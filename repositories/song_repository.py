"""
songs.db 접근 Repository.

songs/charts 테이블의 스키마 관리, 레코드 CRUD, 타이틀 해석 기능을 제공한다.
"""
import sqlite3
import os
from utils.configuration import config, get_cache_dir

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
    return os.path.join(get_cache_dir(), SONGS_DB_NAME)


def get_connection():
    """songs.db에 대한 SQLite 연결을 반환한다."""
    db_path = get_db_path()
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


# === 스키마 관리 ===

def init_songs_db():
    """songs/charts 테이블을 생성하고 필요 컬럼을 보완한다."""
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute('''
        CREATE TABLE IF NOT EXISTS songs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            canonical_title TEXT UNIQUE,
            title_en TEXT,
            title_jp TEXT,
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
            hard_bpm INTEGER,
            UNIQUE(song_id, difficulty),
            FOREIGN KEY(song_id) REFERENCES songs(id)
        )
    ''')

    # Simple migration for existing DBs
    cursor.execute("PRAGMA table_info(songs)")
    columns = [info[1] for info in cursor.fetchall()]
    if 'bpm' not in columns:
        cursor.execute("ALTER TABLE songs ADD COLUMN bpm TEXT")
    if 'title_en' not in columns:
        cursor.execute("ALTER TABLE songs ADD COLUMN title_en TEXT")
    if 'title_jp' not in columns:
        cursor.execute("ALTER TABLE songs ADD COLUMN title_jp TEXT")

    cursor.execute("PRAGMA table_info(charts)")
    columns = [info[1] for info in cursor.fetchall()]

    if 'level' not in columns:
        cursor.execute("ALTER TABLE charts ADD COLUMN level TEXT")
    if 'ignore_chart' not in columns:
        cursor.execute("ALTER TABLE charts ADD COLUMN ignore_chart INTEGER")
    if 'skill_issues' not in columns:
        cursor.execute("ALTER TABLE charts ADD COLUMN skill_issues INTEGER")
    if 'hard_bpm' not in columns:
        cursor.execute("ALTER TABLE charts ADD COLUMN hard_bpm INTEGER")

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

    cursor.execute('SELECT id FROM songs WHERE canonical_title = ?', (title,))
    result = cursor.fetchone()
    if result:
        return result[0]

    cursor.execute('SELECT id FROM songs WHERE lower(canonical_title) = lower(?)', (title,))
    result = cursor.fetchone()

    if result:
        return result[0]
    else:
        cursor.execute('INSERT INTO songs (canonical_title) VALUES (?)', (title,))
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
    cursor.execute('SELECT id, arcaea_id FROM songs WHERE canonical_title = ?', (target_title,))
    result = cursor.fetchone()

    if result:
        db_id, existing_ao_id = result
        if not existing_ao_id:
            cursor.execute('UPDATE songs SET arcaea_id = ? WHERE id = ?', (ao_id, db_id))
        return db_id
    else:
        cursor.execute('INSERT INTO songs (canonical_title, arcaea_id) VALUES (?, ?)', (target_title, ao_id))
        return cursor.lastrowid


def update_song_titles_from_ao(cursor, song_id, title_en, title_jp, artist):
    """AO 데이터를 이용해 songs.db의 title_en/title_jp/artist 공란 필드를 채운다."""
    cursor.execute(
        'SELECT title_en, title_jp, artist FROM songs WHERE id = ?',
        (song_id,)
    )
    row = cursor.fetchone()
    if not row:
        return

    existing_title_en, existing_title_jp, existing_artist = row
    updates = []
    values = []

    if (not existing_title_en) and title_en:
        updates.append('title_en = ?')
        values.append(title_en)
    if (not existing_title_jp) and title_jp:
        updates.append('title_jp = ?')
        values.append(title_jp)
    if (not existing_artist) and artist:
        updates.append('artist = ?')
        values.append(artist)

    if not updates:
        return

    values.append(song_id)
    cursor.execute(f"UPDATE songs SET {', '.join(updates)} WHERE id = ?", values)


# === 데이터 보완 ===

def fill_missing_arcaea_ids_from_scores():
    """
    Backfills missing arcaea_id in songs.db using data from user_scores.db.
    """
    scores_db_path = os.path.join(get_cache_dir(), 'user_scores.db')
    if not os.path.exists(scores_db_path):
        return

    songs_conn = get_connection()
    songs_cursor = songs_conn.cursor()

    songs_cursor.execute("SELECT id, canonical_title FROM songs WHERE arcaea_id IS NULL OR arcaea_id = ''")
    missing_songs = songs_cursor.fetchall()

    if not missing_songs:
        songs_conn.close()
        return

    try:
        updated_count = 0
        with sqlite3.connect(scores_db_path) as scores_conn:
            scores_cursor = scores_conn.cursor()

            for song_id, canonical_title in missing_songs:
                scores_cursor.execute("SELECT arcaea_id FROM scores WHERE title_en = ? LIMIT 1", (canonical_title,))
                row = scores_cursor.fetchone()

                arcaea_id = None
                if row:
                    arcaea_id = row[0]
                else:
                    for map_id, map_title in AO_ID_MAP.items():
                        if map_title == canonical_title:
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


