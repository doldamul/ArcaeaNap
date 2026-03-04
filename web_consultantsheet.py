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
from repositories.song_repository import init_songs_db, get_connection, resolve_song_id
from models.types import Difficulty

SCOPES = [
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/drive.file",
    "https://www.googleapis.com/auth/userinfo.email",
    "openid"
]

SPREADSHEET_ID = "1myl8cFTgMX6tim7Eqci4LNl6fzisuxcFrWt9EX0_obs" # Arcaea Song Database from ConsultantSheet

# Reverse alias map: Official Title (DB) -> Simplified Title (Sheet)
# Built from TITLE_ALIAS_MAP in db_utils.py (which maps Sheet -> DB)
REVERSE_ALIAS_MAP = {
    '͟͝͞Ⅱ́̕': 'II',
    'Anökumene': 'Anokumene',
    'nέo κósmo': 'neo kosmo',
    'Alice à la mode': 'Alice a la mode',
    'April showers': 'April Showers',
}

def _get_bound_sheet_id():
    """Get bound sheet ID from account_connections.json, or None if not bound."""
    connections_filepath = os.path.join(config['general']['cache_path'], 'account_connections.json')
    if os.path.exists(connections_filepath):
        try:
            with open(connections_filepath, 'r', encoding='utf-8') as f:
                connections = json.load(f)
                gs_info = connections.get('google_sheet', {})
                bound_id = gs_info.get('bound_sheet_id', '')
                if bound_id:
                    return bound_id
        except Exception:
            pass
    return None


def run_google_picker(cancellation_context=None):
    """
    Open Google Picker in browser to let user select a spreadsheet.
    Returns (sheet_id, sheet_title) on success, None if cancelled/failed.
    """
    creds = get_creds(cancellation_context)
    if not creds:
        return None
    
    access_token = creds.token
    
    # Read optional API key / app ID from client_secret.json
    secret_filepath = os.path.join(config['general']['cache_path'], 'client_secret.json')
    api_key = ''
    app_id = ''
    try:
        with open(secret_filepath, 'r') as f:
            secret_data = json.load(f)
        installed = secret_data.get('installed', secret_data.get('web', {}))
        api_key = installed.get('api_key', secret_data.get('api_key', ''))
        app_id = installed.get('app_id', secret_data.get('app_id', ''))

        # If app_id is not explicitly available, derive numeric project number
        # from OAuth client_id prefix (e.g. 1234567890-xxxxx.apps.googleusercontent.com)
        if not app_id:
            client_id = installed.get('client_id', '')
            match = re.match(r'^(\d+)-', client_id)
            if match:
                app_id = match.group(1)
    except Exception:
        pass

    if not api_key:
        raise Exception(
            "Google Picker requires API key. Add installed.api_key in client_secret.json."
        )
    
    # Find a free port
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(('localhost', 0))
    port = sock.getsockname()[1]
    sock.close()
    
    state = {
        'result': None,
        'done': False,
        'reason': None,
        'page_loaded': False,
        'last_ping_at': None
    }
    picker_html = _build_picker_html(access_token, api_key, app_id, port)
    
    def picker_app(environ, start_response):
        path = environ['PATH_INFO']
        now = time.monotonic()

        if state['done']:
            start_response('200 OK', [('Content-type', 'text/plain')])
            return [b'OK']
        
        if path == '/':
            state['page_loaded'] = True
            state['last_ping_at'] = now
            start_response('200 OK', [('Content-type', 'text/html; charset=utf-8')])
            return [picker_html.encode('utf-8')]
        elif path == '/heartbeat':
            state['last_ping_at'] = now
            start_response('204 No Content', [])
            return [b'']
        elif path == '/picked':
            from urllib.parse import parse_qs
            query = parse_qs(environ['QUERY_STRING'])
            sheet_id = query.get('id', [''])[0]
            sheet_name = query.get('name', [''])[0]
            if sheet_id:
                state['result'] = (sheet_id, sheet_name)
                state['reason'] = 'picked'
            state['done'] = True
            start_response('200 OK', [('Content-type', 'text/html; charset=utf-8')])
            return [b'''<html><body style="font-family:sans-serif;text-align:center;padding-top:40vh">
                <h2 style="color:#4CAF50">Sheet Selected!</h2>
                <p>You can close this window and return to Arcaea Nap.</p>
                <script>window.close()</script></body></html>''']
        elif path == '/cancelled':
            state['reason'] = 'cancelled'
            state['done'] = True
            print("Google Picker cancelled from browser UI.")
            start_response('200 OK', [('Content-type', 'text/html; charset=utf-8')])
            return [b'''<html><body style="font-family:sans-serif;text-align:center;padding-top:40vh">
                <p>Cancelled. You can close this window.</p>
                <script>setTimeout(function(){window.close();}, 0)</script></body></html>''']
        elif path == '/window_closed':
            state['reason'] = 'window_closed'
            state['done'] = True
            start_response('204 No Content', [])
            return [b'']
        
        start_response('404 Not Found', [('Content-type', 'text/plain')])
        return [b'Not Found']
    
    server = wsgiref.simple_server.make_server('localhost', port, picker_app)
    
    if cancellation_context:
        cancellation_context.set_server(server)
    
    print(f"Opening Google Picker at http://localhost:{port}/")
    webbrowser.open(f'http://localhost:{port}/')
    
    server_thread = threading.Thread(target=server.serve_forever)
    server_thread.daemon = True
    server_thread.start()
    
    try:
        while not state['done']:
            if cancellation_context and cancellation_context.is_cancelled():
                print("Google Picker cancelled by user.")
                return None

            # Browser session close detection fallback:
            # if picker page was loaded but heartbeat stopped for a while,
            # assume browser window/tab was closed by user.
            if state['page_loaded'] and state['last_ping_at'] is not None:
                if time.monotonic() - state['last_ping_at'] > 3.0:
                    state['reason'] = state['reason'] or 'window_closed_timeout'
                    state['done'] = True
                    break
            time.sleep(0.1)
    except KeyboardInterrupt:
        if cancellation_context:
            cancellation_context.cancel()
        return None
    finally:
        def _shutdown_server():
            try:
                server.shutdown()
            except Exception:
                pass
            try:
                server.server_close()
            except Exception:
                pass

        shutdown_thread = threading.Thread(target=_shutdown_server, daemon=True)
        shutdown_thread.start()
        shutdown_thread.join(timeout=1.0)
        server_thread.join(timeout=1.0)

        if shutdown_thread.is_alive():
            print("Google Picker server shutdown timeout; continuing cleanup.")
    
    if state['reason'] in ('cancelled', 'window_closed', 'window_closed_timeout'):
        print(f"Google Picker ended without selection ({state['reason']}).")

    return state['result']


