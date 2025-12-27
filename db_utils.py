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
            difficulty TEXT,
            level TEXT,
            bp REAL,
            perceived_bp REAL,
            s_bp REAL,
            note_count INTEGER,
            cut_200 INTEGER,
            ignore_chart INTEGER,
            skill_issues INTEGER,
            contain_slowspeed INTEGER,
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
    if 'contain_slowspeed' not in columns:
        cursor.execute("ALTER TABLE charts ADD COLUMN contain_slowspeed INTEGER")
    
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
