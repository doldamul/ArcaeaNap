import sqlite3
import os
from configuration import config

SONGS_DB_NAME = 'songs.db'

def get_db_path():
    return os.path.join(config['general']['cache_path'], SONGS_DB_NAME)

def get_connection():
    db_path = get_db_path()
    conn = sqlite3.connect(db_path)
    # Enable foreign keys
    conn.execute("PRAGMA foreign_keys = ON")
    return conn

def init_songs_db():
    conn = get_connection()
    cursor = conn.cursor()
    
    # Table: songs
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS songs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT UNIQUE,
            artist TEXT,
            length INTEGER,
            bpm TEXT,
            arcaea_id TEXT
        )
    ''')
    
    # Table: charts
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS charts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            song_id INTEGER,
            difficulty INTEGER,
            level TEXT,
            bp REAL,
            perceived_bp REAL,
            s_bp REAL,
            note_count INTEGER,
            cut_200 INTEGER,
            ignore_chart INTEGER,
            skill_issues INTEGER,
            UNIQUE(song_id, difficulty),
            FOREIGN KEY(song_id) REFERENCES songs(id)
        )
    ''')
    
    # Simple migration for existing DBs
    cursor.execute("PRAGMA table_info(songs)")
    columns = [info[1] for info in cursor.fetchall()]
    if 'bpm' not in columns:
        cursor.execute("ALTER TABLE songs ADD COLUMN bpm TEXT")

    cursor.execute("PRAGMA table_info(charts)")
    columns = [info[1] for info in cursor.fetchall()]
    
    if 'level' not in columns:
        cursor.execute("ALTER TABLE charts ADD COLUMN level TEXT")
    if 'ignore_chart' not in columns:
        cursor.execute("ALTER TABLE charts ADD COLUMN ignore_chart INTEGER")
    if 'skill_issues' not in columns:
        cursor.execute("ALTER TABLE charts ADD COLUMN skill_issues INTEGER")
    
    conn.commit()
    conn.close()

# Maps Arcaea Online 'song_id' to the Canonical Title in songs.db
# Derived from previous name_exception logic
AO_ID_MAP = {
    'quon': 'Quon(Lanota)',
    'quonwacca': 'Quon(WACCA)', 
    'genesis': 'Genesis(Arcaea)',
    'genesischunithm': 'Genesis(CHUNITHM)',
    'ii': '͟͝͞Ⅱ́̕',
    'mu': 'μ', 
    'neokosmo': 'nέo κósmo',
}

# Standardizes Title differences between Wiki and DB
# (WikiTitle, WikiArtist) -> DBTitle
WIKI_EXCEPTION_MAP = {
    ('Quon', 'Feryquitous'): 'Quon(Lanota)',
    ('Quon', 'DJ Noriken'): 'Quon(WACCA)',
    ('Genesis', 'Iris'): 'Genesis(Arcaea)',
    ('Genesis', 'Morrigan feat.Lily'): 'Genesis(CHUNITHM)',
}

# Maps Simplified Titles (Sheet) -> Official Titles (Wiki/DB)
TITLE_ALIAS_MAP = {
    'II': '͟͝͞Ⅱ́̕',
    'Anokumene': 'Anökumene',
    'neo kosmo': 'nέo κósmo',
    'Alice a la mode': 'Alice à la mode',
    'April Showers': 'April showers',
}

def resolve_song_id(cursor, title):
    """
    Finds the song_id for a given title (Case-Insensitive), checking Alias Map.
    """
    # Check Alias Map
    if title in TITLE_ALIAS_MAP:
        title = TITLE_ALIAS_MAP[title]
        
    return resolve_song_id_with_artist(cursor, title, None)

def resolve_song_id_with_artist(cursor, title, artist=None):
    """
    Finds song_id, handling specific Wiki exceptions using Artist.
    """
    # 1. Check Exception Map
    if artist:
        mapped_title = WIKI_EXCEPTION_MAP.get((title, artist))
        if mapped_title:
            title = mapped_title
            
    # 2. Try exact match
    cursor.execute('SELECT id FROM songs WHERE title = ?', (title,))
    result = cursor.fetchone()
    if result:
        return result[0]
        
    # 3. Try case-insensitive match
    cursor.execute('SELECT id, title FROM songs WHERE lower(title) = lower(?)', (title,))
    result = cursor.fetchone()
    
    if result:
        return result[0]
    else:
        cursor.execute('INSERT INTO songs (title) VALUES (?)', (title,))
        return cursor.lastrowid