def _build_picker_html(access_token, api_key, app_id, callback_port):
    """Build HTML page with Google Picker for spreadsheet selection."""
    picker_config_parts = []
    if api_key:
        picker_config_parts.append(f'.setDeveloperKey("{api_key}")')
    if app_id:
        picker_config_parts.append(f'.setAppId("{app_id}")')
    picker_config = '\n                '.join(picker_config_parts)
    
    return f"""<!DOCTYPE html>
<html><head>
    <title>Select a Spreadsheet - Arcaea Nap</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            display: flex; flex-direction: column;
            align-items: center; justify-content: center;
            height: 100vh; margin: 0; background: #fafafa;
        }}
        .status {{ color: #666; font-size: 16px; margin-bottom: 16px; }}
        .cancel-btn {{
            padding: 8px 24px; border: 1px solid #ccc;
            border-radius: 6px; background: white;
            cursor: pointer; font-size: 14px; color: #333;
        }}
        .cancel-btn:hover {{ background: #f0f0f0; }}
    </style>
</head><body>
    <p class="status" id="status">Loading Google Picker...</p>
    <button class="cancel-btn" onclick="onCancelClick()">Cancel</button>
    <script>
        var sessionTerminated = false;
        var heartbeatTimer = null;

        function markSessionTerminated() {{
            sessionTerminated = true;
            if (heartbeatTimer) {{
                clearInterval(heartbeatTimer);
                heartbeatTimer = null;
            }}
        }}

        function pingHeartbeat() {{
            fetch('http://localhost:{callback_port}/heartbeat', {{
                method: 'GET',
                cache: 'no-store',
                keepalive: true
            }}).catch(function() {{}});
        }}

        function startHeartbeat() {{
            pingHeartbeat();
            heartbeatTimer = setInterval(pingHeartbeat, 1000);
        }}

        function notifyWindowClosed() {{
            if (sessionTerminated) return;

            markSessionTerminated();
            var closeUrl = 'http://localhost:{callback_port}/window_closed';
            try {{
                if (navigator.sendBeacon) {{
                    navigator.sendBeacon(closeUrl, 'closed');
                    return;
                }}
            }} catch (e) {{}}

            try {{
                fetch(closeUrl, {{ method: 'POST', keepalive: true }}).catch(function() {{}});
            }} catch (e) {{}}
        }}

        function onCancelClick() {{
            markSessionTerminated();
            location.href = 'http://localhost:{callback_port}/cancelled';
        }}

        window.onerror = function(message) {{
            document.getElementById('status').textContent = 'Picker error: ' + message;
        }};

        window.addEventListener('beforeunload', notifyWindowClosed);
        window.addEventListener('pagehide', notifyWindowClosed);

        function onApiLoad() {{
            if (!window.gapi) {{
                document.getElementById('status').textContent = 'Failed to load Google API script.';
                return;
            }}
            gapi.load('picker', {{ callback: createPicker }});
        }}

        window.addEventListener('load', function() {{
            var script = document.createElement('script');
            script.src = 'https://apis.google.com/js/api.js';
            script.async = true;
            script.defer = true;
            script.onload = onApiLoad;
            script.onerror = function() {{
                document.getElementById('status').textContent = 'Could not load https://apis.google.com/js/api.js';
            }};
            document.head.appendChild(script);
        }});

        function createPicker() {{
            try {{
                startHeartbeat();
                var view = new google.picker.DocsView(google.picker.ViewId.SPREADSHEETS);
                view.setMimeTypes('application/vnd.google-apps.spreadsheet');
                view.setMode(google.picker.DocsViewMode.LIST);
                var picker = new google.picker.PickerBuilder()
                    .addView(view)
                    .enableFeature(google.picker.Feature.NAV_HIDDEN)
                    .setOAuthToken('{access_token}')
                    .setCallback(pickerCallback)
                    .setTitle('Select a Spreadsheet')
                    {picker_config}
                    .build();
                picker.setVisible(true);
                document.getElementById('status').textContent = 'Select a spreadsheet from the picker.';
            }} catch (e) {{
                document.getElementById('status').textContent = 'Failed to open picker: ' + e.message;
            }}
        }}
        function pickerCallback(data) {{
            if (data.action === google.picker.Action.PICKED) {{
                markSessionTerminated();
                var doc = data.docs[0];
                location.href = 'http://localhost:{callback_port}/picked'
                    + '?id=' + encodeURIComponent(doc.id)
                    + '&name=' + encodeURIComponent(doc.name);
            }} else if (data.action === google.picker.Action.CANCEL) {{
                markSessionTerminated();
                location.href = 'http://localhost:{callback_port}/cancelled';
            }}
        }}
    </script>
</body></html>"""


