"""
songs.db 접근 Repository.

songs/charts 테이블의 스키마 관리, 레코드 CRUD, 타이틀 해석 기능을 제공한다.
"""
import sqlite3
import os
from configuration import config

# === 상수 ===

SONGS_DB_NAME = 'songs.db'

# Maps Arcaea Online 'song_id' to the Canonical Title in songs.db
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


# === DB 연결 ===

def get_db_path():
    """songs.db의 절대 경로를 반환한다."""
    return os.path.join(config['general']['cache_path'], SONGS_DB_NAME)


def get_connection():
    """songs.db에 대한 SQLite 연결을 반환한다."""
    db_path = get_db_path()
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


# === 스키마 관리 ===

def init_songs_db():
    """songs/charts 테이블을 생성하고 필요 시 마이그레이션을 수행한다."""
    conn = get_connection()
    cursor = conn.cursor()

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


# === 타이틀 해석 ===

def resolve_song_id(cursor, title):
    """
    Finds the song_id for a given title (Case-Insensitive), checking Alias Map.
    """
    if title in TITLE_ALIAS_MAP:
        title = TITLE_ALIAS_MAP[title]

    return resolve_song_id_with_artist(cursor, title, None)


def resolve_song_id_with_artist(cursor, title, artist=None):
    """
    Finds song_id, handling specific Wiki exceptions using Artist.
    """
    if artist:
        mapped_title = WIKI_EXCEPTION_MAP.get((title, artist))
        if mapped_title:
            title = mapped_title

    cursor.execute('SELECT id FROM songs WHERE title = ?', (title,))
    result = cursor.fetchone()
    if result:
        return result[0]

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
    """
    Arcaea Online ID로 song_id를 조회하고, 없으면 새 레코드를 생성한다.
    arcaea_id가 비어있는 기존 레코드는 자동으로 갱신한다.
    """
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


# === 데이터 보완 ===

def fill_missing_arcaea_ids_from_scores():
    """
    Backfills missing arcaea_id in songs.db using data from user_scores.db.
    """
    scores_db_path = os.path.join(config['general']['cache_path'], 'user_scores.db')
    if not os.path.exists(scores_db_path):
        return

    songs_conn = get_connection()
    songs_cursor = songs_conn.cursor()

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
                scores_cursor.execute("SELECT arcaea_id FROM scores WHERE title = ? LIMIT 1", (title,))
                row = scores_cursor.fetchone()

                arcaea_id = None
                if row:
                    arcaea_id = row[0]
                else:
                    for map_id, map_title in AO_ID_MAP.items():
                        if map_title == title:
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


# === 조회 ===

def get_all_songs_with_charts():
    """
    Fetches all songs and their charts from songs.db.
    Returns:
        dict: {song_db_id: {
            'arcaea_id': str, 'title': str, 'artist': str, 'length': int, 'bpm': str,
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

            if row[5] is not None:
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
