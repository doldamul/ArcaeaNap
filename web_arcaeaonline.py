from configuration import config
from disrupt import block_pointer_events, restore_pointer_events
from db_utils import get_connection, resolve_song_id_for_ao, init_songs_db
import sqlite3
import pandas as pd
import keyring
import json
import time
import os
from browserdriver import get_driver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from enum import IntEnum
from dataclasses import dataclass, field
from collections import deque
from typing import Dict, Optional, Set

VUE_COMPONENT_SELECTOR = "#app > section > div:nth-child(3)"

class Difficulty(IntEnum):
    PST = 0
    PRS = 1
    FTR = 2
    ETR = 4
    BYD = 3

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

    def start(self):
        self.status.is_running = True
        lang = 'ko'
        url = f'https://arcaea.lowiro.com/{lang}/profile/scores?page=1'
        
        try:
            self.log("Initializing headless browser...")
            self.driver = get_driver()
            assert self.driver is not None, "unsupported browser"

            self.driver.set_window_size(600, 1000)

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
                except Exception:
                    continue
                
                if not self.status.is_running:
                    break

                self.log('New page detected.')

                try:
                    block_pointer_events(self.driver)
                    self.save_data()
                finally:
                    restore_pointer_events(self.driver)
                
                # Check directly if driver is alive
                self.driver.title
        except Exception as e:
            self.log(f'Browser terminated: {e}')
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
            self.log("Loading saved session...")
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
            
            self.driver.execute_cdp_cmd('Network.disable', {})
            self.driver.get(url)
            
        else: # manual login
            self.log("Waiting for manual login...")
            new_sid = None
            self.driver.get(url)
            
            try:
                WebDriverWait(self.driver, 30).until(
                    lambda d: d.get_cookie('sid') is not None
                )
                cookie = self.driver.get_cookie('sid')
                old_sid = cookie['value']
            except Exception as e:
                self.log(f'Error reading old_sid: {e}')
                raise
                
            def has_sid_changed(driver):
                try:
                    cookie = driver.get_cookie('sid')
                    new_sid = cookie['value']
                except Exception:
                    return False
                return new_sid != old_sid
            
            WebDriverWait(self.driver, 300).until(has_sid_changed)
            WebDriverWait(self.driver, 30).until(
                EC.presence_of_element_located((By.CSS_SELECTOR, VUE_COMPONENT_SELECTOR))
            )
            
            self.log("Login successful.")

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
            
                json.dump(cookies, f, ensure_ascii=False)

            self.log("Login session saved.")

    def has_page_changed(self, driver):
        if not self.status.is_running:
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

    def save_data(self):
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
            
            self.log('Saving data...')

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
                        cursor.execute('SELECT song_id, time_played FROM scores WHERE id = ?', (pin_id,))
                        row = cursor.fetchone()
                        if row:
                            pinned_song_id, pinned_song_date = row
                    
                            # if newest item is older, skip(return)
                            newest_item = user_scores_data[0]
                            if newest_item.get('time_played', 0) < pinned_song_date:
                                self.log('Data save canceled: Newest item is older than pinned.')
                                self.status.status = 'ready'
                                return

                            # iterate user_scores_data and compare name_id with pin data
                            for item in user_scores_data:
                                if item.get('song_id') != pinned_song_id:
                                    continue
                                
                                # if name_id is same, compare the date
                                item_date = item.get('time_played')
                                if item_date == pinned_song_date:
                                    # found pin, pin page is the last page of new data
                                    self.total_page[difficulty] = user_data['currentPage']
                                    self.log('Last page of new data is found.')
                                    break

                                else:
                                    # iterate db data - find previous last saved data's id in db, which is not overlaped with newer one, save to pin_id and break
                                    current_search_date = pinned_song_date
                                    found_new_pin = False

                                    while True:
                                        # Find candidate: newest record in DB older than current_search_date
                                        cursor.execute('SELECT id, song_id, time_played FROM scores WHERE difficulty = ? AND time_played < ? ORDER BY time_played DESC LIMIT 1', (difficulty, current_search_date))
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
                                        cursor.execute('SELECT 1 FROM scores WHERE song_id = ? AND difficulty = ? AND time_played > ? LIMIT 1', (c_song_id, difficulty, c_time))
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
            
            init_songs_db()
            songs_conn = get_connection()
            songs_cursor = songs_conn.cursor()

            with sqlite3.connect(score_filepath) as conn:
                cursor = conn.cursor()
                
                try:
                    # Create table with new schema
                    cursor.execute('''
                        CREATE TABLE IF NOT EXISTS scores (
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            song_id TEXT,
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
                            yearly_play_count INTEGER,
                            score_below_max INTEGER,
                            db_song_id INTEGER,
                            UNIQUE(song_id, difficulty, time_played)
                        )
                    ''')
                    
                    # Check if db_song_id exists (migration)
                    cursor.execute("PRAGMA table_info(scores)")
                    columns = [info[1] for info in cursor.fetchall()]
                    if 'db_song_id' not in columns:
                        self.log("Adding 'db_song_id' column to scores table...")
                        cursor.execute("ALTER TABLE scores ADD COLUMN db_song_id INTEGER")

                    data_to_insert = []
                    for item in user_scores_data:
                        title_obj = item.get('title')
                        if isinstance(title_obj, dict):
                            title_str = title_obj.get('en', '')
                        else:
                            title_str = str(title_obj) if title_obj else ''
                        
                        # Resolve db_song_id from songs.db
                        ao_song_id = item.get('song_id')
                        db_song_id = resolve_song_id_for_ao(songs_cursor, ao_song_id, title_str)

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
                            item.get('time_played'),
                            item.get('clear_type'),
                            item.get('best_clear_type'),
                            title_str,
                            item.get('artist'),
                            item.get('user_id'),
                            item.get('yearly_play_count'),
                            item.get('score_below_max'),
                            db_song_id
                        )
                        data_to_insert.append(row)
                    
                    songs_conn.commit()

                    cursor.executemany('''
                        INSERT OR IGNORE INTO scores 
                        (song_id, difficulty, score, shiny_perfect_count, perfect_count, near_count, 
                            miss_count, health, modifier, time_played, clear_type, best_clear_type, 
                            title, artist, user_id, yearly_play_count, score_below_max, db_song_id)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ''', data_to_insert)
                    
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
                            self.log(f'Updated pin for difficulty {difficulty}')
                        
                        self.rise_all_saved_flag(difficulty)

                    conn.commit()
                    self.log(f"Saved/Updated {cursor.rowcount} records in '{score_filepath}'")
                    
                except Exception as e:
                    self.log(f"Error saving to DB: {e}")
                    import traceback
                    traceback.print_exc()
                finally:
                    songs_conn.close()
        
        finally:
            if self.status.status == 'analyzing':
                self.status.status = 'ready'

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
            try:
                cursor.execute('SELECT updated_at FROM pin LIMIT 1')
            except sqlite3.OperationalError:
                try:
                    cursor.execute('ALTER TABLE pin ADD COLUMN updated_at INTEGER')
                except sqlite3.OperationalError:
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
        
        sample_song_id = df['song_id'].iloc[0]
        print(f"\n4. History for song ({sample_song_id}):")
        print(df[df['song_id'] == sample_song_id][['play_date', 'title', 'score', 'perfect_count']])

    except Exception as e:
        print(f"Error checking DB: {e}")

if __name__=='__main__':
    analyzer = ArcaeaOnline()
    analyzer.start()
    # check_db_data()