def send_scores_to_sheet(sheet_id=None, log_callback=None, cancellation_context=None):
    """
    Send best scores from local DB to the bound Google Sheet's score input tab.
    Finds the '점수 입력 [Score Input]' tab, matches Song title + Diff columns
    with local DB, and batch-updates the Score column.
    
    Returns: (updated_count, total_rows) tuple
    """
    from repositories.song_repository import get_all_songs_with_charts, TITLE_ALIAS_MAP
    from services.score_query_service import get_best_scores_per_chart
    
    def log(msg):
        print(f"[SendData] {msg}")
        if log_callback:
            log_callback(msg)
    
    if not sheet_id:
        sheet_id = _get_bound_sheet_id()
    
    if not sheet_id:
        raise Exception("No sheet bound. Please bind a sheet first.")
    
    creds = get_creds(cancellation_context)
    if not creds:
        raise Exception("Google authentication failed")
    
    gc = gspread.authorize(creds)
    sheet = gc.open_by_key(sheet_id)
    
    # Find score input tab
    score_tab = None
    for ws in sheet.worksheets():
        title_lower = ws.title.lower()
        if '점수 입력' in title_lower or 'score input' in title_lower:
            score_tab = ws
            break
    
    if not score_tab:
        raise Exception("Could not find '점수 입력 [Score Input]' tab in the sheet")
    
    log(f"Found tab: {score_tab.title}")
    
    # Read all values
    all_values = score_tab.get_values()
    if not all_values:
        raise Exception("Score input tab is empty")
    
    # Parse headers - support multilingual column names
    header = all_values[3]
    title_col = None
    diff_col = None
    score_col = None
    
    TITLE_HEADERS = {'Song title', '곡명', '曲名'}
    DIFF_HEADERS = {'Diff', '난이도', '難易度'}
    SCORE_HEADERS = {'Score', '점수', 'スコア'}
    
    for idx, cell_val in enumerate(header):
        cell_str = str(cell_val).strip()
        if cell_str in TITLE_HEADERS:
            title_col = idx
        elif cell_str in DIFF_HEADERS:
            diff_col = idx
        elif cell_str in SCORE_HEADERS:
            score_col = idx
    
    if title_col is None or diff_col is None or score_col is None:
        raise Exception(
            f"Missing required columns. Found: "
            f"title={'yes' if title_col is not None else 'no'}, "
            f"diff={'yes' if diff_col is not None else 'no'}, "
            f"score={'yes' if score_col is not None else 'no'}"
        )
    
    log(f"Columns: title={title_col}, diff={diff_col}, score={score_col}")
    
    # Load local data
    songs_data = get_all_songs_with_charts()
    best_scores = get_best_scores_per_chart(config['general']['cache_path'])
    
    # Build title -> arcaea_id lookup (case-insensitive)
    # DB titles are the "official" titles after TITLE_ALIAS_MAP resolution
    title_to_arcaea_id = {}  # lower(title) -> arcaea_id
    for song_data in songs_data.values():
        title = song_data.get('title', '')
        arcaea_id = song_data.get('arcaea_id', '')
        if title and arcaea_id:
            title_to_arcaea_id[title.lower()] = arcaea_id
    
    # Difficulty string -> int mapping
    diff_str_to_int = {
        'PST': Difficulty.PST.value,
        'PRS': Difficulty.PRS.value,
        'FTR': Difficulty.FTR.value,
        'BYD': Difficulty.BYD.value,
        'ETR': Difficulty.ETR.value,
    }
    
    # Prepare batch updates
    batch_updates = []
    matched_count = 0
    total_data_rows = 0
    
    for row_idx, row in enumerate(all_values[1:], start=2):  # 1-indexed, skip header
        if cancellation_context and cancellation_context.is_cancelled():
            raise Exception("Cancelled by user")
        
        # Ensure row has enough columns
        if len(row) <= max(title_col, diff_col):
            continue
        
        sheet_title = str(row[title_col]).strip()
        sheet_diff = str(row[diff_col]).strip().upper()
        
        if not sheet_title or not sheet_diff:
            continue
        
        total_data_rows += 1
        
        # Convert difficulty string
        difficulty_int = diff_str_to_int.get(sheet_diff)
        if difficulty_int is None:
            continue
        
        # Match title: try direct match first, then alias map
        lookup_title = sheet_title.lower()
        
        # Apply TITLE_ALIAS_MAP (Sheet simplified -> DB official)
        mapped_title = TITLE_ALIAS_MAP.get(sheet_title)
        if mapped_title:
            lookup_title = mapped_title.lower()
        
        arcaea_id = title_to_arcaea_id.get(lookup_title)
        if not arcaea_id:
            continue
        
        # Look up best score
        score_data = best_scores.get((arcaea_id, difficulty_int))
        if not score_data or not score_data.get('score'):
            continue
        
        # Convert score_col index to A1 notation
        col_letter = _col_index_to_letter(score_col)
        cell_ref = f"{col_letter}{row_idx}"
        
        batch_updates.append({
            'range': cell_ref,
            'values': [[score_data['score']]]
        })
        matched_count += 1
    
    if batch_updates:
        log(f"Sending {matched_count} scores...")
        score_tab.batch_update(batch_updates, value_input_option='RAW')
    
    log(f"Done: {matched_count}/{total_data_rows} rows updated")
    return matched_count, total_data_rows


