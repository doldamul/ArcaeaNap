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

VUE_COMPONENT_SELECTOR = "#app > section > div:nth-child(3)"

class Difficulty(IntEnum):
    PST = 0
    PRS = 1
    FTR = 2
    ETR = 4
    BYD = 3

def open_arcaea_online():
    lang = 'ko'
    url = f'https://arcaea.lowiro.com/{lang}/profile/scores?page=1'
    try:
        driver = get_driver()
        assert driver is not None, "unsupported browser"

        driver.set_window_size(600, 1000)

        login(driver, url)
        
        save_data.previous_user_data = None
        save_data.checked_page = {}
        save_data.total_page = {}

        for difficulty in Difficulty:
            save_data.checked_page[difficulty] = set()
            save_data.total_page[difficulty] = None

        open_arcaea_online.difficulty = None
        open_arcaea_online.pageno = None
        open_arcaea_online.sort = None
        open_arcaea_online.search_text = ''

        while True:
            WebDriverWait(driver, 300).until(has_page_changed)
            try:
                block_pointer_events(driver)
                save_data(driver)
            finally:
                restore_pointer_events(driver)
        
    except Exception as e:
        print(f'브라우저 종료됨: {e}')

    finally:
        # TODO: 종료 전 변경된 쿠키 확인 후 업데이트?
        try: driver.quit()
        except: pass
        
        try: del driver
        except: pass

def login(driver, url):
    # check login session
    login_filename = 'login.dat'
    login_filepath = os.path.join(config['general']['cache_path'], login_filename)
    
    login = os.path.exists(login_filepath) and os.path.isfile(login_filepath) and config['general']['auto_login']
    if login: # session load
        with open(login_filepath, 'r', encoding='utf-8') as f:
            login_cookies = json.load(f)
        
        driver.execute_cdp_cmd('Network.enable', {})
        
        for cookie in login_cookies:
            try:
                match cookie['name']:
                    case 'sid':
                        cookie['value'] = keyring.get_password('ArcaeaNap', 'sid')
                    case '__stripe_sid':
                        cookie['value'] = keyring.get_password('ArcaeaNap', '__stripe_sid')
                    case '__stripe_mid':
                        cookie['value'] = keyring.get_password('ArcaeaNap', '__stripe_mid')
                    case _:
                        pass
                
                driver.execute_cdp_cmd('Network.setCookie', cookie)
            except Exception as e:
                print(f'쿠키 주입 도중 문제 발생: {e}')
        
        driver.execute_cdp_cmd('Network.disable', {})
        
        driver.get(url)
    else: # manual login and saves session
        new_sid = None
        driver.get(url)
        
        WebDriverWait(driver, 30).until(
            lambda driver: driver.get_cookie('sid') is not None
        )
        
        try:
            cookie = driver.get_cookie('sid')
            old_sid = cookie['value']
        except Exception as e:
            print(f'old_sid 쿠키 읽기 오류: {e}')
            raise
            
        print('wait for login...')
        
        def has_sid_changed(driver):
            try:
                cookie = driver.get_cookie('sid')
                new_sid = cookie['value']
            except Exception as e:
                print(f'new_sid 쿠키 읽기 오류: {e}')
                raise
            
            return new_sid != old_sid
        
        WebDriverWait(driver, 300).until(has_sid_changed) # wait for manual login, timeout: 5min
        WebDriverWait(driver, 30).until(
            EC.presence_of_element_located((By.CSS_SELECTOR, VUE_COMPONENT_SELECTOR))
        )
        
        print('login success.')
        
        # save login session
        LOGIN_COOKIE = {'sid', '__stripe_sid', '__stripe_mid'}
        SUB_COOKIE = {'_ga', 'ctrcode', 'lang'}
        COOKIE_ESSENTIAL_FIELDS = {'name', 'value', 'domain', 'path', 'expires', 'expiry', 'httpOnly', 'secure', 'sameSite'}
        
        data = get_all_cookies_chromium(driver)
        cookies = []
        
        for cookie in data:
            if cookie['name'] in LOGIN_COOKIE:
                keyring.set_password('ArcaeaNap', cookie['name'], cookie['value'])
                cookie['value'] = ''
            elif not any(name in cookie['name'] for name in SUB_COOKIE):
                continue
            
            cookies.append({k: v for k, v in cookie.items() if k in COOKIE_ESSENTIAL_FIELDS})
        
        if __name__=='__main__':
            print(cookies)
        
        with open(login_filepath, 'w', encoding='utf-8') as f:
            json.dump(cookies, f, ensure_ascii=False)

