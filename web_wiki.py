from configuration import config
import time
from browserdriver import get_driver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from bs4 import BeautifulSoup
from db_utils import get_connection, init_songs_db

WIKI_URL = 'https://arcaea.fandom.com/wiki/Songs_by_Date'
TABLE_SELECTOR = 'table.wikitable:nth-child(1) > tbody:nth-child(2)'
LOAD_DETECT_SELECTOR = 'div:nth-child(1) > div > div > table th:nth-child(4)'

# TODO: compare arcaea version with db and call open_wiki if needed
def open_wiki():
    driver = None
    try:
        driver = get_driver(headless=True)
        assert driver is not None, "unsupported browser"
        
        driver.get(WIKI_URL)
        
        wait = WebDriverWait(driver, 30)
        wait.until(EC.presence_of_element_located((By.CSS_SELECTOR, LOAD_DETECT_SELECTOR)))
        wait.until(EC.text_to_be_present_in_element((By.CSS_SELECTOR, LOAD_DETECT_SELECTOR), 'PST'))

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

                titles = [a.get_text(strip=True) for a in cells[1].find_all('a')]
                artist = row_texts[2].strip()
                length = row_texts[8].strip()
                bpm = row_texts[9].strip()

                # in wiki, title:artist:length:bpm
                # always 1:1:1:1 or 2:1:1:1 or 3:1:1:1 or 2:1:2:1 or 2:1:2:2
                if ' ' in length:  # ex) '2:00 2:38'
                    lengths = length.split()
                    
                    if ' ' in bpm:
                        bpms = bpm.split()

                        for i in range(len(lengths)):
                            songs_data.append((titles[i], artist, lengths[i], bpms[i]))
                    else:
                        for i in range(len(lengths)):
                            songs_data.append((titles[i], artist, lengths[i], bpm))
                else:
                    for title in titles:
                        songs_data.append((title, artist, length, bpm))

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
    init_songs_db()
    
    print(f"DB 저장 시작: songs.db")
    
    conn = get_connection()
    cursor = conn.cursor()
    
    try:
        updated_count = 0
        from db_utils import resolve_song_id_with_artist, update_song_metadata
        
        for title, artist, length_str, bpm in data:
            # Convert length "m:ss" to seconds (int)
            length_seconds = None
            if length_str:
                parts = length_str.split(':')
                if len(parts) == 2:
                    try:
                        length_seconds = int(parts[0]) * 60 + int(parts[1])
                    except:
                        pass # keep None
            
            # Resolve ID (handles case-insensitivity and Wiki Exceptions)
            song_id = resolve_song_id_with_artist(cursor, title, artist)
            
            # Update Metadata
            update_song_metadata(cursor, song_id, artist, length_seconds, bpm)
            updated_count += 1
            
        conn.commit()
        print(f"DB 저장 완료: {updated_count}건 처리됨")
        
    except Exception as e:
        print(f"DB 저장 중 오류 발생: {e}")
    finally:
        conn.close()

if __name__ == '__main__':
    open_wiki()