def _col_index_to_letter(index):
    """Convert 0-based column index to A1 notation letter (0->A, 1->B, ..., 25->Z, 26->AA)."""
    result = ''
    while True:
        result = chr(ord('A') + index % 26) + result
        index = index // 26 - 1
        if index < 0:
            break
    return result


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
        'skill_issues': '⚠️'
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
                        'skill_issues': None
                    }
                
                song = merged_data[norm_key]
                
                for col_key, idx in col_indices.items():
                    song[col_key] = row[idx]

        except Exception as e:
            print(f"Error processing {tab_name}: {e}")

    print(f"Total unique songs combined: {len(merged_data)}")
    save_to_db(merged_data.values())

def get_sheet_version_info(sheet_id=None, cancellation_context=None):
    """
    Get version information from the bound Google Sheet's 'Main' tab.
    Looks for:
    - '현재 버전' / 'Current version' / '現在バージョン' -> Returns value in right cell
    - '대응 Arcaea 버전' / 'Arcaea's version' / 'Arcaeaバージョン' -> Returns value in right cell
    
    Returns: dict { 'sheet_ver': str, 'arcaea_ver': str, 'disconnected': bool (optional) }
    """
    if not sheet_id:
        sheet_id = _get_bound_sheet_id()
    
    if not sheet_id:
        return {'sheet_ver': '?', 'arcaea_ver': '?'}
    
    try:
        # Request non-interactive credentials (don't open browser automatically)
        creds = get_creds(cancellation_context, interactive=False)
        if not creds:
            # If creds is None in non-interactive mode, it means the token was
            # expired/revoked and has been cleared. Signal disconnection.
            return {'sheet_ver': '?', 'arcaea_ver': '?', 'disconnected': True}
        
        gc = gspread.authorize(creds)
        sheet = gc.open_by_key(sheet_id)
        
        # Find Main tab - look for English/Korean/Japanese variations
        main_tab = None
        target_names = ['main', '메인', '메인 [main]', 'main [메인]']
        
        for ws in sheet.worksheets():
            ws_title = ws.title.lower().strip()
            # Check exact match or partial match for target names
            if any(t in ws_title for t in target_names):
                main_tab = ws
                break
        
        if not main_tab:
            # Fallback: try first tab if named roughly right, or just first tab? No, risky.
            return {'sheet_ver': '?', 'arcaea_ver': '?'}
            
        # Read a reasonable chunk of data (e.g., A1:Z50) to find the labels
        # Labels are usually near the top
        data = main_tab.get('A1:Z50')
        
        sheet_ver = '?'
        arcaea_ver = '?'
        
        # Labels to search for
        SHEET_VER_LABELS = ['현재 버전', 'current version', '現在バージョン']
        ARCAEA_VER_LABELS = ['대응 arcaea 버전', "arcaea's version", 'arcaeaバージョン']
        
        for row_idx, row in enumerate(data):
            for col_idx, cell_value in enumerate(row):
                if not isinstance(cell_value, str):
                    continue
                    
                cell_lower = cell_value.lower().strip()
                
                # Check for Sheet Version
                if sheet_ver == '?' and any(label in cell_lower for label in SHEET_VER_LABELS):
                    # version is in the cell to the right
                    if col_idx + 1 < len(row):
                        sheet_ver = str(row[col_idx + 1]).strip()
                
                # Check for Arcaea Version
                if arcaea_ver == '?' and any(label in cell_lower for label in ARCAEA_VER_LABELS):
                    # version is in the cell to the right
                    if col_idx + 1 < len(row):
                        arcaea_ver = str(row[col_idx + 1]).strip()
                        
            if sheet_ver != '?' and arcaea_ver != '?':
                break
                
        return {'sheet_ver': sheet_ver, 'arcaea_ver': arcaea_ver}
        
    except Exception as e:
        print(f"Error fetching sheet version info: {e}")
        return {'sheet_ver': '?', 'arcaea_ver': '?'}


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
                (song_id, difficulty, level, bp, perceived_bp, s_bp, note_count, cut_200, ignore_chart, skill_issues)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(song_id, difficulty) DO UPDATE SET
                    level=excluded.level,
                    bp=excluded.bp,
                    perceived_bp=excluded.perceived_bp,
                    s_bp=excluded.s_bp,
                    note_count=excluded.note_count,
                    cut_200=excluded.cut_200,
                    ignore_chart=excluded.ignore_chart,
                    skill_issues=excluded.skill_issues
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
                parse_bool(entry['skill_issues'])
            ))
            updated_count += 1
            
        conn.commit()
        print(f"Saved/Updated {updated_count} charts to database.")
        
        # Try to fill arcaea_id from user_scores.db
        from repositories.song_repository import fill_missing_arcaea_ids_from_scores
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

