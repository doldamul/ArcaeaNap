from configuration import config
import time
import locale as sys_locale
from datetime import datetime
from playwright.sync_api import sync_playwright
from playwright_stealth import Stealth
from browser_utils import get_browser
from bs4 import BeautifulSoup
from db_utils import get_connection, init_songs_db

WIKI_URL = 'https://arcaea.fandom.com/wiki/Songs_by_Date'
TABLE_SELECTOR = 'table.wikitable:nth-child(1) > tbody:nth-child(2)'
LOAD_DETECT_SELECTOR = 'div:nth-child(1) > div > div > table th:nth-child(4)'

# TODO: compare arcaea version with db and call open_wiki if needed
def open_wiki():
    playwright = None
    browser = None
    try:
        playwright = sync_playwright().start()
        # Firefox 사용 (Chromium보다 봇 탐지 회피에 유리)
        browser = playwright.firefox.launch(headless=False)
        
        # 시스템 로케일 및 타임존 가져오기
        system_locale = sys_locale.getdefaultlocale()[0] or 'en-US'
        system_locale = system_locale.replace('_', '-')  # ko_KR -> ko-KR
        system_timezone = datetime.now().astimezone().tzinfo.key if hasattr(datetime.now().astimezone().tzinfo, 'key') else 'UTC'
        
        # 현실적인 브라우저 설정으로 컨텍스트 생성
        context = browser.new_context(
            viewport={'width': 1920, 'height': 1080},
            locale=system_locale,
            timezone_id=system_timezone,
            user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:124.0) Gecko/20100101 Firefox/124.0',
        )
        page = context.new_page()
        
        # Stealth 모드 적용 (봇 감지 회피)
        Stealth().apply_stealth_sync(context)
        
        page.goto(WIKI_URL, timeout=60000)  # 타임아웃 증가
        
        # Wait for table to load
        page.wait_for_selector(LOAD_DETECT_SELECTOR, timeout=30000)
        page.wait_for_function(
            f"document.querySelector('{LOAD_DETECT_SELECTOR}')?.textContent?.includes('PST')",
            timeout=30000
        )
        
        table_body = page.wait_for_selector(TABLE_SELECTOR, timeout=30000)
        
        print("테이블 HTML 가져오는 중...")
        table_html = table_body.inner_html()
        
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
        if browser:
            time.sleep(10)
            browser.close()
        if playwright:
            playwright.stop()

def save_data(data):
    init_songs_db()
    
    print(f"DB 저장 시작: songs.db")
    
    conn = get_connection()
    cursor = conn.cursor()
    
    try:
        updated_count = 0
        from db_utils import resolve_song_id_with_artist, update_song_metadata, fill_missing_arcaea_ids_from_scores
        
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
        
        # Try to fill arcaea_id from user_scores.db
        fill_missing_arcaea_ids_from_scores()
        
    except Exception as e:
        print(f"DB 저장 중 오류 발생: {e}")
    finally:
        conn.close()

if __name__ == '__main__':
    open_wiki()