def has_page_changed(driver):
    new_difficulty = driver.find_element(By.CSS_SELECTOR, ".difficulty-selector.active .label").text
    new_pageno = driver.find_element(By.CSS_SELECTOR, '.selected.no-select').text
    new_sort = driver.find_element(By.CSS_SELECTOR, 'div.dropdown > div > span:nth-child(1)').text

    if new_difficulty != open_arcaea_online.difficulty or new_pageno != open_arcaea_online.pageno or new_sort != open_arcaea_online.sort:
        open_arcaea_online.difficulty = new_difficulty
        open_arcaea_online.pageno = new_pageno
        open_arcaea_online.sort = new_sort
        return True

    new_search_text = driver.find_element(By.CSS_SELECTOR, 'div.search-box > input[type=text]').get_attribute('value')

    if new_search_text != open_arcaea_online.search_text:
        time.sleep(0.4)
        waited_new_search_text = driver.find_element(By.CSS_SELECTOR, 'div.search-box > input[type=text]').get_attribute('value')
        if new_search_text != waited_new_search_text:
            return False

        time.sleep(0.4)
        waited_new_search_text = driver.find_element(By.CSS_SELECTOR, 'div.search-box > input[type=text]').get_attribute('value')
        if new_search_text == waited_new_search_text:
            open_arcaea_online.search_text = new_search_text
            return True
    
    return False

