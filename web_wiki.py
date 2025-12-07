from configuration import config
import sqlite3
import os
import time
from browserdriver import get_driver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from bs4 import BeautifulSoup  # HTML 파싱을 위해 추가

WIKI_URL = 'https://arcaea.fandom.com/wiki/Songs_by_Date'
TABLE_SELECTOR = 'table.wikitable:nth-child(1) > tbody:nth-child(2)'
LOAD_DETECT_SELECTOR = 'a > div > img'

# TODO: compare arcaea version with db and call open_wiki if needed
def open_wiki():
    driver = None
    try:
        driver = get_driver()
        assert driver is not None, "unsupported browser"
        
        driver.get(WIKI_URL)
        
        wait = WebDriverWait(driver, 30)
        wait.until(EC.presence_of_element_located((By.CSS_SELECTOR, LOAD_DETECT_SELECTOR)))
        time.sleep(0.5)
        
        table_body = wait.until(EC.presence_of_element_located((By.CSS_SELECTOR, TABLE_SELECTOR)))
        
        print("테이블 HTML 가져오는 중...")
        table_html = table_body.get_attribute("innerHTML")
        
        soup = BeautifulSoup(table_html, 'html.parser')
        rows = soup.find_all('tr')
        
        songs_data = []
        
        print(f"총 {len(rows)}개의 행 발견...")
        
        for row in rows:
            cells = row.find_all('td')
            if not cells:
                continue
                
            try:
                row_texts = [cell.get_text(' ') for cell in cells]

                artist = row_texts[2]
                titles = [a.get_text(strip=True) for a in cells[1].find_all('a')]
                
                length = row_texts[8]
                if ' ' in length:  # ex) '2:00 2:38'
                    lengths = length.split(' ')   
                    
                    for i in range(len(lengths)):
                        songs_data.append((titles[i], artist, lengths[i]))
                else:
                    for title in titles:
                        songs_data.append((title, artist, length))

            except Exception as e:
                print(f"행 파싱 중 오류 발생 (무시함): {e}")
                continue

        print(f"완료: {len(songs_data)}곡")
        
        save_data(songs_data)
        
    except Exception as e:
        print(f"위키 크롤링 중 오류 발생: {e}")
    finally:
        if driver:
            time.sleep(10)
            driver.quit()

def save_data(data):
    db_filename = 'wiki_songs.db'
    db_filepath = os.path.join(config['general']['cache_path'], db_filename)
    
    print(f"DB 저장 시작: {db_filepath}")
    
    with sqlite3.connect(db_filepath) as conn:
        cursor = conn.cursor()
        
        try:
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS wiki_songs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    title TEXT,
                    artist TEXT,
                    length TEXT
                )
            ''')
            
            cursor.executemany('''
                INSERT OR IGNORE INTO wiki_songs (title, artist, length)
                VALUES (?, ?, ?)
            ''', data)
            
            conn.commit()
            print(f"DB 저장 완료: {cursor.rowcount}건 업데이트 됨")
            
        except Exception as e:
            print(f"DB 저장 중 오류 발생: {e}")

if __name__ == '__main__':
    open_wiki()