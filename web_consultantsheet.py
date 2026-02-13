import os
import json
import keyring
import threading
import socket
import wsgiref.simple_server
import wsgiref.util
import webbrowser
import time
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from configuration import config
import gspread
import re
from db_utils import init_songs_db, get_connection, resolve_song_id
from common_types import Difficulty

SCOPES = [
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/drive.file",
    "https://www.googleapis.com/auth/userinfo.email",
    "openid"
]

SPREADSHEET_ID = "1myl8cFTgMX6tim7Eqci4LNl6fzisuxcFrWt9EX0_obs" # Arcaea Song Database from ConsultantSheet

def open_sheet():
    creds = get_creds()
    
    gc = gspread.authorize(creds)
    sheet = gc.open_by_key(SPREADSHEET_ID)

    init_songs_db()

    target_headers = {
        'level': '레벨',
        'bp': 'BP(M)',
        'perceived_bp': '체감 BP',
        's_bp': 'S-BP',
        'note_count': '노트수',
        'cut_200': '#200 컷',
        'ignore_chart': '⛔',
        'skill_issues': '⚠️',
        'contain_slowspeed': 'isLower'
    }

    tabs = ['_bp_load', '_song_database', '_sbp_load'] # _bp_load first as canonical source
    
    merged_data = {} # (lower_title, difficulty) -> {data} (key is normalized)
    canonical_names = {} # (lower_title, difficulty) -> (Real Title, Real Difficulty)

    for tab_name in tabs:
        print(f"Processing sheet: {tab_name}")
        try:
            tab = sheet.worksheet(tab_name)
            all_values = tab.get_values(value_render_option='UNFORMATTED_VALUE')
            
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
                        'level': None,
                        'bp': None,
                        'perceived_bp': None,
                        's_bp': None,
                        'note_count': None,
                        'cut_200': None,
                        'ignore_chart': None,
                        'skill_issues': None,
                        'contain_slowspeed': None
                    }
                
                song = merged_data[norm_key]
                
                for col_key, idx in col_indices.items():
                    song[col_key] = row[idx]

        except Exception as e:
            print(f"Error processing {tab_name}: {e}")

    print(f"Total unique songs combined: {len(merged_data)}")
    save_to_db(merged_data.values())

def save_to_db(data):
    conn = get_connection()
    cursor = conn.cursor()
    
    try:
        updated_count = 0
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
                
            def parse_bool(val: str) -> int:
                if not val: return None
                if isinstance(val, bool): return int(val)
                try: return int(val.lower() == 'true')
                except: return None

            title = entry['title']
            difficulty_str = entry['difficulty']
            try:
                difficulty = Difficulty[difficulty_str].value
            except KeyError:
                print(f"Unknown difficulty: {difficulty_str} for song: {title}")
                continue
            
            # 1. Resolve Song ID
            song_id = resolve_song_id(cursor, title)
            
            # 2. Insert/Update Chart
            cursor.execute('''
                INSERT INTO charts 
                (song_id, difficulty, level, bp, perceived_bp, s_bp, note_count, cut_200, ignore_chart, skill_issues, contain_slowspeed)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(song_id, difficulty) DO UPDATE SET
                    level=excluded.level,
                    bp=excluded.bp,
                    perceived_bp=excluded.perceived_bp,
                    s_bp=excluded.s_bp,
                    note_count=excluded.note_count,
                    cut_200=excluded.cut_200,
                    ignore_chart=excluded.ignore_chart,
                    skill_issues=excluded.skill_issues,
                    contain_slowspeed=excluded.contain_slowspeed
            ''', (
                song_id,
                difficulty,
                entry['level'],
                parse_float(entry['bp']),
                parse_float(entry['perceived_bp']),
                parse_float(entry['s_bp']),
                parse_int(entry['note_count']),
                parse_int(entry['cut_200']),
                parse_bool(entry['ignore_chart']),
                parse_bool(entry['skill_issues']),
                parse_bool(entry['contain_slowspeed'])
            ))
            updated_count += 1
            
        conn.commit()
        print(f"Saved/Updated {updated_count} charts to database.")
        
        # Try to fill arcaea_id from user_scores.db
        from db_utils import fill_missing_arcaea_ids_from_scores
        fill_missing_arcaea_ids_from_scores()
    
    except Exception as e:
        print(f"Error saving to DB: {e}")
    finally:
        conn.close()

