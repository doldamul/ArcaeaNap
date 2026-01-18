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
from browserdriver import get_driver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException, NoSuchWindowException, WebDriverException
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
    status: str = 'login' # 'login', 'ready', 'analyzing'
    pin_updates: Dict[int, int] = field(default_factory=dict) # Difficulty -> timestamp
    logs: deque = field(default_factory=lambda: deque(maxlen=50))
    is_running: bool = False

class ArcaeaOnline:
    def __init__(self):
        self.status = AnalysisStatus()
        self.driver = None
        self.log_callback = None
        self.data_changed_callback = None  # Called when data is saved to DB or thumbnails are saved
        
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

    def set_log_callback(self, callback):
        self.log_callback = callback
    
    def set_data_changed_callback(self, callback):
        self.data_changed_callback = callback
    
    def notify_data_changed(self):
        """Notify that data has been saved (DB records or thumbnails)"""
        if self.data_changed_callback:
            try:
                self.data_changed_callback()
            except Exception as e:
                self.log(f"Data changed callback error: {e}")

    def start(self):
        self.status.is_running = True
        lang = 'ko'
        url = f'https://arcaea.lowiro.com/{lang}/profile/scores?page=1'
        
        try:
            self.log("Initializing browser...")
            self.driver = get_driver(enable_performance_log=True)
            assert self.driver is not None, "unsupported browser"

            self.driver.set_window_size(600, 1000)
            
            # CDP Network 도메인 활성화 (로그 수집을 위해 필수) - login 전에 위치 복구
            try:
                self.driver.execute_cdp_cmd('Network.enable', {})
            except Exception as e:
                self.log(f"Failed to enable Network domain: {e}")

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

            while self.status.is_running:
                try:
                    # Polling for page change with short timeout to check is_running frequency
                    WebDriverWait(self.driver, 1).until(self.has_page_changed)
                except TimeoutException:
                    continue
                
                if not self.status.is_running:
                    break

                self.log('New page detected.')
                
                # Network 도메인 재활성화 (네비게이션 후 풀릴 수 있음)
                try:
                    self.driver.execute_cdp_cmd('Network.enable', {})
                except:
                    pass
            
                # 이미지 로드 대기 후 Performance Log 파싱 (save_data 전에)
                import time as _time
                try:
                    # album-jacket 이미지가 나타날 때까지 대기
                    WebDriverWait(self.driver, 5).until(
                        EC.presence_of_element_located((By.CSS_SELECTOR, ALBUM_JACKET_SELECTOR))
                    )
                    # 이미지가 실제로 src를 가질 때까지 대기
                    WebDriverWait(self.driver, 5).until(
                        lambda d: d.find_element(By.CSS_SELECTOR, ALBUM_JACKET_SELECTOR).get_attribute('src') and 
                                  'webassets.lowiro.com' in d.find_element(By.CSS_SELECTOR, ALBUM_JACKET_SELECTOR).get_attribute('src')
                    )
                    _time.sleep(2)  # 이미지 응답 완료 대기 (네트워크 로그 기록 시간)
                except:
                    pass
                
                thumbnail_request_ids = self.parse_thumbnail_request_ids()
                if thumbnail_request_ids:
                    self.log(f"Thumbnail: Found {len(thumbnail_request_ids)} image requestIds")
                else:
                    self.log("Thumbnail: No image requestIds found")

                try:
                    block_pointer_events(self.driver)
                    self.save_data(thumbnail_request_ids)
                finally:
                    restore_pointer_events(self.driver)
                
                # Check directly if driver is alive
                self.driver.title
                
                # 다음 페이지 로드 대비 Network 활성화
                try:
                    self.driver.execute_cdp_cmd('Network.enable', {})
                except:
                    pass
        except (NoSuchWindowException, WebDriverException, AttributeError) as e:
            msg = str(e).lower()
            if isinstance(e, NoSuchWindowException) or 'disconnected' in msg or 'not reachable' in msg or 'target closed' in msg or 'get_attribute' in msg:
                self.log(f'Browser closed by user.\n')
            else:
                self.log(f'Browser terminated: {type(e).__name__}; {e}')
        except Exception as e:
            self.log(f'Browser terminated: {type(e).__name__}; {e}')
        finally:
            self.stop()

    def stop(self):
        self.status.is_running = False
        self.status.status = 'login'
        if self.driver:
            try: self.driver.quit()
            except: pass
            self.driver = None

    def login(self, url):        
        # check login session
        login_filename = 'login.dat'
        login_filepath = os.path.join(config['general']['cache_path'], login_filename)
        
        login_exists = os.path.exists(login_filepath) and os.path.isfile(login_filepath) and config['general']['auto_login']
        
        if login_exists: # session load
            self.log("Loading saved login session...")
            with open(login_filepath, 'r', encoding='utf-8') as f:
                login_cookies = json.load(f)
            
            self.driver.execute_cdp_cmd('Network.enable', {})
            
            for cookie in login_cookies:
                try:
                    match cookie['name']:
                        case 'sid':
                            cookie['value'] = keyring.get_password('ArcaeaNap', 'sid')
                        case '__stripe_sid':
                            cookie['value'] = keyring.get_password('ArcaeaNap', '__stripe_sid')
                        case '__stripe_mid':
                            cookie['value'] = keyring.get_password('ArcaeaNap', '__stripe_mid')
                    
                    self.driver.execute_cdp_cmd('Network.setCookie', cookie)
                except Exception as e:
                    self.log(f'Cookie injection error: {e}')
            
            # Network.disable 호출 제거 - 로그 수집 유지
            # self.driver.execute_cdp_cmd('Network.disable', {})
            
            # 페이지 로드 전 Network 활성화 재확인
            try:
                self.driver.execute_cdp_cmd('Network.enable', {})
            except:
                pass

            self.driver.get(url)
            
            # Verify session
            try:
                def check_login(d):
                    login_btns = d.find_elements(By.CSS_SELECTOR, LOGIN_COMPONENT_SELECTOR)
                    if any(btn.is_displayed() for btn in login_btns):
                        return "expired"
                    
                    vue_comps = d.find_elements(By.CSS_SELECTOR, VUE_COMPONENT_SELECTOR)
                    if any(comp.is_displayed() for comp in vue_comps):
                        return "verified"
                    
                    return False

                result = WebDriverWait(self.driver, 30).until(check_login)
                
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
            if ARCAEAONLINE_DOMAIN not in self.driver.current_url:
                self.driver.get(url)

            WebDriverWait(self.driver, 300).until(
                EC.presence_of_element_located((By.CSS_SELECTOR, VUE_COMPONENT_SELECTOR))
            )
            
            self.log("Login complete.")

            # save login session
            LOGIN_COOKIE = {'sid', '__stripe_sid', '__stripe_mid'}
            SUB_COOKIE = {'_ga', 'ctrcode', 'lang'}
            COOKIE_ESSENTIAL_FIELDS = {'name', 'value', 'domain', 'path', 'expires', 'expiry', 'httpOnly', 'secure', 'sameSite'}
            
            data = self.get_all_cookies_chromium()
            cookies = []
            
            for cookie in data:
                if cookie['name'] in LOGIN_COOKIE:
                    keyring.set_password('ArcaeaNap', cookie['name'], cookie['value'])
                    cookie['value'] = ''
                elif not any(name in cookie['name'] for name in SUB_COOKIE):
                    continue
                
                cookies.append({k: v for k, v in cookie.items() if k in COOKIE_ESSENTIAL_FIELDS})
            
            with open(login_filepath, 'w', encoding='utf-8') as f:
                json.dump(cookies, f, ensure_ascii=False)

            self.log("Login session saved.")

    def has_page_changed(self, driver):
        if not self.status.is_running:
            return False
        
        is_disabled = 'disabled' in (driver.find_element(By.CSS_SELECTOR, '.difficulty-select').get_attribute('class') or '')
        if is_disabled:
            return False

        new_difficulty = driver.find_element(By.CSS_SELECTOR, ".difficulty-selector.active .label").text
        new_pageno = driver.find_element(By.CSS_SELECTOR, '.selected.no-select').text
        new_sort = driver.find_element(By.CSS_SELECTOR, 'div.dropdown > div > span:nth-child(1)').text

        if new_difficulty != self.current_difficulty or new_pageno != self.current_pageno or new_sort != self.current_sort:
            self.current_difficulty = new_difficulty
            self.current_pageno = new_pageno
            self.current_sort = new_sort
            return True

        new_search_text = driver.find_element(By.CSS_SELECTOR, 'div.search-box > input[type=text]').get_attribute('value')

        if new_search_text != self.current_search_text:
            time.sleep(0.4)
            waited_new_search_text = driver.find_element(By.CSS_SELECTOR, 'div.search-box > input[type=text]').get_attribute('value')
            if new_search_text != waited_new_search_text:
                return False

            time.sleep(0.4)
            waited_new_search_text = driver.find_element(By.CSS_SELECTOR, 'div.search-box > input[type=text]').get_attribute('value')
            if new_search_text == waited_new_search_text:
                self.current_search_text = new_search_text
                return True
            
        return False

    def save_data(self, thumbnail_request_ids: dict = None):
        self.status.status = 'analyzing'
        target_element = None
        wait = WebDriverWait(self.driver, 1)

        while self.status.is_running:
            try:
                target_element = wait.until(
                    EC.presence_of_element_located((By.CSS_SELECTOR, VUE_COMPONENT_SELECTOR))
                )
            except Exception:
                continue

            break

        try:
            user_data = None
            while self.status.is_running:
                try:
                    user_data = wait.until(
                        lambda d: d.execute_script("""
                            var vue = arguments[0].__vue__;
                            return {
                                userScores: vue.userScores,
                                dropDownSelectedValue: vue.dropDownSelectedValue,
                                searchTerm: vue.searchTerm,
                                currentPage: vue.currentPage,
                                selectedDifficulty: vue.selectedDifficulty,
                                totalPage: vue.totalPage,
                                count: vue.count
                            };
                        """, target_element)
                    )
                except Exception:
                    continue

                if user_data == self.previous_user_data:
                    time.sleep(0.5)
                    continue

                self.previous_user_data = user_data
                break
            
            user_scores_data = None
            if user_data is not None:
                user_scores_data = user_data['userScores']

            if not user_scores_data or len(user_scores_data) == 0:
                self.log('Data save canceled: Current page is empty')
                self.status.status = 'ready'
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
                        self.save_thumbnails(user_scores_data, difficulty, thumbnail_request_ids)
                    except Exception as e:
                        self.log(f"Thumbnail save error: {e}")
                        import traceback
                        traceback.print_exc()
        
        finally:
            if self.status.status == 'analyzing':
                self.status.status = 'ready'

    def parse_thumbnail_request_ids(self) -> dict[str, tuple[str, bool]]:
        """
        Performance Log에서 webassets 이미지의 requestId를 파싱
        Returns:
            dict: {filename: (requestId, fromDiskCache)}
        """
        result = {}
        
        try:
            logs = self.driver.get_log("performance")
            
            for entry in logs:
                try:
                    message = json.loads(entry["message"])["message"]
                    
                    if message.get("method") == "Network.responseReceived":
                        params = message.get("params", {})
                        response = params.get("response", {})
                        url = response.get("url", "")
                        
                        if "webassets.lowiro.com" in url and any(ext in url for ext in ['.jpg', '.png', '.webp']):
                            request_id = params.get("requestId")
                            from_disk_cache = response.get("fromDiskCache", False) or response.get("fromServiceWorker", False)
                            
                            filename = url.split('/')[-1].split('?')[0]
                            result[filename] = (request_id, from_disk_cache)
                except:
                    continue
            
            return result
            
            # if result:
            #     self.log(f"Thumbnail: Found {len(result)} image requestIds in performance log")
            return result
        except Exception as e:
            self.log(f"Error parsing performance log: {e}")
            return {}

    def download_thumbnail_via_cdp(self, request_id: str) -> bytes | None:
        """CDP를 통해 브라우저 메모리에서 이미지 데이터 가져오기"""
        try:
            response_body = self.driver.execute_cdp_cmd(
                "Network.getResponseBody",
                {"requestId": request_id}
            )
            
            body = response_body.get("body")
            is_base64 = response_body.get("base64Encoded", False)
            
            if body:
                if is_base64:
                    return base64.b64decode(body)
                else:
                    return body.encode('utf-8')
            
            return None
        except Exception as e:
            return None

    def save_thumbnails(self, user_scores_data: list, difficulty: int, request_id_map: dict):
        """
        현재 페이지의 썸네일 이미지를 저장
        파일명 형식: {song_id}_{difficulty}.jpg
        """
        if not request_id_map:
            return
        
        # 썸네일 저장 경로
        thumbnails_dir = os.path.join(config['general']['cache_path'], 'thumbnails')
        os.makedirs(thumbnails_dir, exist_ok=True)
        
        difficulty_name = DIFFICULTY_NAMES.get(difficulty, 'unknown')
        
        # 이미지 요소 가져오기
        try:
            img_elements = self.driver.find_elements(By.CSS_SELECTOR, ALBUM_JACKET_SELECTOR)
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
                
                # 이미 존재하면 스킵 (파일 존재 확인은 ~0.01ms로 빠름)
                if os.path.exists(filepath):
                    skipped_count += 1
                    continue
                
                # 이미지 URL에서 파일명 추출
                img_url = img_elem.get_attribute('src')
                if not img_url:
                    continue
                
                url_filename = img_url.split('/')[-1].split('?')[0]
                
                # requestId 찾기
                if url_filename not in request_id_map:
                    not_found_count += 1
                    continue
                
                request_id, _ = request_id_map[url_filename]
                
                # CDP로 이미지 다운로드
                img_data = self.download_thumbnail_via_cdp(request_id)
                
                if img_data:
                    with open(filepath, 'wb') as f:
                        f.write(img_data)
                    saved_count += 1
                    self.notify_data_changed()
                    
            except Exception as e:
                continue
        
        if saved_count > 0 or skipped_count > 0 or not_found_count > 0:
            self.log(f"Thumbnail: saved={saved_count}, skipped={skipped_count}, not_found={not_found_count}")

    def get_all_cookies_chromium(self):
        try:
            self.driver.execute_cdp_cmd('Network.enable', {})
            result = self.driver.execute_cdp_cmd('Network.getAllCookies', {})
            cookies = result['cookies']
        except Exception as e:
            self.log(f'Error getting cookies via CDP: {e}')
            raise
        finally:
            try: self.driver.execute_cdp_cmd('Network.disable', {})
            except: pass
        
        target_cookies = []
        for cookie in cookies:
            if 'lowiro.com' in cookie['domain']:
                target_cookies.append(cookie)
                
        return target_cookies

    def get_pin_id(self, difficulty) -> int | None:
        score_filepath = os.path.join(config['general']['cache_path'], 'user_scores.db')
        try:
            with sqlite3.connect(score_filepath) as conn:
                cursor = conn.cursor()
                try:
                    cursor.execute('SELECT score_id FROM pin WHERE difficulty = ?', (difficulty,))
                except sqlite3.OperationalError:
                    cursor.execute('DROP TABLE IF EXISTS pin')
                    cursor.execute('CREATE TABLE pin (difficulty INTEGER PRIMARY KEY, score_id INTEGER)')
                    cursor.execute('SELECT score_id FROM pin WHERE difficulty = ?', (difficulty,))
                
                row = cursor.fetchone()
                
                if row is None:
                    cursor.execute('CREATE TABLE IF NOT EXISTS pin (difficulty INTEGER PRIMARY KEY, score_id INTEGER)')
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