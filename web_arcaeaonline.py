from configuration import config
from disrupt import block_pointer_events, restore_pointer_events
from db_utils import get_connection, resolve_song_id_for_ao, init_songs_db
import sqlite3
import pandas as pd
import keyring
import json
import time
import os
import base64
from datetime import datetime, timezone
from playwright.sync_api import sync_playwright, Page, Browser, BrowserContext, TimeoutError as PlaywrightTimeout
from browser_utils import get_browser
from enum import IntEnum
from dataclasses import dataclass, field
from collections import deque
from typing import Dict, Optional, Set
from common_types import Difficulty

VUE_COMPONENT_SELECTOR = "#app > section > div:nth-child(3)"
LOGIN_COMPONENT_SELECTOR = ".button.login-button"
ARCAEAONLINE_DOMAIN = "arcaea.lowiro.com"
ALBUM_JACKET_SELECTOR = "img.album-jacket"

DIFFICULTY_NAMES = {0: 'pst', 1: 'prs', 2: 'ftr', 3: 'byd', 4: 'etr'}


@dataclass
class AnalysisStatus:
    status: str = 'closed' # 'closed', 'login', 'analyzing', 'ready'
    pin_updates: Dict[int, int] = field(default_factory=dict) # Difficulty -> timestamp
    logs: deque = field(default_factory=lambda: deque(maxlen=50))
    is_running: bool = False


class ThumbnailCollector:
    """Response 인터셉트를 통한 썸네일 수집기"""
    
    def __init__(self):
        self.cached_images: Dict[str, bytes] = {}
    
    def handle_response(self, response):
        """Response 이벤트 핸들러 - webassets 이미지를 캐싱"""
        try:
            url = response.url
            if "webassets.lowiro.com" in url and any(ext in url for ext in ['.jpg', '.png', '.webp']):
                filename = url.split('/')[-1].split('?')[0]
                # Response body를 동기적으로 가져옴
                try:
                    body = response.body()
                    self.cached_images[filename] = body
                except Exception:
                    pass  # Response body를 가져올 수 없는 경우 무시
        except Exception:
            pass
    
    def get_image(self, filename: str) -> Optional[bytes]:
        """캐싱된 이미지 데이터 반환"""
        return self.cached_images.get(filename)
    
    def clear(self):
        """캐시 초기화"""
        self.cached_images.clear()


