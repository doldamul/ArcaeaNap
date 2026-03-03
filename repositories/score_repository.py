"""
Repository classes for user_scores.db access.

Provides clean separation of DB queries from business logic.
"""
import sqlite3
import time
from dataclasses import dataclass
from typing import Optional


@dataclass
class ScoreRecord:
    """scores 테이블의 레코드"""
    id: int
    arcaea_id: str
    difficulty: int
    time_played: int
    score: Optional[int] = None
    shiny_perfect_count: Optional[int] = None
    perfect_count: Optional[int] = None
    near_count: Optional[int] = None
    miss_count: Optional[int] = None


class ScoreRepository:
    """user_scores.db의 scores 테이블 접근"""
    
    SCORES_SCHEMA = '''
        CREATE TABLE IF NOT EXISTS scores (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            arcaea_id TEXT,
            difficulty INTEGER,
            score INTEGER,
            shiny_perfect_count INTEGER,
            perfect_count INTEGER,
            near_count INTEGER,
            miss_count INTEGER,
            health INTEGER,
            modifier INTEGER,
            time_played INTEGER,
            clear_type INTEGER,
            best_clear_type INTEGER,
            title TEXT,
            artist TEXT,
            user_id INTEGER,
            yearly_play_index INTEGER,
            score_below_max INTEGER,
            UNIQUE(arcaea_id, difficulty, time_played)
        )
    '''
    
    PLAY_COUNT_SCHEMA = '''
        CREATE TABLE IF NOT EXISTS play_count (
            arcaea_id TEXT,
            difficulty INTEGER,
            year INTEGER,
            yearly_play_count INTEGER,
            PRIMARY KEY (arcaea_id, difficulty, year)
        )
    '''
    
    def ensure_tables(self, cursor: sqlite3.Cursor):
        """scores 및 play_count 테이블이 존재하는지 확인하고 없으면 생성"""
        cursor.execute(self.SCORES_SCHEMA)
        cursor.execute(self.PLAY_COUNT_SCHEMA)
    
    def score_exists(self, cursor: sqlite3.Cursor, 
                     arcaea_id: str, difficulty: int, time_played: int) -> bool:
        """해당 스코어가 이미 존재하는지 확인"""
        cursor.execute(
            'SELECT 1 FROM scores WHERE arcaea_id = ? AND difficulty = ? AND time_played = ?',
            (arcaea_id, difficulty, time_played)
        )
        return cursor.fetchone() is not None
    
    def insert_scores(self, cursor: sqlite3.Cursor, scores: list[tuple]):
        """스코어 레코드들을 일괄 삽입 (중복 무시)"""
        cursor.executemany('''
            INSERT OR IGNORE INTO scores 
            (arcaea_id, difficulty, score, shiny_perfect_count, perfect_count, near_count, 
                miss_count, health, modifier, time_played, clear_type, best_clear_type, 
                title, artist, user_id, yearly_play_index, score_below_max)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', scores)
    
    def get_score_by_id(self, cursor: sqlite3.Cursor, score_id: int) -> Optional[ScoreRecord]:
        """ID로 스코어 레코드 조회"""
        cursor.execute(
            'SELECT id, arcaea_id, difficulty, time_played FROM scores WHERE id = ?',
            (score_id,)
        )
        row = cursor.fetchone()
        if row:
            return ScoreRecord(id=row[0], arcaea_id=row[1], difficulty=row[2], time_played=row[3])
        return None
    
    def get_latest_score_id(self, cursor: sqlite3.Cursor, difficulty: int) -> Optional[int]:
        """해당 난이도에서 가장 최근 스코어의 ID 반환"""
        cursor.execute(
            'SELECT id FROM scores WHERE difficulty = ? ORDER BY time_played DESC LIMIT 1',
            (difficulty,)
        )
        row = cursor.fetchone()
        return row[0] if row else None
    
    def find_next_older_score(self, cursor: sqlite3.Cursor, 
                               difficulty: int, before_time: int) -> Optional[tuple]:
        """
        지정된 시간보다 이전인 가장 최근 스코어를 찾습니다.
        
        Returns:
            (id, arcaea_id, time_played) 튜플 또는 None
        """
        cursor.execute(
            '''SELECT id, arcaea_id, time_played FROM scores 
               WHERE difficulty = ? AND time_played < ? 
               ORDER BY time_played DESC LIMIT 1''',
            (difficulty, before_time)
        )
        return cursor.fetchone()
    
    def has_newer_score_for_song(self, cursor: sqlite3.Cursor,
                                  arcaea_id: str, difficulty: int, after_time: int) -> bool:
        """해당 곡/난이도에 지정 시간 이후의 더 최신 스코어가 있는지 확인"""
        cursor.execute(
            'SELECT 1 FROM scores WHERE arcaea_id = ? AND difficulty = ? AND time_played > ? LIMIT 1',
            (arcaea_id, difficulty, after_time)
        )
        return cursor.fetchone() is not None


class PlayCountRepository:
    """play_count 테이블 접근"""
    
    def get_yearly_count(self, cursor: sqlite3.Cursor,
                         arcaea_id: str, difficulty: int, year: int) -> int:
        """해당 곡/난이도/연도의 플레이 카운트 조회"""
        cursor.execute(
            'SELECT yearly_play_count FROM play_count WHERE arcaea_id = ? AND difficulty = ? AND year = ?',
            (arcaea_id, difficulty, year)
        )
        row = cursor.fetchone()
        return row[0] if row else 0
    
    def upsert_counts(self, cursor: sqlite3.Cursor, updates: list[tuple]):
        """
        플레이 카운트 일괄 업데이트 (INSERT 또는 UPDATE)
        
        Args:
            updates: (arcaea_id, difficulty, year, count, count) 형태의 튜플 리스트
                     마지막 count는 ON CONFLICT시 UPDATE용
        """
        cursor.executemany('''
            INSERT INTO play_count (arcaea_id, difficulty, year, yearly_play_count)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(arcaea_id, difficulty, year) DO UPDATE SET yearly_play_count = ?
        ''', updates)


class PinRepository:
    """pin 테이블 접근"""
    
    PIN_SCHEMA = 'CREATE TABLE IF NOT EXISTS pin (difficulty INTEGER PRIMARY KEY, score_id INTEGER, updated_at INTEGER)'
    
    def ensure_table(self, cursor: sqlite3.Cursor):
        """pin 테이블 존재 확인 및 생성"""
        cursor.execute(self.PIN_SCHEMA)
    
    def get_pin(self, cursor: sqlite3.Cursor, difficulty: int) -> Optional[int]:
        """해당 난이도의 pin score_id 조회"""
        try:
            cursor.execute('SELECT score_id FROM pin WHERE difficulty = ?', (difficulty,))
        except sqlite3.OperationalError:
            # 테이블이 없거나 스키마가 다른 경우 재생성
            cursor.execute('DROP TABLE IF EXISTS pin')
            cursor.execute(self.PIN_SCHEMA)
            cursor.execute('SELECT score_id FROM pin WHERE difficulty = ?', (difficulty,))
        
        row = cursor.fetchone()
        if row is None:
            # 레코드가 없으면 NULL로 초기화
            cursor.execute(self.PIN_SCHEMA)
            cursor.execute('INSERT OR IGNORE INTO pin (difficulty, score_id) VALUES (?, NULL)', (difficulty,))
            return None
        return row[0]
    
    def save_pin(self, cursor: sqlite3.Cursor, 
                 difficulty: int, score_id: Optional[int], timestamp: Optional[int] = None):
        """
        pin 저장
        
        Args:
            difficulty: 난이도
            score_id: 스코어 ID (None이면 pin 해제)
            timestamp: 업데이트 시각 (ms), None이면 현재 시각
        """
        if timestamp is None:
            timestamp = int(time.time() * 1000)
        
        cursor.execute(self.PIN_SCHEMA)
        cursor.execute(
            'INSERT OR REPLACE INTO pin (difficulty, score_id, updated_at) VALUES (?, ?, ?)',
            (difficulty, score_id, timestamp)
        )
    
    def get_all_pin_updates(self, cursor: sqlite3.Cursor) -> dict[int, int | None]:
        """모든 난이도의 pin 업데이트 시각 조회"""
        try:
            cursor.execute('SELECT difficulty, updated_at FROM pin')
            return {row[0]: row[1] for row in cursor.fetchall()}
        except sqlite3.OperationalError:
            return {}

    def get_pin_details_with_scores(self, cursor: sqlite3.Cursor) -> dict[int, dict]:
        """
        모든 난이도의 pin 데이터를 연관된 score 정보와 함께 조회.
        
        Returns:
            {difficulty: {'updated_at': int, 'time_played': int, 'arcaea_id': str}}
        """
        try:
            cursor.execute('''
                SELECT p.difficulty, p.updated_at, s.time_played, s.arcaea_id
                FROM pin p
                LEFT JOIN scores s ON p.score_id = s.id
            ''')
            result = {}
            for row in cursor.fetchall():
                result[row[0]] = {
                    'updated_at': row[1] or 0,
                    'time_played': row[2] or 0,
                    'arcaea_id': row[3] or ''
                }
            return result
        except sqlite3.OperationalError:
            return {}
