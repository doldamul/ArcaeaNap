import json
import re
import urllib.request
import urllib.parse
import urllib.error
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
        query_string = urllib.parse.urlencode(params)
        full_url = f"{WIKI_API_URL}?{query_string}"
        
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': '*/*'
        }
        
        req = urllib.request.Request(full_url, headers=headers)
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode('utf-8'))
        
        if 'error' in data:
            print(f"API Error: {data['error']['info']}")
            return
        
        html = data['parse']['text']['*']
        songs_data, ins_titles = parse_wiki_html(html)
        print(f"complete: {len(songs_data)} songs, {len(ins_titles)} inscribed")
        
        save_data(songs_data, ins_titles)
        
    except (urllib.error.URLError, TimeoutError) as e:
        print(f"HTTP request error: {e}")
    except Exception as e:
        print(f"Wiki crawling error: {e}")


def _extract_cell_parts(cell) -> list[str]:
    """
    HTML 셀에서 <hr> 태그를 기준으로 분리된 텍스트 목록을 반환한다.
    <hr> 태그가 없으면 단일 텍스트 문자열(있는 경우)을 포함한 리스트를 반환한다.
    """
    if not cell:
        return []
    if not cell.find('hr'):
        text = cell.get_text(strip=True)
        return [text] if text else []

    parts = []
    current = []
    for elem in cell.contents:
        if getattr(elem, 'name', None) == 'hr':
            part_text = ''.join(current).strip()
            if part_text:
                parts.append(part_text)
            current = []
        else:
            part_text = elem.get_text() if hasattr(elem, 'get_text') else str(elem)
            current.append(part_text)
    part_text = ''.join(current).strip()
    if part_text:
        parts.append(part_text)
    return parts


def _extract_pack_parts(cell) -> list[tuple[str, str]]:
    """
    HTML 셀에서 <hr> 기준으로 분리된 (pack_full, pack_abbr) 목록을 반환한다.
    <a> 태그의 title이 있으면 pack_full로 사용하고, 텍스트를 pack_abbr로 사용한다.
    """
    if not cell:
        return []

    # <hr> 기준 분리
    sub_elements = []
    current = []
    for elem in cell.contents:
        if getattr(elem, 'name', None) == 'hr':
            if current:
                sub_elements.append(current)
            current = []
        else:
            current.append(elem)
    if current:
        sub_elements.append(current)

    if not sub_elements:
        text = cell.get_text(strip=True)
        return [(text, text)] if text else []

    results = []
    for elem_list in sub_elements:
        a_titles = []
        text_parts = []
        for el in elem_list:
            if getattr(el, 'name', None) == 'a':
                if el.get('title'):
                    a_titles.append(el.get('title').strip())
                text_parts.append(el.get_text())
            elif hasattr(el, 'find_all'):
                for a in el.find_all('a'):
                    if a.get('title'):
                        a_titles.append(a.get('title').strip())
                text_parts.append(el.get_text())
            else:
                text_parts.append(el.get_text() if hasattr(el, 'get_text') else str(el))

        abbr = ''.join(text_parts).strip()
        full_name = a_titles[0] if a_titles else abbr
        if full_name or abbr:
            results.append((full_name, abbr))

    return results


DIFF_TAG_MAP = {
    'byd': 3, 'beyond': 3,
    'etr': 4, 'eternal': 4,
    'ins': 3, 'inscribed': 3,
    'ftr': 2, 'future': 2,
    'prs': 1, 'present': 1,
    'pst': 0, 'past': 0,
}


def _extract_version_and_chart_versions(cell, num_titles: int = 1) -> tuple[list[str], list[dict[int, str]]]:
    """
    HTML 셀에서 <hr> 기준으로 각 곡의 기본 버전과 난이도별 출시 버전(BYD/ETR 등)을 추출한다.
    반환값: (base_versions, chart_versions_list)
    """
    if not cell:
        return ["" for _ in range(num_titles)], [{} for _ in range(num_titles)]

    raw_parts = _extract_cell_parts(cell)
    if not raw_parts:
        return ["" for _ in range(num_titles)], [{} for _ in range(num_titles)]

    base_versions = []
    chart_versions_list = [{} for _ in range(num_titles)]

    # Case A: 곡 제목 개수와 raw_parts 개수가 1:1로 일치하는 경우 (예: PRAGMATISM / PRAGMATISM -RESURRECTION-)
    if num_titles > 1 and len(raw_parts) == num_titles:
        for i, part in enumerate(raw_parts):
            m = re.search(r'\[(BYD|ETR|INS|FTR|PRS|PST)\]', part, re.IGNORECASE)
            clean_part = re.sub(r'\[.*?\]', '', part).strip()
            clean_part = re.sub(r'\(.*?\)', '', clean_part).strip()
            v_match = re.search(r'\d+\.\d+(?:\.\d+[a-z]?)?', clean_part)
            ver_str = v_match.group(0) if v_match else clean_part.split('\n')[0].strip()
            base_versions.append(ver_str)
            if m:
                diff_tag = m.group(1).lower()
                diff_int = DIFF_TAG_MAP.get(diff_tag)
                if diff_int is not None:
                    chart_versions_list[i][diff_int] = ver_str
                    chart_versions_list[0][diff_int] = ver_str
        return base_versions, chart_versions_list

    # Case B: 단일 곡이거나 raw_parts 개수가 불일치하는 일반적인 경우
    for part in raw_parts:
        m = re.search(r'\[(BYD|ETR|INS|FTR|PRS|PST)\]', part, re.IGNORECASE)
        clean_part = re.sub(r'\[.*?\]', '', part).strip()
        clean_part = re.sub(r'\(.*?\)', '', clean_part).strip()
        v_match = re.search(r'\d+\.\d+(?:\.\d+[a-z]?)?', clean_part)
        ver_str = v_match.group(0) if v_match else clean_part.split('\n')[0].strip()

        if m:
            diff_tag = m.group(1).lower()
            diff_int = DIFF_TAG_MAP.get(diff_tag)
            if diff_int is not None:
                chart_versions_list[0][diff_int] = ver_str
                # 만약 base_versions가 비어있다면 이 버전을 후보로 사용할 수 있음
                if not base_versions:
                    base_versions.append(ver_str)
        else:
            if ver_str:
                base_versions.append(ver_str)

    # num_titles와 base_versions 길이 동기화
    if not base_versions:
        base_versions = [""] * num_titles
    elif len(base_versions) == 1 and num_titles > 1:
        base_versions = [base_versions[0]] * num_titles
    elif len(base_versions) < num_titles:
        last = base_versions[-1]
        base_versions += [last] * (num_titles - len(base_versions))
    elif len(base_versions) > num_titles:
        base_versions = base_versions[:num_titles]

    return base_versions, chart_versions_list


def _extract_version_parts(cell) -> list[str]:
    """
    HTML 셀에서 <hr> 기준으로 분리된 버전 문자열 목록을 반환한다 (레거시 호환용).
    """
    versions, _ = _extract_version_and_chart_versions(cell, 1)
    return versions


def _extract_pack_color(cell) -> str:
    """
    HTML 셀의 style 속성에서 배경색(HEX 등)을 추출한다.
    예: 'background:#E7DBFF; color:#FFFFFF;' -> '#E7DBFF'
    """
    if not cell:
        return ""
    if isinstance(cell, str):
        style = cell
    else:
        style = cell.get('style', '') or ''
    m = re.search(r'background(?:-color)?\s*:\s*(#[0-9a-fA-F]{3,8}|rgba?\([^)]+\))', style, re.IGNORECASE)
    if m:
        return m.group(1).strip()
    return ""


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
    col_pack = headers.index('pack') if 'pack' in headers else None
    col_update = headers.index('update') if 'update' in headers else None

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
                # <a> 태그가 없는 경우 <hr> 기준 또는 텍스트 직접 추출
                parts = _extract_cell_parts(cells[col_song])
                if parts:
                    titles = parts
                else:
                    continue

            artist = cells[col_artist].get_text(strip=True)

            # Inscribed 난이도 확인: INS 열에 내용이 있는지 여부
            is_ins = bool(col_ins is not None and len(cells) > col_ins and cells[col_ins].get_text(strip=True))
            if is_ins:
                for t in titles:
                    ins_titles.add(t)

            # Len 및 BPM 셀에서 hr 분리된 텍스트 목록 추출
            len_cell = cells[col_len] if len(cells) > col_len else None
            bpm_cell = cells[col_bpm] if len(cells) > col_bpm else None
            pack_cell = cells[col_pack] if col_pack is not None and len(cells) > col_pack else None
            update_cell = cells[col_update] if col_update is not None and len(cells) > col_update else None

            lengths = _extract_cell_parts(len_cell)
            bpms = _extract_cell_parts(bpm_cell)
            packs = _extract_pack_parts(pack_cell)
            versions, chart_versions_list = _extract_version_and_chart_versions(update_cell, len(titles))
            pack_color = _extract_pack_color(pack_cell)

            # 레거시 공백 구분자 호환성 (hr가 없고 titles 수와 일치할 때만 분리)
            if len(lengths) == 1 and ' ' in lengths[0] and len(titles) > 1:
                split_lens = lengths[0].split()
                if len(split_lens) == len(titles):
                    lengths = split_lens

            if len(bpms) == 1 and ' ' in bpms[0] and len(titles) > 1:
                split_bpms = bpms[0].split()
                if len(split_bpms) == len(titles):
                    bpms = split_bpms

            # 각 title별 length, bpm, pack, pack_abbr, version, pack_color, chart_versions 매핑
            num_titles = len(titles)
            for i, title in enumerate(titles):
                if len(lengths) == num_titles:
                    item_len = lengths[i]
                elif len(lengths) == 1:
                    item_len = lengths[0]
                elif i < len(lengths):
                    item_len = lengths[i]
                else:
                    item_len = lengths[-1] if lengths else ""

                if len(bpms) == num_titles:
                    item_bpm = bpms[i]
                elif len(bpms) == 1:
                    item_bpm = bpms[0]
                elif i < len(bpms):
                    item_bpm = bpms[i]
                else:
                    item_bpm = bpms[-1] if bpms else ""

                if len(packs) == num_titles:
                    item_pack, item_pack_abbr = packs[i]
                elif len(packs) == 1:
                    item_pack, item_pack_abbr = packs[0]
                elif i < len(packs):
                    item_pack, item_pack_abbr = packs[i]
                else:
                    item_pack, item_pack_abbr = packs[-1] if packs else ("", "")

                if len(versions) == num_titles:
                    item_ver = versions[i]
                elif len(versions) == 1:
                    item_ver = versions[0]
                elif i < len(versions):
                    item_ver = versions[i]
                else:
                    item_ver = versions[-1] if versions else ""

                item_chart_versions = chart_versions_list[i] if i < len(chart_versions_list) else {}

                songs_data.append((title, artist, item_len, item_bpm, item_pack, item_pack_abbr, item_ver, pack_color, item_chart_versions))

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
            update_song_wiki_metadata,
            update_chart_inscribed_flag,
            update_chart_version,
            fill_missing_arcaea_ids_from_scores,
            fill_song_titles_from_scores,
        )
        
        for item in data:
            title = item[0]
            artist = item[1]
            length_str = item[2]
            bpm = item[3]
            pack = item[4] if len(item) > 4 else None
            pack_abbr = item[5] if len(item) > 5 else None
            version = item[6] if len(item) > 6 else None
            pack_color = item[7] if len(item) > 7 else None
            chart_versions = item[8] if len(item) > 8 else {}

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
            
            # Update Metadata with pack, version, and pack_color
            update_song_wiki_metadata(cursor, song_id, artist, length_seconds, bpm, pack, pack_abbr, version, pack_color)
            updated_count += 1

            if song_id:
                # 1) 기본 곡 출시 버전으로 차트 버전 백필
                if version:
                    cursor.execute(
                        "UPDATE charts SET version = ? WHERE song_id = ? AND (version IS NULL OR version = '')",
                        (version, song_id)
                    )
                # 2) 별도 출시 버전(BYD/ETR 등) 업데이트
                if chart_versions:
                    for diff, c_ver in chart_versions.items():
                        update_chart_version(cursor, song_id, diff, c_ver)

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