def get_creds(cancellation_context=None, interactive=True):
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
                    
                    # Read client_secret from client_secret.json (canonical source)
                    try:
                        with open(secret_filepath, 'r') as f:
                            secret_data = json.load(f)
                        installed = secret_data.get('installed', secret_data.get('web', {}))
                        token_data['client_secret'] = installed.get('client_secret', '')
                    except Exception:
                        token_data['client_secret'] = ''
                    
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
            print(f"Token refresh failed: {e}")
            # Clear the expired/revoked credentials so the app doesn't
            # keep retrying with a dead token on every startup.
            _clear_google_credentials(connections_filepath)
            creds = None
    
    if not creds or not creds.valid:
        if not interactive:
            return None

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

def _clear_google_credentials(connections_filepath):
    """Clear expired/revoked Google credentials from account_connections.json and keyring.
    
    Called when token refresh fails (e.g. invalid_grant) to prevent the app from
    repeatedly attempting to use a dead token on every startup.
    Mirrors the behavior of SettingsHandler.disconnectGoogleSheet() by removing
    the entire google_sheet section and keyring tokens.
    """
    print("[GoogleAuth] Clearing expired credentials...")
    try:
        # Remove tokens from keyring
        try:
            keyring.delete_password('ArcaeaNap', 'google_token')
        except Exception:
            pass
        try:
            keyring.delete_password('ArcaeaNap', 'google_refresh_token')
        except Exception:
            pass
        
        # Remove entire google_sheet section from account_connections.json
        # (same as manual disconnect — clears bound sheet info as well)
        if os.path.exists(connections_filepath):
            try:
                with open(connections_filepath, 'r', encoding='utf-8') as f:
                    connections = json.load(f)
                if 'google_sheet' in connections:
                    del connections['google_sheet']
                with open(connections_filepath, 'w', encoding='utf-8') as f:
                    json.dump(connections, f, ensure_ascii=False, indent=2)
                print("[GoogleAuth] Expired credentials cleared.")
            except Exception as e:
                print(f"[GoogleAuth] Error updating connections file: {e}")
    except Exception as e:
        print(f"[GoogleAuth] Error clearing credentials: {e}")