# Regex to capture "Title [Difficulty]" format.
# e.g. "Remind the Souls (Short Version) [PRS]" -> "Remind the Souls (Short Version)", "PRS"
def title_for_wiki(name):
    match = re.match(r'^(.*) \[(.*)\]$', name)
    return match.group(1), match.group(2)

def get_creds(cancellation_context=None):
    connections_filepath = os.path.join(config['general']['cache_path'], 'account_connections.json')
    secret_filename = 'client_secret.json'
    secret_filepath = os.path.join(config['general']['cache_path'], secret_filename)
    
    creds = None
    token_data = None
    
    # Load token from account_connections.json
    if os.path.exists(connections_filepath):
        try:
            with open(connections_filepath, 'r', encoding='utf-8') as f:
                connections = json.load(f)
                gs_info = connections.get('google_sheet', {})
                if gs_info.get('connected', False) and 'token' in gs_info:
                    token_data = gs_info['token'].copy()
                    
                    # Restore sensitive data from keyring
                    token_data['token'] = keyring.get_password('ArcaeaNap', 'google_token') or ''
                    token_data['refresh_token'] = keyring.get_password('ArcaeaNap', 'google_refresh_token') or ''
                    token_data['client_secret'] = keyring.get_password('ArcaeaNap', 'google_client_secret') or ''
                    
                    # Create Credentials object
                    try:
                        creds = Credentials.from_authorized_user_info(token_data, SCOPES)
                    except Exception as e:
                        print(f"Error creating credentials from saved token: {e}")
                        creds = None
        except Exception as e:
            print(f"Error loading connections: {e}")
    
    if creds and creds.expired and creds.refresh_token:
        try:
            creds.refresh(Request())
            # Save refreshed token
            _save_google_credentials(creds, connections_filepath)
        except Exception as e:
            print(f"Token refresh failed: {e}. Re-authenticating...")
            creds = None
    
    if not creds or not creds.valid:
        if cancellation_context and cancellation_context.is_cancelled():
             return None
             
        flow = InstalledAppFlow.from_client_secrets_file(
            secret_filepath, SCOPES
        )
        # Use our custom cancellable flow
        creds = run_cancellable_flow(flow, cancellation_context)
        
        if creds:
            # Save credentials
            _save_google_credentials(creds, connections_filepath)
    
    return creds

def _save_google_credentials(creds, connections_filepath):
    """Save Google credentials to account_connections.json."""
    try:
        # Extract user email using Google API Client
        user_email = ''
        try:
            user_info_service = build('oauth2', 'v2', credentials=creds)
            user_info = user_info_service.userinfo().get().execute()
            user_email = user_info.get('email', '')
        except Exception as e:
            print(f"Error extracting user email: {e}")
        
        # Get token info
        token_info = json.loads(creds.to_json())
        
        # Save sensitive data to keyring
        if 'token' in token_info:
            keyring.set_password('ArcaeaNap', 'google_token', token_info['token'])
            token_info['token'] = ''
        if 'refresh_token' in token_info:
            keyring.set_password('ArcaeaNap', 'google_refresh_token', token_info['refresh_token'])
            token_info['refresh_token'] = ''
        if 'client_secret' in token_info:
            keyring.set_password('ArcaeaNap', 'google_client_secret', token_info['client_secret'])
            token_info['client_secret'] = ''
        
        # Load existing connections or create new
        connections = {}
        if os.path.exists(connections_filepath):
            try:
                with open(connections_filepath, 'r', encoding='utf-8') as f:
                    connections = json.load(f)
            except Exception:
                pass
        
        # Update google_sheet section
        import time
        connections['google_sheet'] = {
            'connected': True,
            'connected_at': int(time.time()),
            'user_email': user_email,
            'token': token_info
        }
        
        with open(connections_filepath, 'w', encoding='utf-8') as f:
            json.dump(connections, f, ensure_ascii=False, indent=2)
    except Exception as e:
        print(f"Error saving Google credentials: {e}")