def update_song_metadata(cursor, song_id, artist, length, bpm=None):
    """
    Updates artist, length, and bpm for a given song_id.
    """
    cursor.execute('''
        UPDATE songs 
        SET artist = ?, length = ?, bpm = ?
        WHERE id = ?
    ''', (artist, length, bpm, song_id))

def resolve_song_id_for_ao(cursor, ao_id, ao_title):
    target_title = AO_ID_MAP.get(ao_id, ao_title)
    cursor.execute('SELECT id, arcaea_id FROM songs WHERE title = ?', (target_title,))
    result = cursor.fetchone()
    
    if result:
        db_id, existing_ao_id = result
        if not existing_ao_id:
            cursor.execute('UPDATE songs SET arcaea_id = ? WHERE id = ?', (ao_id, db_id))
        return db_id
    else:
        cursor.execute('INSERT INTO songs (title, arcaea_id) VALUES (?, ?)', (target_title, ao_id))
        return cursor.lastrowid

def fill_missing_arcaea_ids_from_scores():
    """
    Backfills missing arcaea_id in songs.db using data from user_scores.db.
    """
    scores_db_path = os.path.join(config['general']['cache_path'], 'user_scores.db')
    if not os.path.exists(scores_db_path):
        return

    songs_conn = get_connection()
    songs_cursor = songs_conn.cursor()
    
    # Get songs with missing arcaea_id
    songs_cursor.execute("SELECT id, title FROM songs WHERE arcaea_id IS NULL OR arcaea_id = ''")
    missing_songs = songs_cursor.fetchall()
    
    if not missing_songs:
        songs_conn.close()
        return

    try:
        updated_count = 0
        with sqlite3.connect(scores_db_path) as scores_conn:
            scores_cursor = scores_conn.cursor()
            
            for song_id, title in missing_songs:
                # 1. Try exact title match in user_scores.db
                scores_cursor.execute("SELECT arcaea_id FROM scores WHERE title = ? LIMIT 1", (title,))
                row = scores_cursor.fetchone()
                
                arcaea_id = None
                if row:
                    arcaea_id = row[0]
                else:
                    # 2. Try Reverse AO_ID_MAP Lookup
                    # Check if current song title is a canonical title in the map
                    # If so, the key is the candidate arcaea_id
                    for map_id, map_title in AO_ID_MAP.items():
                        if map_title == title:
                            # Verify if this ID exists in user_scores.db
                            scores_cursor.execute("SELECT arcaea_id FROM scores WHERE arcaea_id = ? LIMIT 1", (map_id,))
                            if scores_cursor.fetchone():
                                arcaea_id = map_id
                            break
                            
                if arcaea_id:
                    songs_cursor.execute("UPDATE songs SET arcaea_id = ? WHERE id = ?", (arcaea_id, song_id))
                    updated_count += 1
        
        songs_conn.commit()
        if updated_count > 0:
            print(f"Backfilled arcaea_id for {updated_count} songs from user_scores.db")
            
    except Exception as e:
        print(f"Error filling arcaea_ids: {e}")
    finally:
        songs_conn.close()

def play_stats_difficulty(difficulty: int):
    """
    Calculates Play Count and Play Time for a specific difficulty.
    
    Args:
        difficulty: Difficulty code (0=PST, 1=PRS, 2=FTR, 3=BYD, 4=ETR)
    
    Returns:
        tuple: (play_count, play_time_seconds)
    """
    scores_db_path = os.path.join(config['general']['cache_path'], 'user_scores.db')
    songs_db_path = get_db_path()

    if not os.path.exists(scores_db_path) or not os.path.exists(songs_db_path):
        return 0, 0

    conn = sqlite3.connect(scores_db_path)
    try:
        # Attach songs.db
        conn.execute(f"ATTACH DATABASE ? AS songs_db", (songs_db_path,))
        
        cursor = conn.cursor()
        
        # Use play_count table for stats
        # Join with songs AND charts to ensure validity
        # If song length is null, use 140(2min 20sec) as default
        query = """
            SELECT 
                SUM(pc.yearly_play_count),
                SUM(pc.yearly_play_count * IFNULL(s.length, 140))
            FROM play_count pc
            JOIN songs_db.songs s ON pc.arcaea_id = s.arcaea_id
            JOIN songs_db.charts c ON s.id = c.song_id AND pc.difficulty = c.difficulty
            WHERE pc.difficulty = ?
        """
        
        cursor.execute(query, (difficulty,))
        result = cursor.fetchone()
        
        if result:
            total_count = result[0] if result[0] is not None else 0
            total_time = result[1] if result[1] is not None else 0
            return int(total_count), int(total_time)
        else:
            return 0, 0
            
    except Exception as e:
        print(f"Error calculating stats for difficulty {difficulty}: {e}")
        return 0, 0
    finally:
        conn.close()