class ArcaeaOnline:
    def __init__(self):
        self.status = AnalysisStatus()
        self.playwright = None
        self.browser: Optional[Browser] = None
        self.context: Optional[BrowserContext] = None
        self.page: Optional[Page] = None
        self.thumbnail_collector = ThumbnailCollector()
        
        self.log_callback = None
        self.data_changed_callback = None  # Called when data is saved to DB or thumbnails are saved
        self.pin_changed_callback = None   # Called when pin data is updated
        self.status_changed_callback = None # Called when status changes
        
        # State variables
        self.previous_user_data = None
        self.checked_page: Dict[int, Set[int]] = {}
        self.total_page: Dict[int, Optional[int]] = {}
        
        self.current_difficulty = None
        self.current_pageno = None
        self.current_sort = None
        self.current_search_text = ''

        for difficulty in Difficulty:
            self.checked_page[difficulty] = set()
            self.total_page[difficulty] = None
        
        # Initialize pin_updates from database
        self._load_pin_updates_from_db()

    def _load_pin_updates_from_db(self):
        """Load pin update timestamps from database on startup."""
        try:
            score_filepath = os.path.join(config['general']['cache_path'], 'user_scores.db')
            if not os.path.exists(score_filepath):
                return
            
            with sqlite3.connect(score_filepath) as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='pin'")
                if not cursor.fetchone():
                    return
                
                cursor.execute("SELECT difficulty, updated_at FROM pin")
                for row in cursor.fetchall():
                    self.status.pin_updates[row[0]] = row[1]
        except Exception as e:
            print(f"Error loading pin updates from DB: {e}")

    def set_log_callback(self, callback):
        self.log_callback = callback
    
    def set_data_changed_callback(self, callback):
        self.data_changed_callback = callback
    
    def set_pin_changed_callback(self, callback):
        self.pin_changed_callback = callback
    
    def set_status_changed_callback(self, callback):
        self.status_changed_callback = callback
    
    def set_progress_changed_callback(self, callback):
        self.progress_changed_callback = callback
    
    def notify_data_changed(self):
        """Notify that data has been saved (DB records or thumbnails)"""
        if self.data_changed_callback:
            try:
                self.data_changed_callback()
            except Exception as e:
                self.log(f"Data changed callback error: {e}")
    
    def notify_pin_changed(self):
        """Notify that pin data has been updated"""
        if self.pin_changed_callback:
            try:
                self.pin_changed_callback()
            except Exception as e:
                self.log(f"Pin changed callback error: {e}")
    
    def notify_status_changed(self):
        """Notify that status has changed"""
        if self.status_changed_callback:
            try:
                self.status_changed_callback()
            except Exception as e:
                self.log(f"Status changed callback error: {e}")

    def notify_progress_changed(self):
        """Notify that progress data has changed"""
        if hasattr(self, 'progress_changed_callback') and self.progress_changed_callback:
            try:
                self.progress_changed_callback()
            except Exception as e:
                self.log(f"Progress changed callback error: {e}")

    def start(self):
        self.status.is_running = True
        self.status.status = 'login'
        self.notify_status_changed()
        
        lang = 'ko'
        url = f'https://arcaea.lowiro.com/{lang}/profile/scores?page=1'
        
        try:
            self.log("Initializing browser...")
            self.playwright = sync_playwright().start()
            self.browser = get_browser(self.playwright, headless=False)
            self.context = self.browser.new_context(
                viewport={'width': 600, 'height': 1000}
            )
            self.page = self.context.new_page()
            
            # 브라우저 종료 이벤트 리스너
            self._browser_closed = False
            self.page.on("close", lambda: setattr(self, '_browser_closed', True))
            self.context.on("close", lambda: setattr(self, '_browser_closed', True))
            self.browser.on("disconnected", lambda: setattr(self, '_browser_closed', True))
            
            # Response 인터셉트 설정 (썸네일 캐싱용)
            self.page.on("response", self.thumbnail_collector.handle_response)

            self.login(url)
            
            # Reset state
            self.previous_user_data = None
            self.checked_page = {}
            self.total_page = {}

            for difficulty in Difficulty:
                self.checked_page[difficulty] = set()
                self.total_page[difficulty] = None

            self.current_difficulty = None
            self.current_pageno = None
            self.current_sort = None
            self.current_search_text = ''
            
            self.notify_progress_changed()

            while self.status.is_running and not self._browser_closed:
                try:
                    # Polling for page change
                    if self.has_page_changed():
                        pass  # Continue to process
                    else:
                        time.sleep(1)
                        continue
                except Exception as e:
                    # 브라우저 종료 감지
                    if self._is_browser_closed_error(e):
                        break
                    time.sleep(1)
                    continue
                
                if not self.status.is_running:
                    break

                try:
                    block_pointer_events(self.page)
                    
                    self.status.status = 'analyzing'
                    self.notify_status_changed()
                    self.log('New page detected.')

                    # 이미지 로드 대기
                    try:
                        self.page.wait_for_selector(ALBUM_JACKET_SELECTOR, timeout=5000)
                        # 이미지가 실제로 src를 가질 때까지 대기
                        self.page.wait_for_function(
                            f"""() => {{
                                const img = document.querySelector('{ALBUM_JACKET_SELECTOR}');
                                return img && img.src && img.src.includes('webassets.lowiro.com');
                            }}""",
                            timeout=5000
                        )
                        time.sleep(2)  # 이미지 응답 완료 대기
                    except Exception as e:
                        if self._is_browser_closed_error(e):
                            break
                        pass

                    self.save_data()
                except Exception as e:
                    if self._is_browser_closed_error(e):
                        break
                finally:
                    try:
                        restore_pointer_events(self.page)
                    except Exception:
                        pass
                
                # Check if page is still alive
                try:
                    self.page.title()
                except Exception:
                    break

            # 이벤트 리스너로 종료 감지된 경우 로그 출력
            if self._browser_closed:
                self.log('Browser closed by user.\n')

        except Exception as e:
            if self._is_browser_closed_error(e):
                self.log(f'Browser closed by user.\n')
            else:
                self.log(f'Browser terminated: {type(e).__name__}; {e}')
        finally:
            self.stop()
    
    def _is_browser_closed_error(self, e: Exception) -> bool:
        """브라우저/페이지 종료 관련 예외인지 확인"""
        error_msg = str(e).lower()
        closed_indicators = [
            'target closed',
            'browser has been closed',
            'context has been closed', 
            'page has been closed',
            'target page, context or browser has been closed',
            'connection closed',
            'websocket',
        ]
        return any(indicator in error_msg for indicator in closed_indicators)

    def stop(self):
        self.status.is_running = False
        self.status.status = 'closed'
        self.notify_status_changed()
        
        try:
            if self.page:
                self.page.close()
        except Exception:
            pass
        
        try:
            if self.context:
                self.context.close()
        except Exception:
            pass
        
        try:
            if self.browser:
                self.browser.close()
        except Exception:
            pass
        
        try:
            if self.playwright:
                self.playwright.stop()
        except Exception:
            pass
        
        self.page = None
        self.context = None
        self.browser = None
        self.playwright = None

    def login(self, url):        
        # check login session
        login_filename = 'login.dat'
        login_filepath = os.path.join(config['general']['cache_path'], login_filename)
        
        login_exists = os.path.exists(login_filepath) and os.path.isfile(login_filepath)
        
        if login_exists: # session load
            self.log("Loading saved login session...")
            with open(login_filepath, 'r', encoding='utf-8') as f:
                login_cookies = json.load(f)
            
            # Playwright 쿠키 형식으로 변환
            playwright_cookies = []
            for cookie in login_cookies:
                try:
                    pw_cookie = {
                        'name': cookie['name'],
                        'value': cookie['value'],
                        'domain': cookie['domain'],
                        'path': cookie.get('path', '/'),
                    }
                    
                    # Secure 쿠키 처리
                    if cookie.get('secure'):
                        pw_cookie['secure'] = True
                    
                    # SameSite 처리
                    same_site = cookie.get('sameSite', 'Lax')
                    if same_site in ['Strict', 'Lax', 'None']:
                        pw_cookie['sameSite'] = same_site
                    
                    # 민감한 쿠키는 keyring에서 가져오기
                    match cookie['name']:
                        case 'sid':
                            pw_cookie['value'] = keyring.get_password('ArcaeaNap', 'sid') or ''
                        case '__stripe_sid':
                            pw_cookie['value'] = keyring.get_password('ArcaeaNap', '__stripe_sid') or ''
                        case '__stripe_mid':
                            pw_cookie['value'] = keyring.get_password('ArcaeaNap', '__stripe_mid') or ''
                    
                    playwright_cookies.append(pw_cookie)
                except Exception as e:
                    self.log(f'Cookie format error: {e}')
            
            # 쿠키 추가
            self.context.add_cookies(playwright_cookies)
            
            self.page.goto(url)
            
            # Verify session
            try:
                def check_login():
                    # 로그인 버튼이 보이면 세션 만료
                    login_btns = self.page.locator(LOGIN_COMPONENT_SELECTOR)
                    if login_btns.count() > 0:
                        for i in range(login_btns.count()):
                            if login_btns.nth(i).is_visible():
                                return "expired"
                    
                    # Vue 컴포넌트가 보이면 로그인 성공
                    vue_comps = self.page.locator(VUE_COMPONENT_SELECTOR)
                    if vue_comps.count() > 0:
                        for i in range(vue_comps.count()):
                            if vue_comps.nth(i).is_visible():
                                return "verified"
                    
                    return None

                # 30초간 폴링
                start_time = time.time()
                result = None
                while time.time() - start_time < 30:
                    result = check_login()
                    if result:
                        break
                    time.sleep(0.5)
                
                if result == "verified":
                    self.log("Login session verified.")
                else:
                    self.log("Login session expired.")
                    login_exists = False

            except Exception:
                self.log("Login session verification timeout.")
                login_exists = False
            
        if not login_exists: # manual login
            self.log("Waiting for manual login...")
            if ARCAEAONLINE_DOMAIN not in self.page.url:
                self.page.goto(url)

            self.page.wait_for_selector(VUE_COMPONENT_SELECTOR, timeout=300000)
            
            self.log("Login complete.")

            # save login session
            LOGIN_COOKIE = {'sid', '__stripe_sid', '__stripe_mid'}
            SUB_COOKIE = {'_ga', 'ctrcode', 'lang'}
            COOKIE_ESSENTIAL_FIELDS = {'name', 'value', 'domain', 'path', 'expires', 'httpOnly', 'secure', 'sameSite'}
            
            # Playwright로 쿠키 가져오기
            all_cookies = self.context.cookies()
            cookies = []
            
            for cookie in all_cookies:
                if 'lowiro.com' not in cookie.get('domain', ''):
                    continue
                    
                if cookie['name'] in LOGIN_COOKIE:
                    keyring.set_password('ArcaeaNap', cookie['name'], cookie['value'])
                    cookie['value'] = ''
                elif not any(name in cookie['name'] for name in SUB_COOKIE):
                    continue
                
                cookies.append({k: v for k, v in cookie.items() if k in COOKIE_ESSENTIAL_FIELDS})
            
            with open(login_filepath, 'w', encoding='utf-8') as f:
                json.dump(cookies, f, ensure_ascii=False)

            self.log("Login session saved.")

    def has_page_changed(self) -> bool:
        if not self.status.is_running:
            return False
        
        try:
            difficulty_select = self.page.locator('.difficulty-select')
            if 'disabled' in (difficulty_select.get_attribute('class') or ''):
                return False

            new_difficulty = self.page.locator(".difficulty-selector.active .label").text_content()
            new_pageno = self.page.locator('.selected.no-select').text_content()
            new_sort = self.page.locator('div.dropdown > div > span:nth-child(1)').text_content()

            if new_difficulty != self.current_difficulty or new_pageno != self.current_pageno or new_sort != self.current_sort:
                self.current_difficulty = new_difficulty
                self.current_pageno = new_pageno
                self.current_sort = new_sort
                return True

            new_search_text = self.page.locator('div.search-box > input[type=text]').input_value()

            if new_search_text != self.current_search_text:
                time.sleep(0.4)
                waited_new_search_text = self.page.locator('div.search-box > input[type=text]').input_value()
                if new_search_text != waited_new_search_text:
                    return False

                time.sleep(0.4)
                waited_new_search_text = self.page.locator('div.search-box > input[type=text]').input_value()
                if new_search_text == waited_new_search_text:
                    self.current_search_text = new_search_text
                    return True
                
            return False
        except Exception:
            return False

    def save_data(self):
        target_element = None

        while self.status.is_running:
            try:
                target_element = self.page.wait_for_selector(VUE_COMPONENT_SELECTOR, timeout=1000)
                break
            except Exception:
                continue

        try:
            user_data = None
            while self.status.is_running:
                try:
                    user_data = self.page.evaluate("""(element) => {
                        var vue = element.__vue__;
                        return {
                            userScores: vue.userScores,
                            dropDownSelectedValue: vue.dropDownSelectedValue,
                            searchTerm: vue.searchTerm,
                            currentPage: vue.currentPage,
                            selectedDifficulty: vue.selectedDifficulty,
                            totalPage: vue.totalPage,
                            count: vue.count
                        };
                    }""", target_element)
                    break
                except Exception:
                    time.sleep(0.5)
                    continue

            if user_data == self.previous_user_data:
                time.sleep(0.5)
                return

            self.previous_user_data = user_data
            
            user_scores_data = None
            if user_data is not None:
                user_scores_data = user_data['userScores']

            if not user_scores_data or len(user_scores_data) == 0:
                self.log('Data save canceled: Current page is empty')
                self.status.status = 'ready'
                self.notify_status_changed()
                return

            is_datesort = user_data['dropDownSelectedValue']['value'] == 'date'
            is_search = user_data['searchTerm'] != ''

            difficulty = int(user_data['selectedDifficulty'])
            pin_id = self.get_pin_id(difficulty)

            if not is_search and is_datesort:
                self.checked_page[difficulty].add(user_data['currentPage'])
                
                if pin_id:
                    score_filepath = os.path.join(config['general']['cache_path'], 'user_scores.db')
                    pinned_song_date = None
                    pinned_song_id = None
                    
                    with sqlite3.connect(score_filepath) as conn:
                        cursor = conn.cursor()
                        cursor.execute('SELECT arcaea_id, time_played FROM scores WHERE id = ?', (pin_id,))
                        row = cursor.fetchone()
                        if row:
                            pinned_song_id, pinned_song_date = row

                            # iterate user_scores_data and compare name_id with pin data
                            for item in user_scores_data:
                                if item.get('song_id') != pinned_song_id:
                                    continue
                                
                                # if name_id is same, compare the date
                                item_date = item.get('time_played')
                                if item_date == pinned_song_date:
                                    # found pin, pin page is the last page of new data
                                    self.total_page[difficulty] = user_data['currentPage']
                                    self.log('Found last page of new data.')
                                    break

                                else:
                                    # iterate db data - find previous last saved data's id in db, which is not overlaped with newer one, save to pin_id and break
                                    current_search_date = pinned_song_date
                                    found_new_pin = False

                                    while True:
                                        # Find candidate: newest record in DB older than current_search_date
                                        cursor.execute('SELECT id, arcaea_id, time_played FROM scores WHERE difficulty = ? AND time_played < ? ORDER BY time_played DESC LIMIT 1', (difficulty, current_search_date))
                                        candidate_row = cursor.fetchone()

                                        if not candidate_row:
                                            # No more history -> Set Pin to None
                                            self.save_pin_id(difficulty, None, cursor)
                                            found_new_pin = True
                                            break
                                        
                                        c_id, c_song_id, c_time = candidate_row
                                        current_search_date = c_time # Move cursor for next iteration

                                        # Check Overlap (Is there a newer record for this song?)
                                        newer_exists = False

                                        # 1. Check in Fetched Data
                                        for fetched_item in user_scores_data:
                                            if fetched_item.get('song_id') == c_song_id:
                                                f_time = fetched_item.get('time_played', 0)
                                                if f_time > c_time:
                                                    newer_exists = True
                                                    break
                                        
                                        if newer_exists:
                                            continue # Newer exists, try previous

                                        # 2. Check in DB (Is there a newer record for this song?)
                                        cursor.execute('SELECT 1 FROM scores WHERE arcaea_id = ? AND difficulty = ? AND time_played > ? LIMIT 1', (c_song_id, difficulty, c_time))
                                        if cursor.fetchone():
                                            newer_exists = True
                                        
                                        if newer_exists:
                                            continue # Newer exists, try previous
                                        
                                        # If we are here, No Newer Record exists (Stable)
                                        self.save_pin_id(difficulty, c_id, cursor)
                                        found_new_pin = True
                                        break
                                    
                                    if found_new_pin:
                                        break
                                break
                else:
                    self.total_page[difficulty] = user_data['totalPage']
            
            self.notify_progress_changed()

            record_count = user_data['count']

            # save data
            score_filename = 'user_scores.db'
            score_filepath = os.path.join(config['general']['cache_path'], score_filename)

            self.log(f"Found {len(user_scores_data)} play records.")
            
            # Weak dependency for songs.db
            songs_conn = None
            songs_cursor = None
            try:
                init_songs_db()
                songs_conn = get_connection()
                songs_cursor = songs_conn.cursor()
            except Exception as e:
                self.log(f"Warning: Could not connect to songs.db. Data linking will be skipped. ({e})")

            with sqlite3.connect(score_filepath) as conn:
                cursor = conn.cursor()
                
                try:
                    # Create table with new schema
                    cursor.execute('''
                        CREATE TABLE IF NOT EXISTS scores (
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            arcaea_id TEXT,
                            difficulty INTEGER,
                            score INTEGER,
                            shiny_perfect_count INTEGER,
                            perfect_count INTEGER,
                            near_count INTEGER,
                            miss_count INTEGER,
                            health INTEGER,
                            modifier INTEGER,
                            time_played INTEGER,
                            clear_type INTEGER,
                            best_clear_type INTEGER,
                            title TEXT,
                            artist TEXT,
                            user_id INTEGER,
                            yearly_play_index INTEGER,
                            score_below_max INTEGER,
                            UNIQUE(arcaea_id, difficulty, time_played)
                        )
                    ''')
                    
                    # Create play_count table
                    cursor.execute('''
                        CREATE TABLE IF NOT EXISTS play_count (
                            arcaea_id TEXT,
                            difficulty INTEGER,
                            year INTEGER,
                            yearly_play_count INTEGER,
                            PRIMARY KEY (arcaea_id, difficulty, year)
                        )
                    ''')
                    
                    play_score_updates = []
                    play_count_updates = [] # (arcaea_id, diff, year, count)
                    current_year = datetime.now(timezone.utc).year

                    for idx, item in enumerate(user_scores_data):
                        diff_val = item.get('difficulty')
                        title_obj = item.get('title')
                        if isinstance(title_obj, dict):
                            title_str = title_obj.get('en', '')
                        else:
                            title_str = str(title_obj) if title_obj else ''
                        
                        # Weak dependency: Update songs.db if possible
                        ao_song_id = item.get('song_id')
                        
                        if songs_cursor:
                            try:
                                resolve_song_id_for_ao(songs_cursor, ao_song_id, title_str)
                            except Exception as e:
                                pass

                        time_played = item.get('time_played')
                        score_year = datetime.fromtimestamp(time_played / 1000, tz=timezone.utc).year
                        
                        # Check existence first to prevent double counting on past scores
                        # We need to know if we are inserting a NEW score or just seeing an old one.
                        
                        cursor.execute('SELECT 1 FROM scores WHERE arcaea_id = ? AND difficulty = ? AND time_played = ?', (ao_song_id, diff_val, time_played))
                        is_existing_score = cursor.fetchone() is not None
                        
                        yearly_play_count = item.get('yearly_play_count') or 0

                        # Update current year play count if valid (regardless of score year)
                        if yearly_play_count > 0:
                            play_count_updates.append((ao_song_id, diff_val, current_year, yearly_play_count, yearly_play_count))
                        
                        # Only process new scores for insertion
                        if not is_existing_score:
                            yearly_play_index = 0
                            
                            if score_year == current_year:
                                # Current Year: Trust data for index
                                yearly_play_index = yearly_play_count
                            else:
                                # New Past Score -> Increment from DB (for that PAST year)
                                cursor.execute('SELECT yearly_play_count FROM play_count WHERE arcaea_id = ? AND difficulty = ? AND year = ?', 
                                            (ao_song_id, diff_val, score_year))
                                row_pc = cursor.fetchone()
                                current_db_count = row_pc[0] if row_pc else 0
                                yearly_play_index = current_db_count + 1
                                
                                # Update DB for PAST YEAR
                                play_count_updates.append((ao_song_id, diff_val, score_year, yearly_play_index, yearly_play_index))

                            row = (
                                ao_song_id,
                                item.get('difficulty'),
                                item.get('score'),
                                item.get('shiny_perfect_count'),
                                item.get('perfect_count'),
                                item.get('near_count'),
                                item.get('miss_count'),
                                item.get('health'),
                                item.get('modifier'),
                                time_played,
                                item.get('clear_type'),
                                item.get('best_clear_type'),
                                title_str,
                                item.get('artist'),
                                item.get('user_id'),
                                yearly_play_index,
                                item.get('score_below_max')
                            )
                            play_score_updates.append(row)

                    songs_conn.commit()

                    cursor.executemany('''
                        INSERT OR IGNORE INTO scores 
                        (arcaea_id, difficulty, score, shiny_perfect_count, perfect_count, near_count, 
                            miss_count, health, modifier, time_played, clear_type, best_clear_type, 
                            title, artist, user_id, yearly_play_index, score_below_max)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ''', play_score_updates)

                    cursor.executemany('''
                        INSERT INTO play_count (arcaea_id, difficulty, year, yearly_play_count)
                        VALUES (?, ?, ?, ?)
                        ON CONFLICT(arcaea_id, difficulty, year) DO UPDATE SET yearly_play_count = ?
                    ''', play_count_updates)
                    
                    # check all_pages_checked
                    if self.all_pages_checked(difficulty):
                        # find most recent data in current difficulty from db
                        cursor.execute('SELECT id FROM scores WHERE difficulty = ? ORDER BY time_played DESC LIMIT 1', (difficulty,))
                        
                        row = cursor.fetchone()
                        recent_id = None
                        if row:
                            recent_id = row[0]
                            
                        # Check if the newest data is different from the current pin (avoid log spam)
                        try:
                            cursor.execute('SELECT score_id FROM pin WHERE difficulty = ?', (difficulty,))
                            pin_row = cursor.fetchone()
                            current_pin_id = pin_row[0] if pin_row else None
                        except Exception:
                            current_pin_id = None

                        if recent_id != current_pin_id:
                            self.save_pin_id(difficulty, recent_id, cursor)
                            self.log(f'Updated pin for {Difficulty(difficulty).name}')
                        
                        self.rise_all_saved_flag(difficulty)

                    conn.commit()
                    if len(play_score_updates) > 0:
                        self.log(f"Saved/Updated {len(play_score_updates)} records in '{score_filepath}'")
                        self.notify_data_changed()
                    else:
                        self.log(f"No records to save in '{score_filepath}'")
                except Exception as e:
                    self.log(f"Error saving to DB: {e}")
                    import traceback
                    traceback.print_exc()
                finally:
                    if songs_conn:
                        songs_conn.commit()
                        songs_conn.close()
                    
                    # 썸네일 다운로드 (DB 저장과 별개로 수행)
                    try:
                        self.save_thumbnails(user_scores_data, difficulty)
                    except Exception as e:
                        self.log(f"Thumbnail save error: {e}")
                        import traceback
                        traceback.print_exc()
        
        finally:
            if self.status.status == 'analyzing':
                self.status.status = 'ready'
                self.notify_status_changed()

    def save_thumbnails(self, user_scores_data: list, difficulty: int):
        """
        현재 페이지의 썸네일 이미지를 저장
        파일명 형식: {song_id}_{difficulty}.jpg
        Response 인터셉트 방식으로 캐싱된 이미지 사용
        """
        # 썸네일 저장 경로
        thumbnails_dir = os.path.join(config['general']['cache_path'], 'thumbnails')
        os.makedirs(thumbnails_dir, exist_ok=True)
        
        difficulty_name = DIFFICULTY_NAMES.get(difficulty, 'unknown')
        
        # 이미지 요소 가져오기
        try:
            img_elements = self.page.locator(ALBUM_JACKET_SELECTOR).all()
        except Exception as e:
            self.log(f"Thumbnail: Failed to find image elements: {e}")
            return
        
        if not img_elements:
            self.log(f"Thumbnail: No image elements found")
            return
        
        # Vue 데이터와 이미지 요소 매칭 (순서 기반)
        saved_count = 0
        skipped_count = 0
        not_found_count = 0
        
        for score, img_elem in zip(user_scores_data, img_elements):
            try:
                song_id = score.get('song_id')
                if not song_id:
                    continue
                
                # 저장할 파일 경로
                filename = f"{song_id}_{difficulty_name}.jpg"
                filepath = os.path.join(thumbnails_dir, filename)
                
                # 이미 존재하면 스킵
                if os.path.exists(filepath):
                    skipped_count += 1
                    continue
                
                # 이미지 URL에서 파일명 추출
                img_url = img_elem.get_attribute('src')
                if not img_url:
                    continue
                
                url_filename = img_url.split('/')[-1].split('?')[0]
                
                # 캐싱된 이미지 찾기
                img_data = self.thumbnail_collector.get_image(url_filename)
                
                if img_data:
                    with open(filepath, 'wb') as f:
                        f.write(img_data)
                    saved_count += 1
                    self.notify_data_changed()
                else:
                    not_found_count += 1
                    
            except Exception as e:
                continue
        
        if saved_count > 0 or skipped_count > 0 or not_found_count > 0:
            self.log(f"Thumbnail: saved={saved_count}, skipped={skipped_count}, not_found={not_found_count}")

    def get_pin_id(self, difficulty) -> int | None:
        score_filepath = os.path.join(config['general']['cache_path'], 'user_scores.db')
        try:
            with sqlite3.connect(score_filepath) as conn:
                cursor = conn.cursor()
                try:
                    cursor.execute('SELECT score_id FROM pin WHERE difficulty = ?', (difficulty,))
                except sqlite3.OperationalError:
                    cursor.execute('DROP TABLE IF EXISTS pin')
                    cursor.execute('CREATE TABLE pin (difficulty INTEGER PRIMARY KEY, score_id INTEGER, updated_at INTEGER)')
                    cursor.execute('SELECT score_id FROM pin WHERE difficulty = ?', (difficulty,))
                
                row = cursor.fetchone()
                
                if row is None:
                    cursor.execute('CREATE TABLE IF NOT EXISTS pin (difficulty INTEGER PRIMARY KEY, score_id INTEGER, updated_at INTEGER)')
                    cursor.execute('INSERT OR IGNORE INTO pin (difficulty, score_id) VALUES (?, NULL)', (difficulty,))
                    conn.commit()
                    return None
                return row[0]
                
        except Exception as e:
            self.log(f"get_pin_id Error: {e}")
            return None

    def save_pin_id(self, difficulty, score_id, cursor):
        try:
            cursor.execute('CREATE TABLE IF NOT EXISTS pin (difficulty INTEGER PRIMARY KEY, score_id INTEGER, updated_at INTEGER)')
            
            current_time = int(time.time() * 1000)
            cursor.execute('INSERT OR REPLACE INTO pin (difficulty, score_id, updated_at) VALUES (?, ?, ?)', (difficulty, score_id, current_time))
            
            # Update status object
            self.status.pin_updates[difficulty] = current_time
            
            # Notify UI to refresh pin dates
            self.notify_pin_changed()
            
        except Exception as e:
            self.log(f"save_pin_id Error: {e}")

    def all_pages_checked(self, difficulty):
        if not self.total_page[difficulty]:
            return False
        return set(range(1, self.total_page[difficulty] + 1)) <= self.checked_page[difficulty]

    def rise_all_saved_flag(self, difficulty):
        self.checked_page[difficulty] = set()
        self.total_page[difficulty] = None

    def log(self, message: str):
        timestamp = time.strftime("[%H:%M:%S]")
        formatted_message = f"{timestamp} {message}"
        self.status.logs.append(formatted_message)
        print(formatted_message)
        
        if self.log_callback:
            self.log_callback(formatted_message)


