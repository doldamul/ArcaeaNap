import os
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from configuration import config
import gspread
import sqlite3
import re

SCOPES = [
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/drive.file",
]

SPREADSHEET_ID = "1myl8cFTgMX6tim7Eqci4LNl6fzisuxcFrWt9EX0_obs" # Arcaea Song Database from ConsultantSheet

def open_sheet():
    creds = get_creds()
    print('creds: ', creds)
    
    gc = gspread.authorize(creds)
    sheet = gc.open_by_key(SPREADSHEET_ID)
    
    name_exception = {
        'Quon(Lanota)': 'quon', 
        'Quon(WACCA)': 'quonwacca', 
        'Genesis(Arcaea)': 'genesis',
        'Genesis(CHUNITHM)': 'genesischunithm',
    }

    # DB 초기화
    init_db()

    target_headers = {
        'bp': 'BP(M)',
        'perceived_bp': '체감 BP',
        's_bp': 'S-BP',
        'note_count': '노트수',
        'cut_200': '#200 컷',
    }

    tabs = ['_bp_load', '_song_database', '_sbp_load'] # _bp_load first as canonical source
    
    merged_data = {} # (lower_title, difficulty) -> {data} (key is normalized)
    canonical_names = {} # (lower_title, difficulty) -> (Real Title, Real Difficulty)

    for tab_name in tabs:
        print(f"Processing sheet: {tab_name}")
        try:
            tab = sheet.worksheet(tab_name)
            all_values = tab.get_values()
            
            if not all_values:
                continue

            col_indices = {}
            header = all_values[0] # first row of the table
            
            # 컬럼 매핑
            for col_idx, cell_val in enumerate(header):
                cell_val = cell_val.strip()
                for key, possibilities in target_headers.items():
                    if key not in col_indices and cell_val == possibilities:
                        col_indices[key] = col_idx
            
            print(f"Columns: {col_indices}")
            
            # 데이터 추출
            for row in all_values[1:]:
                # 제목과 난이도 분리
                raw_name = row[0].strip()
                try:
                    title, difficulty_str = title_for_wiki(raw_name)
                except:
                    # 포맷이 안 맞으면 스킵 (예: 헤더가 반복되거나 이상한 데이터)
                    continue

                # Key normalization for case-insensitive matching
                norm_key = (title.lower(), difficulty_str)
                
                # If this is the first time seeing this song (likely from _bp_load due to order),
                # set it as the canonical name.
                if norm_key not in canonical_names:
                    canonical_names[norm_key] = (title, difficulty_str)
                    merged_data[norm_key] = {
                        'title': title, # Use the first encountered case (from _bp_load)
                        'difficulty': difficulty_str,
                        'bp': None,
                        'perceived_bp': None,
                        's_bp': None,
                        'note_count': None,
                        'cut_200': None
                    }
                
                song = merged_data[norm_key]
                
                for col_key, idx in col_indices.items():
                    song[col_key] = row[idx]

        except Exception as e:
            print(f"Error processing {tab_name}: {e}")

    print(f"Total unique songs combined: {len(merged_data)}")
    save_to_db(merged_data.values())

def init_db():
    db_path = os.path.join(config['general']['cache_path'], 'consultant_data.db')
    with sqlite3.connect(db_path) as conn:
        cursor = conn.cursor()
        cursor.execute('DROP TABLE IF EXISTS songs')
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS songs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT,
                difficulty TEXT,
                bp REAL,
                perceived_bp REAL,
                s_bp REAL,
                note_count INTEGER,
                cut_200 INTEGER,
                UNIQUE(title, difficulty)
            )
        ''')
        conn.commit()

def save_to_db(data):
    db_path = os.path.join(config['general']['cache_path'], 'consultant_data.db')
    with sqlite3.connect(db_path) as conn:
        cursor = conn.cursor()
        
        for entry in data:
            def parse_float(val):
                if not val: return None
                if isinstance(val, (int, float)): return float(val)
                try: 
                    # 쉼표 제거 (ex: 1,000 -> 1000)
                    clean = val.replace(',', '').replace('~', '').strip() 
                    if not clean: return None
                    return float(clean)
                except: return None
            
            def parse_int(val):
                if not val: return None
                if isinstance(val, (int, float)): return int(val)
                try: 
                    clean = val.replace(',', '').replace('~', '').strip()
                    if not clean: return None
                    return int(float(clean)) # 1000.0 방지
                except: return None

            cursor.execute('''
                INSERT OR REPLACE INTO songs 
                (title, difficulty, bp, perceived_bp, s_bp, note_count, cut_200)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ''', (
                entry['title'],
                entry['difficulty'],
                parse_float(entry['bp']),
                parse_float(entry['perceived_bp']),
                parse_float(entry['s_bp']),
                parse_int(entry['note_count']),
                parse_int(entry['cut_200'])
            ))
        conn.commit()
        print(f"Saved {len(list(data))} rows to database.")

# Regex to capture "Title [Difficulty]" format.
# e.g. "Remind the Souls (Short Version) [PRS]" -> "Remind the Souls (Short Version)", "PRS"
def title_for_wiki(name):
    match = re.match(r'^(.*) \[(.*)\]$', name)
    return match.group(1), match.group(2)

def get_creds():
    token_filename = 'token.json'
    token_filepath = os.path.join(config['general']['cache_path'], token_filename)
    
    secret_filename = 'client_secret.json'
    secret_filepath = os.path.join(config['general']['cache_path'], secret_filename)
    
    creds = None
    if os.path.exists(token_filepath):
        creds = Credentials.from_authorized_user_file(token_filepath, SCOPES)
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_secrets_file(
                secret_filepath, SCOPES
            )
            creds = flow.run_local_server(port=0) # TODO: mannually open URL to set the browser as configuration, and handle the redirect
        with open(token_filepath, "w") as token:
            token.write(creds.to_json())
    return creds

if __name__ == "__main__":
    open_sheet()