def _save_google_credentials(creds, connections_filepath):
    """Save Google credentials to account_connections.json."""
    print("[GoogleAuth] Saving credentials...")
    try:
        # Extract user email using Google API Client
        user_email = ''
        try:
            print("[GoogleAuth] Fetching user info...")
            # Set a timeout for this discovery build/execute to prevent hanging
            socket.setdefaulttimeout(10) 
            user_info_service = build('oauth2', 'v2', credentials=creds)
            user_info = user_info_service.userinfo().get().execute()
            user_email = user_info.get('email', '')
            print(f"[GoogleAuth] User email: {user_email}")
        except Exception as e:
            print(f"[GoogleAuth] Error extracting user email (non-critical): {e}")
        finally:
             socket.setdefaulttimeout(None) # Reset timeout
        
        # Get token info
        token_info = json.loads(creds.to_json())
        
        # Save sensitive data to keyring
        print("[GoogleAuth] Saving to keyring...")
        if 'token' in token_info:
            try: keyring.set_password('ArcaeaNap', 'google_token', token_info['token'])
            except Exception as e: print(f"[GoogleAuth] Keyring error (token): {e}")
            token_info['token'] = ''
        if 'refresh_token' in token_info:
            try: keyring.set_password('ArcaeaNap', 'google_refresh_token', token_info['refresh_token'])
            except Exception as e: print(f"[GoogleAuth] Keyring error (refresh_token): {e}")
            token_info['refresh_token'] = ''
        # client_secret is available in client_secret.json; just blank it from token_info
        if 'client_secret' in token_info:
            token_info['client_secret'] = ''
        
        # Load existing connections or create new
        connections = {}
        if os.path.exists(connections_filepath):
            try:
                with open(connections_filepath, 'r', encoding='utf-8') as f:
                    connections = json.load(f)
            except Exception:
                pass
        
        # Update google_sheet section (merge to preserve bound_sheet_id/name)
        import time
        gs_info = connections.get('google_sheet', {})
        gs_info.update({
            'connected': True,
            'connected_at': int(time.time()),
            'user_email': user_email,
            'token': token_info
        })
        connections['google_sheet'] = gs_info
        
        print(f"[GoogleAuth] Writing to {connections_filepath}...")
        with open(connections_filepath, 'w', encoding='utf-8') as f:
            json.dump(connections, f, ensure_ascii=False, indent=2)
        print("[GoogleAuth] Credentials saved successfully.")
        
    except Exception as e:
        print(f"Error saving Google credentials: {e}")

