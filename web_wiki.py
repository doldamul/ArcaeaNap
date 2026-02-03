from configuration import config
import requests
from bs4 import BeautifulSoup
from db_utils import get_connection, init_songs_db

WIKI_API_URL = 'https://arcaea.fandom.com/api.php'
WIKI_PAGE = 'Songs_by_Date'

def open_wiki():
    try:
        print("request data to MediaWiki API...")
        
        params = {
            'action': 'parse',
            'page': WIKI_PAGE,
            'format': 'json',
            'prop': 'text'
        }
        
        response = requests.get(WIKI_API_URL, params=params, timeout=30)
        response.raise_for_status()
        
        data = response.json()
        
        if 'error' in data:
            print(f"API Error: {data['error']['info']}")
            return
        
        html = data['parse']['text']['*']
        
        soup = BeautifulSoup(html, 'html.parser')
        
        # 첫 번째 wikitable 찾기
        table = soup.find('table', class_='wikitable')
        if not table:
            print("table not found")
            return
        
        tbody = table.find('tbody')
        rows = tbody.find_all('tr') if tbody else table.find_all('tr')
        
        songs_data = []
        
        print(f"found {len(rows)} rows")
        
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
                print(f"row parsing error: {e}")
                continue

        print(f"complete: {len(songs_data)} songs")
        
        save_data(songs_data)
        
    except requests.RequestException as e:
        print(f"HTTP request error: {e}")
    except Exception as e:
        print(f"Wiki crawling error: {e}")

def save_data(data):
    init_songs_db()
    
    print(f"save data to songs.db...")
    
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
        print(f"save data to songs.db complete: {updated_count} songs")
        
        # Try to fill arcaea_id from user_scores.db
        fill_missing_arcaea_ids_from_scores()
        
    except Exception as e:
        print(f"save data to songs.db error: {e}")
    finally:
        conn.close()

if __name__ == '__main__':
    open_wiki()