from configuration import config
from disrupt import block_pointer_events, restore_pointer_events
from db_utils import get_connection, resolve_song_id_for_ao, init_songs_db
from score_repository import ScoreRepository, PlayCountRepository, PinRepository
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


@dataclass
class PageScoreData:
    """한 페이지에서 추출된 스코어 데이터"""
    scores: list
    difficulty: int
    current_page: int
    total_page: int
    is_date_sorted: bool
    is_search: bool
    record_count: int


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
        
        # Repository instances
        self.db_path = os.path.join(config['general']['cache_path'], 'user_scores.db')
        self._score_repo = ScoreRepository()
        self._play_count_repo = PlayCountRepository()
        self._pin_repo = PinRepository()
        
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
                        self.status.status = 'ready'
                        self.notify_status_changed()
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
        """
        페이지 데이터를 DB에 저장하는 메인 진입점.
        
        Vue 컴포넌트에서 데이터 추출 → 페이지 진행 상태 업데이트 → DB 저장 → 썸네일 저장
        """
        # 1. 페이지 데이터 추출
        page_data = self._extract_page_data()
        if not page_data:
            return
        
        difficulty = page_data.difficulty
        
        # 2. 페이지 진행 상태 업데이트 (날짜순 정렬 + 검색 아닐 때만)
        if not page_data.is_search and page_data.is_date_sorted:
            self.checked_page[difficulty].add(page_data.current_page)
            
            pin_id = self.get_pin_id(difficulty)
            if pin_id:
                with sqlite3.connect(self.db_path) as conn:
                    cursor = conn.cursor()
                    self._check_pin_in_page(cursor, pin_id, page_data)
            else:
                self.total_page[difficulty] = page_data.total_page
        
        self.notify_progress_changed()
        
        # 3. DB 저장
        self.log(f"Found {len(page_data.scores)} play records.")
        
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            try:
                # 테이블 생성
                self._score_repo.ensure_tables(cursor)
                
                # INSERT 데이터 준비
                score_inserts, count_updates = self._prepare_inserts(
                    cursor, page_data.scores, difficulty
                )
                
                # INSERT 실행
                self._score_repo.insert_scores(cursor, score_inserts)
                self._play_count_repo.upsert_counts(cursor, count_updates)
                
                # 전체 페이지 완료 시 Pin 업데이트
                if self.all_pages_checked(difficulty):
                    recent_id = self._score_repo.get_latest_score_id(cursor, difficulty)
                    
                    # 현재 Pin과 다를 때만 업데이트 (로그 스팸 방지)
                    try:
                        current_pin_id = self._pin_repo.get_pin(cursor, difficulty)
                    except Exception:
                        current_pin_id = None
                    
                    if recent_id != current_pin_id:
                        self.save_pin_id(difficulty, recent_id, cursor)
                        self.log(f'Updated pin for {Difficulty(difficulty).name}')
                    
                    self.rise_all_saved_flag(difficulty)
                
                conn.commit()
                
                if len(score_inserts) > 0:
                    self.log(f"Saved/Updated {len(score_inserts)} records in '{self.db_path}'")
                    self.notify_data_changed()
                else:
                    self.log(f"No records to save in '{self.db_path}'")
                    
            except Exception as e:
                self.log(f"Error saving to DB: {e}")
                import traceback
                traceback.print_exc()
            finally:
                # 썸네일 다운로드 (DB 저장과 별개로 수행)
                try:
                    self.save_thumbnails(page_data.scores, difficulty)
                except Exception as e:
                    self.log(f"Thumbnail save error: {e}")
                    import traceback
                    traceback.print_exc()


    def _extract_page_data(self) -> Optional[PageScoreData]:
        """
        Vue 컴포넌트에서 스코어 데이터를 추출합니다.
        
        Returns:
            PageScoreData 또는 None (데이터 없음/중복시)
        """
        target_element = None
        while self.status.is_running:
            try:
                target_element = self.page.wait_for_selector(VUE_COMPONENT_SELECTOR, timeout=1000)
                break
            except Exception:
                continue
        
        if not target_element:
            return None
        
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
            return None
        
        self.previous_user_data = user_data
        
        user_scores = user_data.get('userScores') if user_data else None
        if not user_scores or len(user_scores) == 0:
            self.log('Data save canceled: Current page is empty')
            self.status.status = 'ready'
            self.notify_status_changed()
            return None
        
        return PageScoreData(
            scores=user_scores,
            difficulty=int(user_data['selectedDifficulty']),
            current_page=user_data['currentPage'],
            total_page=user_data['totalPage'],
            is_date_sorted=user_data['dropDownSelectedValue']['value'] == 'date',
            is_search=user_data['searchTerm'] != '',
            record_count=user_data['count']
        )

    def _check_pin_in_page(self, cursor: sqlite3.Cursor, pin_id: int, 
                            page_data: PageScoreData) -> None:
        """
        현재 페이지에서 Pin 곡을 검색해, 존재할 경우 마지막 페이지로 선정, 신규 기록으로 덮어씌워진 경우 Pin을 재선정합니다.
        
        Args:
            cursor: DB 커서
            pin_id: 현재 Pin의 score ID
            page_data: 페이지 스코어 데이터
        """
        pin_record = self._score_repo.get_score_by_id(cursor, pin_id)
        if not pin_record:
            return
        
        pinned_song_id = pin_record.arcaea_id
        pinned_time = pin_record.time_played
        
        for item in page_data.scores:
            if item.get('song_id') != pinned_song_id:
                continue
            
            item_time = item.get('time_played')
            if item_time == pinned_time:
                # Pin 발견 - 이 페이지가 새 데이터의 마지막 페이지
                self.total_page[page_data.difficulty] = page_data.current_page
                self.log('Found last page of new data.')
            else:
                # 같은 곡의 더 최신 기록 존재 → Pin 재선정 필요
                self._find_new_stable_pin(cursor, page_data.difficulty, 
                                           pinned_time, page_data.scores)

    def _find_new_stable_pin(self, cursor: sqlite3.Cursor, difficulty: int,
                              start_time: int, page_items: list):
        """
        기존 Pin이 무효화되었을 때 새로운 안정적인 Pin을 찾습니다.
        
        조건:
        1. 기존 Pin보다 이전(older) 기록이어야 함
        2. 해당 곡의 동일 난이도 내 가장 최신 기록이어야 함
        3. 현재 페이지에 더 최신 기록이 없어야 함
        
        Args:
            cursor: DB 커서
            difficulty: 난이도
            start_time: 탐색 시작 시간 (기존 Pin의 time_played)
            page_items: 현재 페이지의 스코어 아이템들
        """
        search_time = start_time
        
        while True:
            # 조건1: start_time보다 이전인 가장 최신 레코드
            candidate = self._score_repo.find_next_older_score(cursor, difficulty, search_time)
            
            if not candidate:
                # 더 이상 후보 없음 → Pin을 None으로 설정
                self.save_pin_id(difficulty, None, cursor)
                return
            
            c_id, c_song_id, c_time = candidate
            search_time = c_time  # 다음 반복을 위해 커서 이동
            
            # 조건3: 현재 페이지에 이 곡의 더 최신 기록이 있는지 확인
            has_newer_in_page = any(
                item.get('song_id') == c_song_id and item.get('time_played', 0) > c_time
                for item in page_items
            )
            if has_newer_in_page:
                continue
            
            # 조건2: DB에 이 곡의 더 최신 기록이 있는지 확인
            if self._score_repo.has_newer_score_for_song(cursor, c_song_id, difficulty, c_time):
                continue
            
            # 모든 조건 충족 → 새 Pin으로 선정
            self.save_pin_id(difficulty, c_id, cursor)
            return

    def _prepare_inserts(self, cursor: sqlite3.Cursor, 
                          items: list, difficulty: int) -> tuple[list, list]:
        """
        INSERT할 스코어 및 플레이카운트 데이터를 준비합니다.
        
        Args:
            cursor: user_scores.db 커서
            items: 스코어 아이템 리스트
            difficulty: 난이도
            
        Returns:
            (score_inserts, count_updates) 튜플
        """
        score_inserts = []
        count_updates = []
        current_year = datetime.now(timezone.utc).year
        
        # songs.db 연결 (실패해도 계속 진행)
        songs_conn = None
        songs_cursor = None
        try:
            init_songs_db()
            songs_conn = get_connection()
            songs_cursor = songs_conn.cursor()
        except Exception as e:
            self.log(f"Warning: Could not connect to songs.db. Data linking will be skipped. ({e})")
        
        try:
            for item in items:
                diff_val = item.get('difficulty')
                ao_song_id = item.get('song_id')
                time_played = item.get('time_played')
                
                # 타이틀 추출
                title_obj = item.get('title')
                if isinstance(title_obj, dict):
                    title_str = title_obj.get('en', '')
                else:
                    title_str = str(title_obj) if title_obj else ''
                
                # songs.db 연동 (실패해도 계속 진행)
                if songs_cursor:
                    try:
                        resolve_song_id_for_ao(songs_cursor, ao_song_id, title_str)
                    except Exception:
                        pass
                
                score_year = datetime.fromtimestamp(time_played / 1000, tz=timezone.utc).year
                
                # 중복 체크
                is_existing = self._score_repo.score_exists(cursor, ao_song_id, diff_val, time_played)
                
                yearly_play_count = item.get('yearly_play_count') or 0
                
                # 현재 연도 플레이 카운트 업데이트 (스코어 연도와 무관)
                if yearly_play_count > 0:
                    count_updates.append((ao_song_id, diff_val, current_year, yearly_play_count, yearly_play_count))
                
                # 새 스코어만 삽입
                if not is_existing:
                    yearly_play_index = 0
                    
                    if score_year == current_year:
                        yearly_play_index = yearly_play_count
                    else:
                        # 과거 스코어 → DB에서 해당 연도 카운트 조회 후 +1
                        current_db_count = self._play_count_repo.get_yearly_count(
                            cursor, ao_song_id, diff_val, score_year
                        )
                        yearly_play_index = current_db_count + 1

                        # 해당 연도 플레이 카운트 업데이트
                        count_updates.append((ao_song_id, diff_val, score_year, yearly_play_index, yearly_play_index))
                    
                    row = (
                        ao_song_id,
                        diff_val,
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
                    score_inserts.append(row)
        finally:
            if songs_conn:
                songs_conn.commit()
                songs_conn.close()
        
        return score_inserts, count_updates

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