def play_stats_total():
    """
    Calculates Total Play Count and Total Play Time by summing all difficulties.
    
    Returns:
        tuple: (total_play_count, total_play_time_seconds)
    """
    total_count = 0
    total_time = 0
    
    # All difficulty codes: 0=PST, 1=PRS, 2=FTR, 3=BYD, 4=ETR
    for diff in [0, 1, 2, 3, 4]:
        count, time = play_stats_difficulty(diff)
        total_count += count
        total_time += time
    
    return total_count, total_time

def calculate_rank(score: int) -> str:
    """
    Calculate grade rank from score.
    """
    if score is None:
        return ""
    if score >= 10000000:
        return "PM"
    elif score >= 9900000:
        return "EX+"
    elif score >= 9800000:
        return "EX"
    elif score >= 9500000:
        return "AA"
    elif score >= 9200000:
        return "A"
    elif score >= 8900000:
        return "B"
    elif score >= 8600000:
        return "C"
    else:
        return "D"


def get_all_songs_with_charts():
    """
    Fetches all songs and their charts from songs.db.
    Returns:
        dict: {arcaea_id: {
            'title': str, 'artist': str, 'length': int, 'bpm': str,
            'charts': {difficulty: {level, bp, s_bp, perceived_bp, note_count, ignore_chart, skill_issues}}
        }}
    """
    songs_db_path = get_db_path()
    if not os.path.exists(songs_db_path):
        return {}

    conn = sqlite3.connect(songs_db_path)
    try:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT s.arcaea_id, s.title, s.artist, s.length, s.bpm,
                   c.difficulty, c.level, c.bp, c.s_bp, c.perceived_bp, c.note_count,
                   c.ignore_chart, c.skill_issues, s.id
            FROM songs s
            LEFT JOIN charts c ON s.id = c.song_id
            WHERE s.arcaea_id IS NOT NULL AND s.arcaea_id != ''
        """)
        
        result = {}
        for row in cursor.fetchall():
            arcaea_id = row[0]
            song_id = row[13]
            
            if song_id not in result:
                result[song_id] = {
                    'arcaea_id': arcaea_id,
                    'title': row[1] or 'Unknown',
                    'artist': row[2] or 'Unknown',
                    'length': row[3] or 0,
                    'bpm': row[4] or '',
                    'charts': {}
                }
            
            if row[5] is not None:  # difficulty exists
                result[song_id]['charts'][row[5]] = {
                    'level': row[6] or '',
                    'bp': row[7] or 0.0,
                    's_bp': row[8] or 0.0,
                    'perceived_bp': row[9] or 0.0,
                    'note_count': row[10] or 0,
                    'ignore_chart': bool(row[11]),
                    'skill_issues': bool(row[12]),
                }
        
        return result
    except Exception as e:
        print(f"Error fetching songs with charts: {e}")
        return {}
    finally:
        conn.close()


def get_best_scores_per_chart():
    """
    For each (arcaea_id, difficulty), fetches the record with the highest score.
    Returns:
        dict: {(arcaea_id, difficulty): {
            'score': int, 'shiny_perfect': int, 'perfect': int, 'near': int, 'miss': int,
            'best_clear_type': int, 'time_played': int, 'score_below_max': int
        }}
    """
    scores_db_path = os.path.join(config['general']['cache_path'], 'user_scores.db')
    if not os.path.exists(scores_db_path):
        return {}

    conn = sqlite3.connect(scores_db_path)
    try:
        cursor = conn.cursor()
        # Get best score per chart using window function
        cursor.execute("""
            WITH ranked AS (
                SELECT 
                    arcaea_id, difficulty, score, 
                    shiny_perfect_count, perfect_count, near_count, miss_count,
                    best_clear_type, time_played, score_below_max,
                    ROW_NUMBER() OVER (PARTITION BY arcaea_id, difficulty ORDER BY score DESC) as rn
                FROM scores
            )
            SELECT arcaea_id, difficulty, score, 
                   shiny_perfect_count, perfect_count, near_count, miss_count,
                   best_clear_type, time_played, score_below_max
            FROM ranked WHERE rn = 1
        """)
        
        result = {}
        for row in cursor.fetchall():
            key = (row[0], row[1])
            result[key] = {
                'score': row[2] or 0,
                'shiny_perfect': row[3] or 0,
                'perfect': row[4] or 0,
                'near': row[5] or 0,
                'miss': row[6] or 0,
                'best_clear_type': row[7] or 0,
                'time_played': row[8] or 0,
                'score_below_max': row[9] or 0,
            }
        
        return result
    except Exception as e:
        print(f"Error fetching best scores: {e}")
        return {}
    finally:
        conn.close()


def get_play_counts():
    """
    Fetches total play count for each (arcaea_id, difficulty).
    Only includes play counts for valid charts that exist in songs.db.
    Returns:
        dict: {(arcaea_id, difficulty): total_play_count}
    """
    scores_db_path = os.path.join(config['general']['cache_path'], 'user_scores.db')
    songs_db_path = get_db_path()
    
    if not os.path.exists(scores_db_path) or not os.path.exists(songs_db_path):
        return {}

    conn = sqlite3.connect(scores_db_path)
    try:
        # Attach songs.db
        conn.execute(f"ATTACH DATABASE ? AS songs_db", (songs_db_path,))
        
        cursor = conn.cursor()
        # Sum all yearly_play_count for each chart, but only for valid charts
        # This matches the logic in calculate_user_stats()
        cursor.execute("""
            SELECT pc.arcaea_id, pc.difficulty, SUM(pc.yearly_play_count) as total
            FROM play_count pc
            JOIN songs_db.songs s ON pc.arcaea_id = s.arcaea_id
            JOIN songs_db.charts c ON s.id = c.song_id AND pc.difficulty = c.difficulty
            GROUP BY pc.arcaea_id, pc.difficulty
        """)
        
        result = {}
        for row in cursor.fetchall():
            key = (row[0], row[1])
            result[key] = row[2] or 0
        
        return result
    except Exception as e:
        print(f"Error fetching play counts: {e}")
        return {}
    finally:
        conn.close()


def get_this_year_play_counts():
    """
    Fetches play count for the current year for each (arcaea_id, difficulty).
    Returns:
        dict: {(arcaea_id, difficulty): this_year_play_count}
    """
    from datetime import datetime
    
    scores_db_path = os.path.join(config['general']['cache_path'], 'user_scores.db')
    if not os.path.exists(scores_db_path):
        return {}

    conn = sqlite3.connect(scores_db_path)
    try:
        cursor = conn.cursor()
        current_year = datetime.now().year
        
        cursor.execute("""
            SELECT arcaea_id, difficulty, yearly_play_count
            FROM play_count
            WHERE year = ?
        """, (current_year,))
        
        result = {}
        for row in cursor.fetchall():
            key = (row[0], row[1])
            result[key] = row[2] or 0
        
        return result
    except Exception as e:
        print(f"Error fetching this year play counts: {e}")
        return {}
    finally:
        conn.close()


# Difficulty code (string) -> int for play_count table. Matches ui.py DIFFICULTY_NAMES/COLORS.
DIFFICULTY_CODE_TO_INT = {'pst': 0, 'prs': 1, 'ftr': 2, 'byd': 3, 'etr': 4}
DIFFICULTY_NAMES = {0: 'PST', 1: 'PRS', 2: 'FTR', 3: 'BYD', 4: 'ETR'}
DIFFICULTY_COLORS = {0: '#00A0E9', 1: '#50C050', 2: '#A060FF', 3: '#E04040', 4: '#808080'}


def _allowed_difficulties():
    """Return set of difficulty integers to include based on config difficulty_filter."""
    raw = config['profile']['difficulty_filter']
    if raw == 'all':
        return {0, 1, 2, 3, 4}
    if not raw:
        return set()
    return {DIFFICULTY_CODE_TO_INT.get(p.strip().lower()) for p in raw.split(',') if p.strip().lower() in DIFFICULTY_CODE_TO_INT}


def get_top_10_most_played():
    """
    Returns the top 10 most played songs or charts based on config:
    - grouping_criteria: 'song' (aggregate by song) or 'chart' (per difficulty)
    - difficulty_filter: 'all' or comma-separated codes (e.g. 'pst,prs,ftr') to include
    - most_played_scope: 'total' (all years) or 'this_year'

    Returns:
        list of dict: by song: [{'title', 'artist', 'playCount', 'arcaeaId', 'colorCode'}, ...]
                      by chart: same + 'difficulty' (int), 'difficultyName', 'difficultyColor'
    """
    scores_db_path = os.path.join(config['general']['cache_path'], 'user_scores.db')
    songs_db_path = get_db_path()
    if not os.path.exists(scores_db_path) or not os.path.exists(songs_db_path):
        return []

    scope = config['profile']['most_played_scope']
    grouping = config['profile']['grouping_criteria']
    allowed = _allowed_difficulties()

    if scope == 'this_year':
        raw_counts = get_this_year_play_counts()
    else:
        raw_counts = get_play_counts()

    # Filter by allowed difficulties; key is (arcaea_id, difficulty), difficulty may be int
    filtered = {}
    for (aid, diff), count in raw_counts.items():
        d = int(diff) if diff is not None else 0
        if d in allowed and count:
            filtered[(aid, d)] = count

    if not filtered:
        return []

    if grouping == 'chart':
        # Top 10 charts by play count
        sorted_charts = sorted(filtered.items(), key=lambda x: -x[1])[:10]
        conn = sqlite3.connect(songs_db_path)
        try:
            cursor = conn.cursor()
            results = []
            for (arcaea_id, difficulty), play_count in sorted_charts:
                cursor.execute("SELECT title, artist FROM songs WHERE arcaea_id = ?", (arcaea_id,))
                row = cursor.fetchone()
                title = row[0] if row and row[0] else 'Unknown Title'
                artist = row[1] if row and row[1] else 'Unknown Artist'
                results.append({
                    'title': title,
                    'artist': artist,
                    'playCount': play_count,
                    'arcaeaId': arcaea_id or '',
                    'colorCode': '#FFFFFF',
                    'difficulty': difficulty,
                    'difficultyName': DIFFICULTY_NAMES.get(difficulty, ''),
                    'difficultyColor': DIFFICULTY_COLORS.get(difficulty, '#888'),
                })
            return results
        except Exception as e:
            print(f"Error fetching top 10 (chart): {e}")
            return []
        finally:
            conn.close()

    # grouping == 'song': aggregate by arcaea_id
    by_song = {}
    for (aid, _), count in filtered.items():
        by_song[aid] = by_song.get(aid, 0) + count
    sorted_songs = sorted(by_song.items(), key=lambda x: -x[1])[:10]
    if not sorted_songs:
        return []

    conn = sqlite3.connect(songs_db_path)
    try:
        cursor = conn.cursor()
        results = []
        for arcaea_id, play_count in sorted_songs:
            cursor.execute("SELECT title, artist FROM songs WHERE arcaea_id = ?", (arcaea_id,))
            row = cursor.fetchone()
            title = row[0] if row and row[0] else 'Unknown Title'
            artist = row[1] if row and row[1] else 'Unknown Artist'
            results.append({
                'title': title,
                'artist': artist,
                'playCount': play_count,
                'arcaeaId': arcaea_id or '',
                'colorCode': '#FFFFFF',
                'difficulty': -1,
                'difficultyName': '',
                'difficultyColor': '#888',
            })
        return results
    except Exception as e:
        print(f"Error fetching top 10 (song): {e}")
        return []
    finally:
        conn.close()


def get_pin_updated_dates():
    """
    Fetches the last updated timestamp for each difficulty from the 'pin' table.
    Returns:
        dict: {difficulty (int): timestamp (int)}
         - Timestamp is in milliseconds (Unix).
         - Returns empty dict if no data found.
    """
    scores_db_path = os.path.join(config['general']['cache_path'], 'user_scores.db')
    if not os.path.exists(scores_db_path):
        return {}

    conn = sqlite3.connect(scores_db_path)
    try:
        cursor = conn.cursor()
        
        # Check if 'pin' table exists just in case
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='pin'")
        if not cursor.fetchone():
            return {}
        
        query = """
            SELECT p.difficulty, p.updated_at
            FROM pin p
        """
        cursor.execute(query)
        
        result = {}
        for row in cursor.fetchall():
            diff = str(row[0])  # Convert to string for QML compatibility
            timestamp = row[1]
            result[diff] = timestamp
            
        return result
            
    except Exception as e:
        print(f"Error fetching pin dates: {e}")
        return {}
    finally:
        conn.close()


def get_song_title(arcaea_id):
    """
    Fetches the song title given an arcaea_id.
    """
    songs_db_path = get_db_path()
    if not os.path.exists(songs_db_path):
        return None
    
    conn = sqlite3.connect(songs_db_path)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT title FROM songs WHERE arcaea_id = ?", (arcaea_id,))
        row = cursor.fetchone()
        return row[0] if row else None
    except Exception as e:
        print(f"Error fetching song title: {e}")
        return None
    finally:
        conn.close()