class CancellationContext:
    def __init__(self):
        self._cancel_event = threading.Event()
        self._server = None
        
    def cancel(self):
        """Signal cancellation and shutdown the server if running."""
        self._cancel_event.set()
        if self._server:
            try:
                self._server.shutdown()
            except Exception as e:
                print(f"Error shutting down server: {e}")
            try:
                self._server.server_close()
            except Exception as e:
                print(f"Error closing server socket: {e}")

    def set_server(self, server):
        self._server = server
        
    def is_cancelled(self):
        return self._cancel_event.is_set()

def run_cancellable_flow(flow, cancellation_context=None):
    """
    Run the OAuth flow using a local server that can be cancelled.
    Based on InstalledAppFlow.run_local_server but with cancellation support.
    """
    # Find a free port
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(('localhost', 0))
    port = sock.getsockname()[1]
    sock.close()

    redirect_uri = f'http://localhost:{port}/'
    flow.redirect_uri = redirect_uri
    
    auth_url, _ = flow.authorization_url(prompt='consent')
    
    # Shared state for the WSGI app
    state = {'code': None}
    
    def simple_app(environ, start_response):
        """WSGI app to handle the redirect."""
        from urllib.parse import parse_qs
        
        if environ['PATH_INFO'] != '/':
            start_response('404 Not Found', [('Content-type', 'text/plain')])
            return [b'Not Found']

        query = parse_qs(environ['QUERY_STRING'])
        
        if 'code' in query:
            state['code'] = query['code'][0]
            start_response('200 OK', [('Content-type', 'text/html; charset=utf-8')])
            return [b'''
            <html>
                <head><title>Authentication Successful</title></head>
                <body style="font-family: sans-serif; text-align: center; display: flex; flex-direction: column; justify-content: center; align-items: center; height: 100vh; margin: 0;">
                    <h1 style="color: #4CAF50;">Authentication Successful!</h1>
                    <p>You can close this window and return to Arcaea Nap.</p>
                    <script>window.close()</script>
                </body>
            </html>
            ''']
        
        if 'error' in query:
            start_response('200 OK', [('Content-type', 'text/plain')])
            return [f"Authentication error: {query['error'][0]}".encode('utf-8')]
            
        start_response('400 Bad Request', [('Content-type', 'text/plain')])
        return [b'No code found in request']

    # Create server
    server = wsgiref.simple_server.make_server('localhost', port, simple_app)
    
    if cancellation_context:
        cancellation_context.set_server(server)

    # Open browser
    print(f"Opening browser for OAuth: {auth_url}")
    webbrowser.open(auth_url)

    # Run server in a separate thread because serve_forever blocks
    server_thread = threading.Thread(target=server.serve_forever)
    server_thread.daemon = True
    server_thread.start()
    
    # Main thread waits for code or cancellation
    try:
        while state['code'] is None:
            if cancellation_context and cancellation_context.is_cancelled():
                print("OAuth flow cancelled by user.")
                # Server shutdown handles cleanup
                return None
            time.sleep(0.1)
    except KeyboardInterrupt:
        if cancellation_context:
            cancellation_context.cancel()
        return None
    finally:
        # Ensure server is shut down
        try:
            server.shutdown()
            server.server_close()
        except:
            pass
        server_thread.join(timeout=1.0)
    
    if state['code']:
        flow.fetch_token(code=state['code'])
        return flow.credentials
    return None

if __name__ == "__main__":
    open_sheet()