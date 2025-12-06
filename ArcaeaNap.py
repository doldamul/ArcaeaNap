from configuration import config
from disrupt import block_pointer_events, restore_pointer_events
import sqlite3
import pandas as pd
import keyring
import json
import os
from browserdriver import get_driver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

VUE_COMPONENT_SELECTOR = "#app > section > div:nth-child(3)"

def open_arcaea_online():
    lang = 'ko'
    url = f'https://arcaea.lowiro.com/{lang}/profile/scores?page=1'
    try:
        driver = get_driver()
        assert driver is not None, "unsupported browser"

        login(driver, url)
        
        while True:
            try:
                block_pointer_events(driver)
                save_data(driver)
                
                difficulty = driver.find_element(By.CSS_SELECTOR, ".difficulty-selector.active .label").text
                pageno = driver.find_element(By.CSS_SELECTOR, '.selected.no-select').text
            finally:
                restore_pointer_events(driver)
            
            def has_page_changed(driver):
                new_difficulty = driver.find_element(By.CSS_SELECTOR, ".difficulty-selector.active .label").text
                new_pageno = driver.find_element(By.CSS_SELECTOR, '.selected.no-select').text
                return new_difficulty != difficulty or new_pageno != pageno
            
            WebDriverWait(driver, 300).until(has_page_changed)    
        
    except Exception as e:
        print(f'브라우저 종료됨: {e}')

    finally:
        # TODO: 종료 전 변경된 쿠키 확인 후 업데이트?
        try: driver.quit()
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

def save_data(driver):
    wait = WebDriverWait(driver, 30)
            
    target_element = wait.until(
        EC.presence_of_element_located((By.CSS_SELECTOR, VUE_COMPONENT_SELECTOR))
    )
    
    time.sleep(0.5) # TODO: compare with previous object(global variable). if same, wait again(after source code file splitting)
    user_scores_data = wait.until(
        lambda d: d.execute_script("return arguments[0].__vue__.userScores;", 
            target_element
        )
    )

    score_filename = 'user_scores.db'
    score_filepath = os.path.join(config['general']['cache_path'], score_filename)
    
    assert user_scores_data, '데이터 가져오는 중 오류 발생'

    print(f"{len(user_scores_data)}개의 플레이 기록 발견")
        
    if __name__=='__main__':
        print("\n데이터 샘플:")
        print(json.dumps(user_scores_data[0], indent=2, ensure_ascii=False))

    with sqlite3.connect(score_filepath) as conn:
        cursor = conn.cursor()
        
        try:
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
                    UNIQUE(song_id, difficulty, time_played)
                )
            ''')

            data_to_insert = []
            for item in user_scores_data:
                title_obj = item.get('title')
                if isinstance(title_obj, dict):
                    title_str = title_obj.get('en', '')
                else:
                    title_str = str(title_obj) if title_obj else ''

                row = (
                    item.get('song_id'),
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
                    item.get('score_below_max')
                )
                data_to_insert.append(row)

            cursor.executemany('''
                INSERT OR IGNORE INTO scores 
                (song_id, difficulty, score, shiny_perfect_count, perfect_count, near_count, 
                    miss_count, health, modifier, time_played, clear_type, best_clear_type, 
                    title, artist, user_id, yearly_play_count, score_below_max)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', data_to_insert)
            
            conn.commit()
            
            print(f"\n'{score_filepath}' DB 파일에 {cursor.rowcount}건 저장/업데이트 완료")
            
        except Exception as e:
            print(f"DB 저장 중 오류 발생: {e}")

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
    # open_arcaea_online()
    check_db_data()