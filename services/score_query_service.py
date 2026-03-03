"""
user_scores.db 통계 쿼리 서비스.

플레이 통계, 최고 점수, 플레이 횟수 등의 집계 쿼리를 제공한다.
score_repository.py(개별 레코드 CRUD)와 구분되는 읽기 전용 집계 서비스이다.
"""
import os
import sqlite3
from datetime import datetime

from models.constants import (
    DIFFICULTY_CODE_TO_INT, DIFFICULTY_NAMES, DIFFICULTY_COLORS,
    ALL_DIFFICULTIES
)
from repositories.song_repository import get_db_path


def _get_scores_db_path(cache_path: str) -> str:
    """cache_path로부터 user_scores.db 경로를 반환."""
    return os.path.join(cache_path, 'user_scores.db')


def play_stats_difficulty(cache_path: str, difficulty: int):
    """
    Calculates Play Count and Play Time for a specific difficulty.

    Args:
        cache_path: 데이터 디렉토리 경로
        difficulty: Difficulty code (0=PST, 1=PRS, 2=FTR, 3=BYD, 4=ETR)

    Returns:
        tuple: (play_count, play_time_seconds)
    """
    scores_db_path = _get_scores_db_path(cache_path)
    songs_db_path = get_db_path()

    if not os.path.exists(scores_db_path) or not os.path.exists(songs_db_path):
        return 0, 0

    conn = sqlite3.connect(scores_db_path)
    try:
        conn.execute(f"ATTACH DATABASE ? AS songs_db", (songs_db_path,))

        cursor = conn.cursor()
        cursor.execute("""
            SELECT
                SUM(pc.yearly_play_count),
                SUM(pc.yearly_play_count * IFNULL(s.length, 140))
            FROM play_count pc
            JOIN songs_db.songs s ON pc.arcaea_id = s.arcaea_id
            JOIN songs_db.charts c ON s.id = c.song_id AND pc.difficulty = c.difficulty
            WHERE pc.difficulty = ?
        """, (difficulty,))
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


def play_stats_total(cache_path: str):
    """
    Calculates Total Play Count and Total Play Time by summing all difficulties.

    Args:
        cache_path: 데이터 디렉토리 경로

    Returns:
        tuple: (total_play_count, total_play_time_seconds)
    """
    total_count = 0
    total_time = 0

    for diff in [0, 1, 2, 3, 4]:
        count, time_sec = play_stats_difficulty(cache_path, diff)
        total_count += count
        total_time += time_sec

    return total_count, total_time


def get_best_scores_per_chart(cache_path: str):
    """
    For each (arcaea_id, difficulty), fetches the record with the highest score.

    Args:
        cache_path: 데이터 디렉토리 경로

    Returns:
        dict: {(arcaea_id, difficulty): {
            'score', 'shiny_perfect', 'perfect', 'near', 'miss',
            'best_clear_type', 'time_played', 'score_below_max'
        }}
    """
    scores_db_path = _get_scores_db_path(cache_path)
    if not os.path.exists(scores_db_path):
        return {}

    conn = sqlite3.connect(scores_db_path)
    try:
        cursor = conn.cursor()
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


def get_play_counts(cache_path: str):
    """
    Fetches total play count for each (arcaea_id, difficulty).
    Only includes play counts for valid charts that exist in songs.db.

    Args:
        cache_path: 데이터 디렉토리 경로

    Returns:
        dict: {(arcaea_id, difficulty): total_play_count}
    """
    scores_db_path = _get_scores_db_path(cache_path)
    songs_db_path = get_db_path()

    if not os.path.exists(scores_db_path) or not os.path.exists(songs_db_path):
        return {}

    conn = sqlite3.connect(scores_db_path)
    try:
        conn.execute(f"ATTACH DATABASE ? AS songs_db", (songs_db_path,))

        cursor = conn.cursor()
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


def get_this_year_play_counts(cache_path: str):
    """
    Fetches play count for the current year for each (arcaea_id, difficulty).

    Args:
        cache_path: 데이터 디렉토리 경로

    Returns:
        dict: {(arcaea_id, difficulty): this_year_play_count}
    """
    scores_db_path = _get_scores_db_path(cache_path)
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


def _allowed_difficulties(difficulty_filter: str):
    """
    난이도 필터 문자열을 파싱하여 포함할 난이도 정수 집합을 반환한다.

    Args:
        difficulty_filter: 'all' 또는 'pst,prs,ftr' 형태의 쉼표 구분 문자열

    Returns:
        난이도 정수 집합 (예: {0, 1, 2})
    """
    if difficulty_filter == 'all':
        return ALL_DIFFICULTIES.copy()
    if not difficulty_filter:
        return set()
    return {
        DIFFICULTY_CODE_TO_INT.get(p.strip().lower())
        for p in difficulty_filter.split(',')
        if p.strip().lower() in DIFFICULTY_CODE_TO_INT
    }


def get_top_10_most_played(
    cache_path: str,
    difficulty_filter: str,
    grouping_criteria: str,
    most_played_scope: str
):
    """
    Returns the top 10 most played songs or charts.

    Args:
        cache_path: 데이터 디렉토리 경로
        difficulty_filter: 'all' or comma-separated codes (e.g. 'pst,prs,ftr')
        grouping_criteria: 'song' (aggregate by song) or 'chart' (per difficulty)
        most_played_scope: 'total' (all years) or 'this_year'

    Returns:
        list of dict: by song: [{'title', 'artist', 'playCount', 'arcaeaId', 'colorCode'}, ...]
                      by chart: same + 'difficulty' (int), 'difficultyName', 'difficultyColor'
    """
    scores_db_path = _get_scores_db_path(cache_path)
    songs_db_path = get_db_path()
    if not os.path.exists(scores_db_path) or not os.path.exists(songs_db_path):
        return []

    allowed = _allowed_difficulties(difficulty_filter)

    if most_played_scope == 'this_year':
        raw_counts = get_this_year_play_counts(cache_path)
    else:
        raw_counts = get_play_counts(cache_path)

    # Filter by allowed difficulties
    filtered = {}
    for (aid, diff), count in raw_counts.items():
        d = int(diff) if diff is not None else 0
        if d in allowed and count:
            filtered[(aid, d)] = count

    if not filtered:
        return []

    if grouping_criteria == 'chart':
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