def fill_song_titles_from_scores():
    """
    user_scores.db의 title_en/title_jp 데이터를 songs.db에 역으로 채운다.
    songs.db 재생성 후 호출하여 인게임 제목 데이터를 복원한다.
    """
    scores_db_path = os.path.join(get_cache_dir(), 'user_scores.db')
    if not os.path.exists(scores_db_path):
        return

    songs_conn = get_connection()
    songs_cursor = songs_conn.cursor()
    attached = False

    try:
        songs_cursor.execute("ATTACH DATABASE ? AS user_db", (scores_db_path,))
        attached = True

        songs_cursor.execute("""
            UPDATE songs
            SET title_en = COALESCE(
                    NULLIF(songs.title_en, ''),
                    (SELECT us.title_en
                     FROM user_db.scores us
                     JOIN charts c ON c.song_id = songs.id
                     WHERE us.arcaea_id = songs.arcaea_id
                       AND us.difficulty = c.difficulty
                       AND us.title_en IS NOT NULL AND us.title_en != ''
                     LIMIT 1)
                ),
                title_jp = COALESCE(
                    NULLIF(songs.title_jp, ''),
                    (SELECT us.title_jp
                     FROM user_db.scores us
                     JOIN charts c ON c.song_id = songs.id
                     WHERE us.arcaea_id = songs.arcaea_id
                       AND us.difficulty = c.difficulty
                       AND us.title_jp IS NOT NULL AND us.title_jp != ''
                     LIMIT 1)
                )
            WHERE songs.arcaea_id IS NOT NULL AND songs.arcaea_id != ''
        """)

        songs_conn.commit()

        restored_count = songs_cursor.execute(
            "SELECT COUNT(*) FROM songs WHERE (title_en IS NOT NULL AND title_en != '') OR (title_jp IS NOT NULL AND title_jp != '')"
        ).fetchone()[0]
        print(f"[fill_song_titles_from_scores] Restored title_en/title_jp for {restored_count} songs")

    except Exception as e:
        print(f"Error filling song titles from scores: {e}")
    finally:
        if attached:
            try:
                songs_cursor.execute("DETACH DATABASE user_db")
            except Exception:
                pass
        songs_conn.close()


# === 조회 ===

def get_all_songs_with_charts():
    """
    Fetches all songs and their charts from songs.db.
    Returns:
        dict: {song_db_id: {
            'arcaea_id': str, 'canonical_title': str, 'title_en': str, 'title_jp': str,
            'artist': str, 'length': int, 'bpm': str,
            'charts': {difficulty: {level, bp, s_bp, perceived_bp, note_count, ignore_chart, skill_issues, hard_bpm}}
        }}
    """
    songs_db_path = get_db_path()
    if not os.path.exists(songs_db_path):
        return {}

    conn = sqlite3.connect(songs_db_path)
    try:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT s.arcaea_id, s.canonical_title, s.title_en, s.title_jp, s.artist, s.length, s.bpm,
                   c.difficulty, c.level, c.bp, c.s_bp, c.perceived_bp, c.note_count,
                   c.ignore_chart, c.skill_issues, c.hard_bpm, s.id
            FROM songs s
            LEFT JOIN charts c ON s.id = c.song_id
            WHERE s.arcaea_id IS NOT NULL AND s.arcaea_id != ''
        """)

        result = {}
        for row in cursor.fetchall():
            arcaea_id = row[0]
            song_id = row[16]

            if song_id not in result:
                result[song_id] = {
                    'arcaea_id': arcaea_id,
                    'canonical_title': row[1] or 'Unknown',
                    'title_en': row[2] or '',
                    'title_jp': row[3] or '',
                    'artist': row[4] or 'Unknown',
                    'length': row[5] or 0,
                    'bpm': row[6] or '',
                    'charts': {}
                }

            if row[7] is not None:
                result[song_id]['charts'][row[7]] = {
                    'level': row[8] or '',
                    'bp': row[9] or 0.0,
                    's_bp': row[10] or 0.0,
                    'perceived_bp': row[11] or 0.0,
                    'note_count': row[12] or 0,
                    'ignore_chart': bool(row[13]),
                    'skill_issues': bool(row[14]),
                    'hard_bpm': bool(row[15]),
                }

        return result
    except Exception as e:
        print(f"Error fetching songs with charts: {e}")
        return {}
    finally:
        conn.close()


def get_song_title(arcaea_id, difficulty=None, song_title_language='en'):
    """
    Fetches display title for an arcaea_id. If difficulty is provided,
    resolves the exact song row via (arcaea_id, difficulty).
    song_title_language: 'en' or 'jp'
    """
    songs_db_path = get_db_path()
    if not os.path.exists(songs_db_path):
        return None

    conn = sqlite3.connect(songs_db_path)
    try:
        cursor = conn.cursor()
        lang = str(song_title_language or 'en').lower()
        if difficulty is not None:
            cursor.execute(
                "SELECT s.title_en, s.title_jp, s.canonical_title "
                "FROM songs s "
                "JOIN charts c ON c.song_id = s.id "
                "WHERE s.arcaea_id = ? AND c.difficulty = ? "
                "LIMIT 1",
                (arcaea_id, int(difficulty)),
            )
        else:
            cursor.execute(
                "SELECT title_en, title_jp, canonical_title FROM songs "
                "WHERE arcaea_id = ? "
                "ORDER BY CASE WHEN title_en IS NOT NULL AND title_en != '' THEN 0 ELSE 1 END "
                "LIMIT 1",
                (arcaea_id,),
            )
        row = cursor.fetchone()
        if not row:
            return None
        title_en, title_jp, canonical_title = row
        if lang == 'jp':
            return title_jp or title_en or canonical_title
        return title_en or title_jp or canonical_title
    except Exception as e:
        print(f"Error fetching song title: {e}")
        return None
    finally:
        conn.close()
