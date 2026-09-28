import requests
from bs4 import BeautifulSoup
from repositories.song_repository import get_connection, init_songs_db

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
        songs_data, ins_titles = parse_wiki_html(html)
        print(f"complete: {len(songs_data)} songs, {len(ins_titles)} inscribed")
        
        save_data(songs_data, ins_titles)
        
    except requests.RequestException as e:
        print(f"HTTP request error: {e}")
    except Exception as e:
        print(f"Wiki crawling error: {e}")


def parse_wiki_html(html: str) -> tuple[list, set]:
    """
    Wiki Songs_by_Date HTML을 파싱하여 (songs_data, ins_titles)를 반환한다.

    헤더를 동적으로 분석하여 INS, Len, BPM 위치를 결정한다.
    """
    soup = BeautifulSoup(html, 'html.parser')
    table = soup.find('table', class_='wikitable')
    if not table:
        print("table not found")
        return [], set()

    # 동적 헤더 인덱스 매핑
    headers = []
    header_cells = table.find_all('th')
    if header_cells:
        headers = [th.get_text(strip=True).lower() for th in header_cells]

    col_song = headers.index('song') if 'song' in headers else 1
    col_artist = headers.index('artist') if 'artist' in headers else 2
    col_ins = headers.index('ins') if 'ins' in headers else None
    col_len = headers.index('len') if 'len' in headers else (9 if col_ins is not None else 8)
    col_bpm = headers.index('bpm') if 'bpm' in headers else (10 if col_ins is not None else 9)

    tbody = table.find('tbody')
    rows = tbody.find_all('tr') if tbody else table.find_all('tr')

    songs_data = []
    ins_titles = set()

    for row in rows:
        cells = row.find_all('td')
        if not cells or len(cells) <= max(col_song, col_artist):
            continue

        try:
            titles = [a.get_text(strip=True) for a in cells[col_song].find_all('a')]
            if not titles:
                # <a> 태그가 없는 경우 텍스트 직접 추출
                direct_title = cells[col_song].get_text(strip=True)
                if direct_title:
                    titles = [direct_title]
                else:
                    continue

            artist = cells[col_artist].get_text(strip=True)
            length = cells[col_len].get_text(strip=True) if len(cells) > col_len else ""
            bpm = cells[col_bpm].get_text(strip=True) if len(cells) > col_bpm else ""

            # Inscribed 난이도 확인: INS 열에 내용이 있는지 여부
            is_ins = bool(col_ins is not None and len(cells) > col_ins and cells[col_ins].get_text(strip=True))
            if is_ins:
                for t in titles:
                    ins_titles.add(t)

            if ' ' in length:
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

    return songs_data, ins_titles


def save_data(data, ins_titles=None):
    init_songs_db()
    
    print(f"save data to songs.db...")
    
    conn = get_connection()
    cursor = conn.cursor()
    
    try:
        updated_count = 0
        from repositories.song_repository import (
            resolve_song_id_with_artist,
            update_song_metadata,
            update_chart_inscribed_flag,
            fill_missing_arcaea_ids_from_scores,
            fill_song_titles_from_scores,
        )
        
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

        # Inscribed 채보 플래그 반영 (difficulty 3)
        if ins_titles:
            ins_updated = 0
            for title in ins_titles:
                song_id = resolve_song_id_with_artist(cursor, title, None)
                if song_id and update_chart_inscribed_flag(cursor, song_id, 3, 1):
                    ins_updated += 1
            print(f"updated {ins_updated} inscribed charts")
            
        conn.commit()
        print(f"save data to songs.db complete: {updated_count} songs")
        
        # Try to fill arcaea_id from user_scores.db
        fill_missing_arcaea_ids_from_scores()
        fill_song_titles_from_scores()
        
    except Exception as e:
        print(f"save data to songs.db error: {e}")
    finally:
        conn.close()

if __name__ == '__main__':
    open_wiki()