def save_data(driver):
    wait = WebDriverWait(driver, 30)
            
    target_element = wait.until(
        EC.presence_of_element_located((By.CSS_SELECTOR, VUE_COMPONENT_SELECTOR))
    )
    
    user_data = None
    while(True):
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

        if user_data == save_data.previous_user_data:
            time.sleep(0.5)
            continue

        save_data.previous_user_data = user_data
        break

    user_scores_data = user_data['userScores']

    if not user_scores_data or len(user_scores_data) == 0:
        print('current page is empty')
        return
    
    is_datesort = user_data['dropDownSelectedValue']['value'] == 'date'
    is_search = user_data['searchTerm'] != ''

    difficulty = int(user_data['selectedDifficulty'])
    pin_id = get_pin_id(difficulty)

    if not is_search and is_datesort:
        save_data.checked_page[difficulty].add(user_data['currentPage'])
        
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
                        print('newest item is older than pinned')
                        return

                    # iterate user_scores_data and compare name_id with pin data
                    for item in user_scores_data:
                        if item.get('song_id') != pinned_song_id:
                            continue
                        
                        # if name_id is same, compare the date
                        item_date = item.get('time_played')
                        if item_date == pinned_song_date:
                            if not is_search and is_datesort:
                                save_data.total_page[difficulty] = user_data['totalPage']
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
                                    save_pin_id(difficulty, None, cursor)
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
                                save_pin_id(difficulty, c_id, cursor)
                                found_new_pin = True
                                break
                            
                            if found_new_pin:
                                break
                        break
        else:
            save_data.total_page[difficulty] = user_data['totalPage']

    record_count = user_data['count']

    # save data
    score_filename = 'user_scores.db'
    score_filepath = os.path.join(config['general']['cache_path'], score_filename)

    if not user_scores_data:
        print("데이터 비어있음")
        return

    print(f"{len(user_scores_data)}개의 플레이 기록 발견")
        
    if __name__=='__main__':
        print("\n데이터 샘플:")
        print(json.dumps(user_scores_data[0], indent=2, ensure_ascii=False))
    
    # Ensure songs.db exists
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
                print("Adding 'db_song_id' column to scores table...")
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
            
            songs_conn.commit() # Commit any new song creations in songs.db

            cursor.executemany('''
                INSERT OR IGNORE INTO scores 
                (song_id, difficulty, score, shiny_perfect_count, perfect_count, near_count, 
                    miss_count, health, modifier, time_played, clear_type, best_clear_type, 
                    title, artist, user_id, yearly_play_count, score_below_max, db_song_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', data_to_insert)
            
            # check all_pages_checked, if yes, call rise_all_saved_flag, find newest saved data's id in db and save to pin_id
                print(f'{difficulty} 난이도의 최신화 완료')
                
            if all_pages_checked(difficulty):
                # find most recent data in current difficulty from db
                cursor.execute('SELECT id FROM scores WHERE difficulty = ? ORDER BY time_played DESC LIMIT 1', (difficulty,))
                
                row = cursor.fetchone()
                id = row[0]

                # save the id to db's pin_id
                save_pin_id(difficulty, id, cursor)
                rise_all_saved_flag(difficulty)

            conn.commit()
            print(f"\n'{score_filepath}' DB 파일에 {cursor.rowcount}건 저장/업데이트 완료")
            
        except Exception as e:
            print(f"DB 저장 중 오류 발생: {e}")
            import traceback
            traceback.print_exc()
        finally:
            songs_conn.close()

def get_all_cookies_chromium(driver):
    try:
        driver.execute_cdp_cmd('Network.enable', {})
        result = driver.execute_cdp_cmd('Network.getAllCookies', {})
        cookies = result['cookies']
    except Exception as e:
        print(f'cdp로부터 쿠키 가져오는 중 오류 발생: {e}')
        raise
    finally:
        try: driver.execute_cdp_cmd('Network.disable', {})
        except: pass
    
    target_cookies = []
    for cookie in cookies:
        if 'lowiro.com' in cookie['domain']:
            target_cookies.append(cookie)
            
    return target_cookies

# get pinned last saved data's id from db
def get_pin_id(difficulty) -> int | None:
    score_filepath = os.path.join(config['general']['cache_path'], 'user_scores.db')
    try:
        with sqlite3.connect(score_filepath) as conn:
            cursor = conn.cursor()
            # Note: Changed to use score_id as INTEGER based on user correction.
            # Handle potential schema mismatch from previous runs gracefully
            try:
                cursor.execute('SELECT score_id FROM pin WHERE difficulty = ?', (difficulty,))
            except sqlite3.OperationalError:
                # If table exists with old schema (song_id column), drop and recreate
                cursor.execute('DROP TABLE IF EXISTS pin')
                cursor.execute('CREATE TABLE pin (difficulty INTEGER PRIMARY KEY, score_id INTEGER)')
                cursor.execute('SELECT score_id FROM pin WHERE difficulty = ?', (difficulty,))
            
            row = cursor.fetchone()
            
            if row is None:
                # Table might be empty or this difficulty not present
                # Ensure table exists if we dropped it or it's new
                cursor.execute('CREATE TABLE IF NOT EXISTS pin (difficulty INTEGER PRIMARY KEY, score_id INTEGER)')
                cursor.execute('INSERT OR IGNORE INTO pin (difficulty, score_id) VALUES (?, NULL)', (difficulty,))
                conn.commit()
                return None
            return row[0]
            
    except Exception as e:
        print(f"get_pin_id 오류: {e}")
        return None

def save_pin_id(difficulty, score_id, cursor):
    try:
        cursor.execute('CREATE TABLE IF NOT EXISTS pin (difficulty INTEGER PRIMARY KEY, score_id INTEGER)')
        cursor.execute('INSERT OR REPLACE INTO pin (difficulty, score_id) VALUES (?, ?)', (difficulty, score_id))
    except Exception as e:
        print(f"save_pin_id 오류: {e}")

def all_pages_checked(difficulty):
    if not save_data.total_page[difficulty]:
        return False
    return set(range(1, save_data.total_page[difficulty] + 1)) <= save_data.checked_page[difficulty]

def rise_all_saved_flag(difficulty):
    # reset static variables
    save_data.checked_page[difficulty] = set()
    save_data.total_page[difficulty] = None

def check_db_data():
    DB_FILENAME = 'user_scores.db'
    DB_FILEPATH = os.path.join(config['general']['cache_path'], DB_FILENAME)
    # DB 파일 존재 여부 확인
    if not os.path.exists(DB_FILEPATH):
        print(f"오류: '{DB_FILEPATH}' 파일을 찾을 수 없습니다.")
        return

    try:
        conn = sqlite3.connect(DB_FILEPATH)

        # 모든 데이터
        query = "SELECT * FROM scores"
        df = pd.read_sql(query, conn)
        conn.close()

        if df.empty:
            print("DB에 저장된 데이터가 없습니다.")
            return

        # --- [가독성 향상] ---
        # time_played가 타임스탬프(ms)라면 날짜 형식으로 변환해서 보여줌
        if 'time_played' in df.columns:
            df['play_date'] = pd.to_datetime(df['time_played'], unit='ms')
            # 보기 좋게 컬럼 순서 조정 (play_date를 앞으로)
            cols = ['play_date', 'title', 'difficulty', 'score'] + [c for c in df.columns if c not in ['play_date', 'title', 'difficulty', 'score']]
            df = df[cols]

        # --- [출력] ---
        print(f"=== 총 데이터 개수: {len(df)}개 ===")
        
        print("\n1. 상위 5개 데이터 미리보기:")
        print(df.head())

        print("\n2. 데이터 정보 (컬럼 타입 및 결측치 확인):")
        print(df.info())

        print("\n3. 주요 수치 통계 (점수 등):")
        # float 포맷을 소수점 2자리까지만 나오게 설정
        pd.set_option('display.float_format', lambda x: '%.2f' % x)
        print(df[['score', 'shiny_perfect_count', 'miss_count']].describe())
        
        # (옵션) 특정 곡의 히스토리 확인해보기
        # 예: 데이터에 있는 첫 번째 곡의 ID로 필터링
        sample_song_id = df['song_id'].iloc[0]
        print(f"\n4. 특정 곡({sample_song_id})의 기록 내역:")
        print(df[df['song_id'] == sample_song_id][['play_date', 'title', 'score', 'perfect_count']])

    except Exception as e:
        print(f"데이터 로드 중 오류 발생: {e}")

if __name__=='__main__':
    open_arcaea_online()
    # check_db_data()