def check_db_data():
    DB_FILENAME = 'user_scores.db'
    DB_FILEPATH = os.path.join(config['general']['cache_path'], DB_FILENAME)
    if not os.path.exists(DB_FILEPATH):
        print(f"Error: '{DB_FILEPATH}' not found.")
        return

    try:
        conn = sqlite3.connect(DB_FILEPATH)

        query = "SELECT * FROM scores"
        df = pd.read_sql(query, conn)
        conn.close()

        if df.empty:
            print("DB is empty.")
            return

        if 'time_played' in df.columns:
            df['play_date'] = pd.to_datetime(df['time_played'], unit='ms')
            cols = ['play_date', 'title', 'difficulty', 'score'] + [c for c in df.columns if c not in ['play_date', 'title', 'difficulty', 'score']]
            df = df[cols]

        print(f"=== Total records: {len(df)} ===")
        print("\n1. Head 5:")
        print(df.head())

        print("\n2. Info:")
        print(df.info())

        print("\n3. Describe:")
        pd.set_option('display.float_format', lambda x: '%.2f' % x)
        print(df[['score', 'shiny_perfect_count', 'miss_count']].describe())
        
        sample_song_id = df['arcaea_id'].iloc[0]
        print(f"\n4. History for song ({sample_song_id}):")
        print(df[df['arcaea_id'] == sample_song_id][['play_date', 'title', 'score', 'perfect_count']])

    except Exception as e:
        print(f"Error checking DB: {e}")


if __name__=='__main__':
    analyzer = ArcaeaOnline()
    analyzer.start()
    # check_db_data()