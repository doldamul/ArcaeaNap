from utils.configuration import config
from utils.disrupt import block_pointer_events, restore_pointer_events
from repositories.song_repository import (
    get_connection,
    resolve_song_id_for_ao,
    init_songs_db,
    update_song_titles_from_ao,
)
from repositories.score_repository import ScoreRepository, PlayCountRepository, PinRepository
import sqlite3
import time
import os
import re
import base64
from datetime import datetime, timezone
from playwright.sync_api import sync_playwright, Page, Browser, BrowserContext, TimeoutError as PlaywrightTimeout
from utils.browser_utils import get_browser
from enum import IntEnum
from dataclasses import dataclass, field
from collections import deque
from typing import Dict, Optional, Set
from models.types import Difficulty
from services.connection_store import get_provider, set_provider
from services.keyring_store import get_secret, set_secret
from services.write_conflict_guard import mark_write_activity, clear_write_activity

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


@dataclass
class CountModeState:
    """Play Count Analyze Mode 전용 상태. 기존 로직과 완전히 분리."""
    checked_pages: Dict[int, Set[int]] = field(default_factory=dict)
    total_pages: Dict[int, Optional[int]] = field(default_factory=dict)
    completed: Set[int] = field(default_factory=set)

    def __post_init__(self):
        for d in Difficulty:
            if d not in self.checked_pages:
                self.checked_pages[d] = set()
            if d not in self.total_pages:
                self.total_pages[d] = None

    def reset_progress(self):
        """세션 리셋 시 진행도 초기화 (completed는 보존)"""
        for d in self.checked_pages:
            self.checked_pages[d] = set()
            self.total_pages[d] = None

    def reset_all(self):
        """모드 해제 시 전체 초기화"""
        self.reset_progress()
        self.completed.clear()

    def all_pages_checked(self, difficulty: int) -> bool:
        total = self.total_pages.get(difficulty)
        if not total:
            return False
        return set(range(1, total + 1)) <= self.checked_pages.get(difficulty, set())


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
        self._score_repo = ScoreRepository()
        self._play_count_repo = PlayCountRepository()
        self._pin_repo = PinRepository()
        
        self.log_callback = None
        self.data_changed_callback = None  # Called when data is saved to DB or thumbnails are saved
        self.pin_changed_callback = None   # Called when pin data is updated
        self.status_changed_callback = None # Called when status changes
        self.session_reset_callback = None  # Called when session is auto-reset
        self.login_completed_callback = None  # Called when login is completed
        
        # State variables
        self.previous_user_data = None
        self.checked_page: Dict[int, Set[int]] = {}
        self.total_page: Dict[int, Optional[int]] = {}
        
        self.current_difficulty = None
        self.current_pageno = None
        self.current_sort = None
        self.current_search_text = ''
        self._difficulty_tag: Optional[str] = None

        # Session auto-reset detection
        self.scanned_pages: Dict[int, Dict[int, list]] = {}  # difficulty -> {page -> [time_played]}

        for difficulty in Difficulty:
            self.checked_page[difficulty] = set()
            self.total_page[difficulty] = None
            self.scanned_pages[difficulty] = {}

        # Play Count Analyze Mode 전용 상태
        self.count_mode = CountModeState()
        self._mode_toggle_pending = False
        self._pin_notify_pending = False
        
        # Initialize pin_updates from database
        self._load_pin_updates_from_db()

    @property
    def db_path(self):
        return os.path.join(config['general']['cache_path'], 'user_scores.db')

    def _load_pin_updates_from_db(self):
        """Load pin update timestamps from database on startup."""
        try:
            if not os.path.exists(self.db_path):
                return
            
            with sqlite3.connect(self.db_path, timeout=10) as conn:
                cursor = conn.cursor()
                pin_updates = self._pin_repo.get_all_pin_updates(cursor)
                self.status.pin_updates.update(pin_updates)
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
    
    def set_session_reset_callback(self, callback):
        self.session_reset_callback = callback
    
    def set_login_completed_callback(self, callback):
        self.login_completed_callback = callback

    def set_play_count_mode(self, enabled: bool):
        """Play Count Analyze Mode 토글"""
        config['general']['analyze_mode'] = enabled
        self.count_mode.reset_all()
        self.log(f"Play Count Analyze Mode: {'ON' if enabled else 'OFF'}", with_tag=False)

        # 분석 스레드 실행 중일 때만 플래그 설정 (브라우저가 켜져 있어야 리셋 가능)
        # 닫혀있다면 다음 start() 시 자연스럽게 새 세션으로 시작되므로 리셋 불필요
        if self.status.is_running and self.status.status not in ('closed',):
            self._mode_toggle_pending = True

        self.notify_progress_changed()

    @property
    def play_count_mode(self) -> bool:
        return config['general']['analyze_mode']
    
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
        mark_write_activity("user_scores_db", "analysis_session")
        
        lang = 'en'
        url = f'https://arcaea.lowiro.com/{lang}/profile/scores?page=1'
        
        try:
            self.log("Initializing browser...")
            self.playwright = sync_playwright().start()
            self.browser = get_browser(self.playwright, headless=False)
            
            self.context = self.browser.new_context(
                viewport={'width': 600, 'height': 1000}
            )
            self.page = self.context.new_page()
            
            # Cache browser PID via window title marker (browser-agnostic)
            self._browser_pid = self._detect_browser_pid()
            
            # Response 인터셉트 설정 (썸네일 캐싱용)
            self.setup_browser_listeners()

            self.login(url)
            
            # Reset state
            self.previous_user_data = None
            self.checked_page = {}
            self.total_page = {}
            self.scanned_pages = {}

            for difficulty in Difficulty:
                self.checked_page[difficulty] = set()
                self.total_page[difficulty] = None
                self.scanned_pages[difficulty] = {}

            self.current_difficulty = None
            self.current_pageno = None
            self.current_sort = None
            self.current_search_text = ''
            self._difficulty_tag = None
            
            self.notify_progress_changed()

            while self.status.is_running and not self._browser_closed:
                try:
                    # Play Count Mode 토글 감지 → 분석 스레드에서 안전하게 세션 리셋
                    if self._mode_toggle_pending:
                        self._mode_toggle_pending = False
                        self._reset_analysis_session(
                            current_page=self.current_pageno, 
                            msg="Play Count Analyze Mode changed. Session refreshed"
                        )
                        continue

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
                    self.log('New page detected.', with_tag=False)

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
                self.log('Browser closed by user.', with_tag=False)

        except Exception as e:
            if self._is_browser_closed_error(e):
                self.log('Browser closed by user.', with_tag=False)
            else:
                self.log(f'Browser terminated: {type(e).__name__}; {e}', with_tag=False)
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

    def cancel(self):
        """Signal cancellation without closing resources (thread-safe)."""
        self.status.is_running = False
        self.status.status = 'closed'
        self.notify_status_changed()
        clear_write_activity("user_scores_db")

    def stop(self):
        self.status.is_running = False
        self.status.status = 'closed'
        self.notify_status_changed()
        clear_write_activity("user_scores_db")
        
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
        self._difficulty_tag = None

    def _detect_browser_pid(self):
        """Detect browser PID by temporarily setting a unique window title marker.
        
        Sets document.title to a unique string, finds the OS window with that title
        via EnumWindows, extracts the PID, then restores the original title.
        Works with any browser (Chromium, Firefox, WebKit).
        """
        import ctypes
        import ctypes.wintypes
        import time as _time

        TITLE_MARKER = "ArcaeaNap_BrowserID"

        try:
            # 1. Set unique title marker
            self.page.evaluate(f"document.title = '{TITLE_MARKER}'")
            _time.sleep(0.3)  # Wait for window title to update

            # 2. Find window with the marker title
            user32 = ctypes.windll.user32
            EnumWindows = user32.EnumWindows
            GetWindowTextW = user32.GetWindowTextW
            GetWindowTextLengthW = user32.GetWindowTextLengthW
            GetWindowThreadProcessId = user32.GetWindowThreadProcessId
            IsWindowVisible = user32.IsWindowVisible

            WNDENUMPROC = ctypes.WINFUNCTYPE(
                ctypes.wintypes.BOOL, ctypes.wintypes.HWND, ctypes.wintypes.LPARAM
            )

            found_pid = None

            def enum_callback(hwnd, lparam):
                nonlocal found_pid
                if IsWindowVisible(hwnd):
                    length = GetWindowTextLengthW(hwnd)
                    if length > 0:
                        buf = ctypes.create_unicode_buffer(length + 1)
                        GetWindowTextW(hwnd, buf, length + 1)
                        if TITLE_MARKER in buf.value:
                            proc_id = ctypes.wintypes.DWORD()
                            GetWindowThreadProcessId(hwnd, ctypes.byref(proc_id))
                            found_pid = proc_id.value
                            return False  # stop enumeration
                return True  # continue

            EnumWindows(WNDENUMPROC(enum_callback), 0)

            # 3. Restore original title
            self.page.evaluate("document.title = ''")

            return found_pid

        except Exception as e:
            print(f"Failed to detect browser PID: {e}")
            return None

    def bring_to_front(self):
        """Bring the browser OS window to the foreground using cached PID."""
        try:
            import ctypes
            import ctypes.wintypes

            pid = getattr(self, '_browser_pid', None)
            if not pid:
                return

            user32 = ctypes.windll.user32
            EnumWindows = user32.EnumWindows
            GetWindowThreadProcessId = user32.GetWindowThreadProcessId
            IsWindowVisible = user32.IsWindowVisible
            SetForegroundWindow = user32.SetForegroundWindow
            ShowWindow = user32.ShowWindow
            SW_RESTORE = 9

            WNDENUMPROC = ctypes.WINFUNCTYPE(
                ctypes.wintypes.BOOL, ctypes.wintypes.HWND, ctypes.wintypes.LPARAM
            )

            target_hwnd = None

            def enum_callback(hwnd, lparam):
                nonlocal target_hwnd
                if IsWindowVisible(hwnd):
                    proc_id = ctypes.wintypes.DWORD()
                    GetWindowThreadProcessId(hwnd, ctypes.byref(proc_id))
                    if proc_id.value == pid:
                        target_hwnd = hwnd
                        return False  # stop enumeration
                return True  # continue

            EnumWindows(WNDENUMPROC(enum_callback), 0)

            if target_hwnd:
                ShowWindow(target_hwnd, SW_RESTORE)
                SetForegroundWindow(target_hwnd)
        except Exception as e:
            print(f"Failed to bring browser to front: {e}")

    
    def setup_browser_listeners(self):
        """Set up browser event listeners for close detection and response interception."""
        if not self.page or not self.context or not self.browser:
             return

        self._browser_closed = False
        self.page.on("close", lambda: setattr(self, '_browser_closed', True))
        self.context.on("close", lambda: setattr(self, '_browser_closed', True))
        self.browser.on("disconnected", lambda: setattr(self, '_browser_closed', True))
        
        # Response intercept
        self.page.on("response", self.thumbnail_collector.handle_response)

    def login(self, url):        
        # Initialize browser closed flag if not set (needed for direct login calls)
        if not hasattr(self, '_browser_closed'):
            self._browser_closed = False

        login_exists = False
        login_cookies = []
        
        try:
            ao_info = get_provider('arcaea_online')
            if ao_info.get('connected', False) and isinstance(ao_info.get('cookies'), list):
                login_exists = True
                login_cookies = ao_info['cookies']
        except Exception as e:
            self.log(f'Error loading connections: {e}')
        
        if login_exists: # session load
            self.log("Loading saved login session...")
            
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
                            pw_cookie['value'] = get_secret('sid') or ''
                        case '__stripe_sid':
                            pw_cookie['value'] = get_secret('__stripe_sid') or ''
                        case '__stripe_mid':
                            pw_cookie['value'] = get_secret('__stripe_mid') or ''
                    
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
                    # Update profile from Vue even on session load
                    self._update_profile_from_vue()
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

            # Polling instead of blocking wait to allow cancellation
            start_time = time.time()
            login_success = False
            while self.status.is_running and (time.time() - start_time < 300):
                 if self._browser_closed: 
                      break
                 try:
                      # Use a short timeout suitable for polling loop check
                      # Note: is_visible is better than count for visibility check
                      if self.page.locator(VUE_COMPONENT_SELECTOR).count() > 0:
                           login_success = True
                           break
                 except:
                      pass
                 time.sleep(0.5)
            
            if not login_success:
                 if not self.status.is_running:
                      self.log("Login cancelled.")
                 else:
                      self.log("Login timeout.")
                 return
            
            self.log("Login complete.")

            # Extract authUser and save login session (cookies + profile)
            auth_user = self._extract_auth_user()

            # save login session to account_connections.json
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
                    set_secret(cookie['name'], cookie['value'])
                    cookie['value'] = ''
                elif not any(name in cookie['name'] for name in SUB_COOKIE):
                    continue
                
                cookies.append({k: v for k, v in cookie.items() if k in COOKIE_ESSENTIAL_FIELDS})
            
            # Update arcaea_online section
            ao_payload = {
                'connected': True,
                'connected_at': int(time.time()),
                'name': auth_user.get('name', ''),
                'user_id': auth_user.get('user_id', ''),
                'rating': auth_user.get('rating'),
                'join_date': auth_user.get('join_date'),
                'user_code': auth_user.get('user_code', ''),
                'cookies': cookies
            }
            try:
                set_provider('arcaea_online', ao_payload)
                self.log("Login session saved.")
            except Exception as e:
                self.log(f"Failed to save login session: {e}")
            
            # Notify that login is completed (for updating settings/profile UI)
            if self.login_completed_callback:
                try:
                    self.login_completed_callback()
                except Exception as e:
                    self.log(f"Login completed callback error: {e}")

    def _extract_auth_user(self) -> dict:
        """Vue 컴포넌트에서 authUser 정보를 추출합니다."""
        auth_user = {}
        try:
            vue_element = self.page.locator(VUE_COMPONENT_SELECTOR)
            if vue_element.count() > 0:
                auth_user_data = self.page.evaluate("""(element) => {
                    var vue = element.__vue__;
                    var authUser = vue.authUser;
                    return {
                        name: authUser.name || '',
                        user_id: authUser.user_id || '',
                        rating: authUser.rating || null,
                        join_date: authUser.join_date || null,
                        user_code: authUser.user_code || ''
                    };
                }""", vue_element.nth(0).element_handle())
                auth_user = auth_user_data or {}
        except Exception as e:
            self.log(f'Could not extract authUser: {e}')
        return auth_user

    def _update_profile_from_vue(self):
        """Vue에서 최신 프로필 데이터를 추출하여 account_connections.json의 프로필 필드만 갱신합니다.
        
        cookies 등 기존 세션 데이터는 유지하고, name/user_id/rating/join_date/user_code만 업데이트합니다.
        """
        auth_user = self._extract_auth_user()
        if not auth_user:
            return
        
        try:
            ao_info = get_provider('arcaea_online')
            
            # 프로필 필드만 업데이트 (cookies, connected, connected_at 등은 유지)
            ao_info['name'] = auth_user.get('name', '')
            ao_info['user_id'] = auth_user.get('user_id', '')
            ao_info['rating'] = auth_user.get('rating')
            ao_info['join_date'] = auth_user.get('join_date')
            ao_info['user_code'] = auth_user.get('user_code', '')
            
            set_provider('arcaea_online', ao_info)
            
            self.log("Profile data updated.")
            
            # Notify UI to refresh profile
            if self.login_completed_callback:
                try:
                    self.login_completed_callback()
                except Exception as e:
                    self.log(f"Login completed callback error: {e}")
        except Exception as e:
            self.log(f"Error updating profile: {e}")

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
        
        # Session integrity check (date-sorted, non-search only)
        if not page_data.is_search and page_data.is_date_sorted:
            if self._check_session_integrity(page_data):
                return  # 리로드 발생 → start() 루프가 리로드된 페이지를 다시 처리
        
        difficulty = page_data.difficulty
        self._difficulty_tag = Difficulty(difficulty).name
        
        # 2. 페이지 진행 상태 업데이트 (날짜순 정렬 + 검색 아닐 때만)
        if not page_data.is_search and page_data.is_date_sorted:
            self.checked_page[difficulty].add(page_data.current_page)
            
            pin_id = self.get_pin_id(difficulty)
            if pin_id:
                with sqlite3.connect(self.db_path, timeout=10) as conn:
                    cursor = conn.cursor()
                    self._check_pin_in_page(cursor, pin_id, page_data)
            else:
                self.total_page[difficulty] = page_data.total_page

            # Play Count Analyze Mode: 별도 상태로 진행도 추적
            if self.play_count_mode:
                self.count_mode.checked_pages[difficulty].add(page_data.current_page)
                self.count_mode.total_pages[difficulty] = page_data.total_page
                if self.count_mode.all_pages_checked(difficulty):
                    self.count_mode.completed.add(difficulty)
        
        self.notify_progress_changed()
        
        # 3. DB 저장
        
        mark_write_activity("user_scores_db", "analysis_save")
        with sqlite3.connect(self.db_path, timeout=10) as conn:
            cursor = conn.cursor()
            self._pin_notify_pending = False
            
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
                    
                    # 현재 Pin과 다를 때만 로그 (스팸 방지), 하지만 updated_at은 항상 갱신
                    try:
                        current_pin_id = self._pin_repo.get_pin(cursor, difficulty)
                    except Exception:
                        current_pin_id = None
                    
                    # Always update pin to refresh updated_at timestamp
                    self.save_pin_id(difficulty, recent_id, cursor)
                    
                    if recent_id != current_pin_id:
                        self.log(f'Synchronization status updated')
                    
                    self.rise_all_saved_flag(difficulty)
                
                conn.commit()

                if self._pin_notify_pending:
                    self._pin_notify_pending = False
                    self.notify_pin_changed()

                if len(score_inserts) > 0:
                    self.log(f"Saved {len(score_inserts)} records.")
                    self.notify_data_changed()
                else:
                    if len(count_updates) > 0:
                        self.notify_data_changed()

                    self.log(f"No new records.")
                    
            except Exception as e:
                self._pin_notify_pending = False
                self.log(f"Save failed: {e}")
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
        
        while self.status.is_running:
            try:        
                # HTML 요소의 disabled 클래스를 통해 로딩 상태 확인
                is_loading = self.page.evaluate("""() => {
                    const diffSelect = document.querySelector('.difficulty-select');
                    if (diffSelect && diffSelect.classList.contains('disabled')) return true;
                    
                    const pagination = document.querySelector('.pagination-container');
                    if (pagination) {
                        const items = pagination.querySelectorAll('*');
                        for (let i = 0; i < items.length; i++) {
                            if (items[i].classList.contains('disabled')) return true;
                        }
                    }
                    return false;
                }""")
                
                if not is_loading: # 로딩 중이 아닐 때만 다음 단계로 넘어감
                    break
                time.sleep(0.2)
            except Exception:
                time.sleep(0.2)
                continue
        
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
            self.log('Page is empty.')
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

    def _check_session_integrity(self, page_data: PageScoreData) -> bool:
        """
        세션 무결성 검사: 중복 레코드 또는 페이지 내용 변경 감지 시 세션 리셋.
        
        Returns:
            True if session was reset (caller should abort save_data)
        """
        difficulty = page_data.difficulty
        page = page_data.current_page
        current_times = [s.get('time_played') for s in page_data.scores]

        # 1) 페이지 재방문 → 스냅샷 비교
        if page in self.scanned_pages[difficulty]:
            if self.scanned_pages[difficulty][page] != current_times:
                self.log(f"Session reset: Page {page} content changed on revisit.", with_tag=False)
                reloaded = self._reset_analysis_session(page)
                self.scanned_pages[difficulty][page] = current_times
                return reloaded
            return False  # 동일 내용이면 중복 체크 불필요

        # 2) 순방향 중복 감지 — 다른 페이지에 같은 time_played가 있는지
        all_scanned = set()
        for p, times in self.scanned_pages[difficulty].items():
            all_scanned.update(times)

        for tp in current_times:
            if tp in all_scanned:
                self.log(f"Session reset: Already scanned record detected on page {page}.", with_tag=False)
                reloaded = self._reset_analysis_session(page)
                self.scanned_pages[difficulty][page] = current_times
                return reloaded

        # 정상 — 스냅샷 저장
        self.scanned_pages[difficulty][page] = current_times
        return False

    def _reset_analysis_session(self, current_page: int = None, 
                              msg: str = "New play record detected. Session refreshed") -> bool:
        """세션 무결성 위반 시 세션 리셋. 리로드 발생 시 True 반환."""
        # 스캔 추적 초기화
        self.previous_user_data = None
        for difficulty in Difficulty:
            self.checked_page[difficulty] = set()
            self.total_page[difficulty] = None
            self.scanned_pages[difficulty] = {}

        # Play Count Analyze Mode: 진행도 리셋 (completed는 보존)
        self.count_mode.reset_progress()

        # 1페이지로 이동 (이미 1페이지면 스킵)
        reloaded = False
        if current_page != 1:
            try:
                current_url = self.page.url
                page1_url = re.sub(r'page=\d+', 'page=1', current_url)
                self.page.goto(page1_url)
                reloaded = True
                # has_page_changed()가 이동한 페이지를 새 페이지로 감지하도록 초기화
                self.current_pageno = None
                self.current_difficulty = None
                self.current_sort = None
                self.current_search_text = ''
            except Exception:
                pass

        self.notify_progress_changed()

        if msg:
            self.log(msg, with_tag=False)
            if self.session_reset_callback:
                try:
                    self.session_reset_callback(msg)
                except Exception:
                    pass

        return reloaded

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
            self.log(f"Song data unavailable. Some details may be missing.")
        
        try:
            for item in items:
                diff_val = item.get('difficulty')
                ao_song_id = item.get('song_id')
                time_played = item.get('time_played')
                
                # 타이틀 추출
                title_obj = item.get('title')
                if isinstance(title_obj, dict):
                    title_en = title_obj.get('en', '')
                    title_jp = title_obj.get('ja', '')
                else:
                    title_en = str(title_obj) if title_obj else ''
                    title_jp = ''

                ao_artist = item.get('artist') or ''
                
                # 해당 채보의 곡을 songs.db에서 찾아 ao_song_id 정보 삽입 (실패해도 계속 진행)
                if songs_cursor:
                    try:
                        db_song_id = resolve_song_id_for_ao(songs_cursor, ao_song_id, title_en)
                        update_song_titles_from_ao(
                            songs_cursor,
                            db_song_id,
                            title_en,
                            title_jp,
                            ao_artist,
                        )
                    except Exception:
                        pass
                
                # 중복 체크
                is_existing = self._score_repo.score_exists(cursor, ao_song_id, diff_val, time_played)
                if is_existing:
                    # Play Count Analyze Mode: 기존 기록이어도 play count 최신화
                    if self.play_count_mode:
                        yearly_play_count = item.get('yearly_play_count') or 0
                        if yearly_play_count > 0:
                            count_updates.append((ao_song_id, diff_val, current_year, yearly_play_count, yearly_play_count))
                    continue

                yearly_play_index = 0
                yearly_play_count = item.get('yearly_play_count') or 0
                
                # 현재 연도 플레이 카운트 업데이트 (스코어 연도와 무관)
                if yearly_play_count > 0:
                    count_updates.append((ao_song_id, diff_val, current_year, yearly_play_count, yearly_play_count))
                
                score_year = datetime.fromtimestamp(time_played / 1000, tz=timezone.utc).year

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
                    title_en,
                    title_jp,
                    ao_artist,
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
        
        # 1차 패스: 미저장 썸네일의 인덱스 → filepath 매핑
        missing = {}  # {index: filepath}
        for i, score in enumerate(user_scores_data):
            song_id = score.get('song_id')
            if not song_id:
                continue
            filepath = os.path.join(thumbnails_dir, f"{song_id}_{difficulty_name}.jpg")
            if not os.path.exists(filepath):
                missing[i] = filepath
        
        if not missing:
            return  # 모든 썸네일이 이미 존재
        
        self.log(f"Downloading {len(missing)} thumbnails...")
        # 미저장 썸네일이 있으면 이미지 로드 대기
        try:
            self.page.wait_for_selector(ALBUM_JACKET_SELECTOR, timeout=5000)
            self.page.wait_for_function(
                f"""() => {{
                    const img = document.querySelector('{ALBUM_JACKET_SELECTOR}');
                    return img && img.src && img.src.includes('webassets.lowiro.com');
                }}""",
                timeout=5000
            )
        except Exception as e:
            if self._is_browser_closed_error(e):
                return
            pass  # 타임아웃이어도 캐싱된 데이터로 시도
        
        # 이미지 요소 가져오기
        try:
            img_elements = self.page.locator(ALBUM_JACKET_SELECTOR).all()
        except Exception as e:
            self.log(f"Thumbnail download failed: {e}")
            return
        
        if not img_elements:
            return
            
        # 다운로드할 대상 파일명(캐시 키) 수집
        target_filenames = set()
        for i, img_elem in enumerate(img_elements):
            if i in missing:
                try:
                    img_url = img_elem.get_attribute('src')
                    if img_url and 'webassets.lowiro.com' in img_url:
                        url_filename = img_url.split('/')[-1].split('?')[0]
                        target_filenames.add(url_filename)
                except Exception:
                    continue
                    
        # 캐시 폴링 루프 (최대 10초 대기)
        if target_filenames:
            start_time = time.time()
            while time.time() - start_time < 10.0:
                if all(filename in self.thumbnail_collector.cached_images for filename in target_filenames):
                    break
                time.sleep(0.2)
        
        # 미저장 항목만 처리
        saved_count = 0
        not_found_count = 0
        
        for i, img_elem in enumerate(img_elements):
            if i not in missing:
                continue
            
            filepath = missing[i]
            try:
                img_url = img_elem.get_attribute('src')
                if not img_url:
                    continue
                
                url_filename = img_url.split('/')[-1].split('?')[0]
                img_data = self.thumbnail_collector.get_image(url_filename)
                
                if img_data:
                    with open(filepath, 'wb') as f:
                        f.write(img_data)
                    saved_count += 1
                    self.notify_data_changed()
                else:
                    not_found_count += 1
                    
            except Exception:
                continue
        
        if saved_count > 0:
            self.log(f"Saved {saved_count} thumbnails.")
        if not_found_count > 0:
            self.log(f"{not_found_count} thumbnails not found.")

    def get_pin_id(self, difficulty) -> int | None:
        try:
            with sqlite3.connect(self.db_path, timeout=10) as conn:
                cursor = conn.cursor()
                pin_id = self._pin_repo.get_pin(cursor, difficulty)
                conn.commit()  # get_pin may INSERT if row is None
                return pin_id
        except Exception as e:
            self.log(f"Pin lookup failed: {e}")
            return None

    def save_pin_id(self, difficulty, score_id, cursor):
        try:
            current_time = int(time.time() * 1000)
            self._pin_repo.save_pin(cursor, difficulty, score_id, current_time)

            # Update status object
            self.status.pin_updates[difficulty] = current_time
            self._pin_notify_pending = True

        except Exception as e:
            self.log(f"Pin update failed: {e}")

    def all_pages_checked(self, difficulty):
        if not self.total_page[difficulty]:
            return False
        return set(range(1, self.total_page[difficulty] + 1)) <= self.checked_page[difficulty]

    def rise_all_saved_flag(self, difficulty):
        self.checked_page[difficulty] = set()
        self.total_page[difficulty] = None

    def log(self, message: str, with_tag: bool = True):
        timestamp = time.strftime("[%H:%M:%S]")
        diff_tag = f"[{self._difficulty_tag}]" if getattr(self, '_difficulty_tag', None) and with_tag else ""
        formatted_message = f"{timestamp}{diff_tag} {message}"
        self.status.logs.append(formatted_message)
        print(formatted_message)
        
        if self.log_callback:
            self.log_callback(formatted_message)


if __name__=='__main__':
    analyzer = ArcaeaOnline()
    analyzer.start()