class CancellationContext:
    def __init__(self):
        self._cancel_event = threading.Event()
        self._server = None
        self._shutdown_started = False
        
    def cancel(self):
        """Signal cancellation and shutdown the server if running."""
        print("[CancellationContext] Cancel requested")
        self._cancel_event.set()
        if self._server and not self._shutdown_started:
            self._shutdown_started = True

            def _shutdown_server():
                try:
                    print("[CancellationContext] Shutting down server...")
                    self._server.shutdown()
                    print("[CancellationContext] Server shutdown complete.")
                except Exception as e:
                    print(f"Error shutting down server: {e}")
                try:
                    self._server.server_close()
                except Exception as e:
                    print(f"Error closing server socket: {e}")

            shutdown_thread = threading.Thread(target=_shutdown_server, daemon=True)
            shutdown_thread.start()

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
    state = {'code': None, 'error': None}
    
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
            state['error'] = query['error'][0]
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
    print("[OAuth] Starting local server...")
    server_thread = threading.Thread(target=server.serve_forever)
    server_thread.daemon = True
    server_thread.start()
    
    # Main thread waits for code, error, or cancellation
    try:
        while state['code'] is None and state['error'] is None:
            if cancellation_context and cancellation_context.is_cancelled():
                print("OAuth flow cancelled by user.")
                # Server shutdown handles cleanup via cancellation_context.cancel() or below
                return None
            time.sleep(0.1)
    except KeyboardInterrupt:
        if cancellation_context:
            cancellation_context.cancel()
        return None
    finally:
        # Ensure server is shut down
        print("[OAuth] Stopping local server...")
        try:
             # Use a separate thread to shutdown to avoid stalling main thread if it blocks
            def _shutdown():
                 try: server.shutdown()
                 except: pass
                 try: server.server_close()
                 except: pass
            
            t = threading.Thread(target=_shutdown, daemon=True)
            t.start()
            t.join(timeout=2.0) # Wait max 2 seconds for shutdown
            if t.is_alive():
                 print("[OAuth] Server shutdown timed out (continuing).")
        except Exception as e:
            print(f"[OAuth] Server cleanup error: {e}")

        # server_thread.join(timeout=1.0) # We don't necessarily need to join it if we don't care

    if state['error']:
        print(f"[OAuth] Authentication failed from browser: {state['error']}")
        return None

    if state['code']:
        print("[OAuth] Code received, fetching token...")
        
        # Check cancellation before fetching token
        if cancellation_context and cancellation_context.is_cancelled():
            return None
            
        try:
            # Set timeout for token fetch
            socket.setdefaulttimeout(15) 
            flow.fetch_token(code=state['code'])
            print("[OAuth] Token fetched successfully.")
            return flow.credentials
        except Exception as e:
             print(f"[OAuth] Error fetching token: {e}")
             return None
        finally:
             socket.setdefaulttimeout(None)
             
    print("[OAuth] No code received.")
    return None

if __name__ == "__main__":
    open_sheet()