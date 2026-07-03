"""
Statistics 탭 비즈니스 로직.

데이터 로딩, 필터링, 정렬, 아이템 빌드를 담당한다.
PyQt6 의존 없이 순수 Python으로 구현된다.
"""
import math
from dataclasses import dataclass
from datetime import datetime
from models.potential import calculate_potential
from services.score_query_service import (
    get_best_scores_per_chart, get_play_counts,
    get_this_year_play_counts
)
from repositories.song_repository import get_all_songs_with_charts
from models.constants import (
    calculate_rank,
    DIFFICULTY_ORDER, DIFFICULTY_NAMES, DIFFICULTY_COLORS, SCORE_RANKS,
    RANK_COLORS, DEFAULT_RANK_COLOR, CLEAR_TYPE_TEXTS, CLEAR_TYPE_ABBREVIATIONS
)


@dataclass
class FilterParams:
    """필터 상태 값 객체."""
    difficulties: list  # [int]
    level_min_str: str
    level_max_str: str
    bp_mode: bool
    bp_min: float
    bp_max: float
    ignore_chart: str
    skill_issues: str
    score_min_rank: int
    score_max_rank: int
    clear_types: list  # [int]


class StatisticsService:
    """Statistics 탭 비즈니스 로직: 데이터 로딩, 필터링, 정렬, 아이템 빌드."""

    def __init__(self):
        # 데이터 캐시
        self.songs_data = {}
        self.songs_by_db_id = {}
        self.scores_data = {}
        self.play_counts = {}
        self.this_year_play_counts = {}

        # 중간 결과 캐시
        self._full_items_cache = None
        self._full_items_cache_key = None
        self._filtered_items_cache = None
        self._filtered_cache_key = None

        # Level/BP 경계
        self.available_levels = []
        self.available_bps = []
        self.level_boundaries = {}

    @staticmethod
    def _normalize_level(level) -> str:
        """Normalize level text for consistent backend->QML contract."""
        return str(level or "").strip()

    def load_data(self, cache_path: str, song_title_language: str = 'en'):
        """DB에서 데이터 로딩 + 정규화. 경계 계산 포함. song_title_language는 'en'/'jp'."""
        # Load raw data
        raw_songs = get_all_songs_with_charts()
        raw_scores = get_best_scores_per_chart(cache_path)
        raw_play_counts = get_play_counts(cache_path)
        raw_this_year_play_counts = get_this_year_play_counts(cache_path)

        # Normalize songs data (ensure diff keys are int)
        lang = str(song_title_language or 'en').lower()
        self.songs_data = {}
        self.songs_by_db_id = {}
        for sid, sdata in raw_songs.items():
            normalized_song = dict(sdata)
            normalized_charts = {}
            for diff, cdata in sdata.get('charts', {}).items():
                normalized_chart = dict(cdata)
                normalized_chart['level'] = self._normalize_level(normalized_chart.get('level', ''))
                try:
                    normalized_charts[int(diff)] = normalized_chart
                except:
                    normalized_charts[diff] = normalized_chart
            normalized_song['charts'] = normalized_charts

            canonical_title = str(normalized_song.get('canonical_title') or '').strip()
            title_en = str(normalized_song.get('title_en') or '').strip()
            title_jp = str(normalized_song.get('title_jp') or '').strip()
            normalized_song['canonical_title'] = canonical_title
            normalized_song['title_en'] = title_en
            normalized_song['title_jp'] = title_jp
            if lang == 'jp':
                normalized_song['title'] = title_jp or title_en or canonical_title or 'Unknown'
            else:
                normalized_song['title'] = title_en or title_jp or canonical_title or 'Unknown'
            normalized_song['song_db_id'] = sid

            self.songs_data[sid] = normalized_song
            arcaea_id = normalized_song.get('arcaea_id')
            if arcaea_id:
                self.songs_by_db_id[sid] = normalized_song

        # Normalize scores data
        self.scores_data = {}
        for (aid, diff), scdata in raw_scores.items():
            try:
                self.scores_data[(aid, int(diff))] = scdata
            except:
                self.scores_data[(aid, diff)] = scdata

        # Normalize play counts
        self.play_counts = {}
        for (aid, diff), count in raw_play_counts.items():
            try:
                self.play_counts[(aid, int(diff))] = count
            except:
                self.play_counts[(aid, diff)] = count

        # Normalize this year play counts
        self.this_year_play_counts = {}
        for (aid, diff), count in raw_this_year_play_counts.items():
            try:
                self.this_year_play_counts[(aid, int(diff))] = count
            except:
                self.this_year_play_counts[(aid, diff)] = count

        # Calculate Level/BP boundaries
        self._calculate_level_bp_boundaries()

        # 데이터 원본이 바뀌었으므로 중간 캐시는 전부 무효화
        self.invalidate_caches()

    def invalidate_caches(self):
        """중간 결과 캐시를 모두 무효화한다."""
        self._full_items_cache = None
        self._full_items_cache_key = None
        self._filtered_items_cache = None
        self._filtered_cache_key = None

    def build_filtered_sorted_list(
        self, display_mode, sort_mode, sort_ascending,
        search_text, filters: FilterParams
    ) -> list:
        """호환용 API: 분리된 경로를 순차 실행해 완성 리스트를 반환."""
        full = self.build_full_items(display_mode, filters)
        filtered = self.filter_items(full, display_mode, search_text, filters)
        sorted_items = self.sort_items(filtered, sort_mode, sort_ascending)
        self.apply_display_values(sorted_items, sort_mode, display_mode)
        return sorted_items

    def build_full_items(self, display_mode: str, filters: FilterParams = None) -> list:
        """필터 전(Chart) 또는 필터 반영 집계(Song) 기준의 전체 아이템을 빌드한다."""
        cache_key = self._make_full_items_cache_key(display_mode, filters)
        if self._full_items_cache_key == cache_key and self._full_items_cache is not None:
            return self._full_items_cache

        if display_mode == "chart":
            items = self._build_all_chart_items()
        else:
            items = self._build_all_song_items(filters)

        self._full_items_cache = items
        self._full_items_cache_key = cache_key

        # full 캐시가 바뀌면 filtered 캐시도 무효화
        self._filtered_items_cache = None
        self._filtered_cache_key = None
        return items

    def filter_items(
        self,
        items: list,
        display_mode: str,
        search_text: str,
        filters: FilterParams,
    ) -> list:
        """빌드된 아이템에서 검색/필터 조건에 맞는 항목만 추출한다."""
        search_lower = (search_text or "").lower().strip()
        filter_hash = self._make_filter_hash(filters) if filters else None
        cache_key = (id(items), display_mode, search_lower, filter_hash)

        if self._filtered_cache_key == cache_key and self._filtered_items_cache is not None:
            return self._filtered_items_cache

        result = []
        for item in items:
            if search_lower:
                if (
                    search_lower not in item.get('canonical_title', '').lower()
                    and search_lower not in item.get('title_en', '').lower()
                    and search_lower not in item.get('title_jp', '').lower()
                    and search_lower not in item.get('artist', '').lower()
                ):
                    continue

            if (
                display_mode == "chart"
                and filters is not None
                and not self._item_matches_chart_filter(item, filters)
            ):
                continue

            result.append(item)

        self._filtered_items_cache = result
        self._filtered_cache_key = cache_key
        return result

    def sort_items(self, items: list, sort_mode: str, sort_ascending: bool) -> list:
        """정렬된 새 리스트를 반환한다. 원본 리스트는 변경하지 않는다."""
        return sorted(
            items,
            key=lambda item: self._get_sort_key(item, sort_mode),
            reverse=not sort_ascending,
        )

    def apply_display_values(self, items: list, sort_mode: str, display_mode: str):
        """정렬된 리스트의 displayValue를 in-place로 갱신한다."""
        for item in items:
            item['displayValue'] = self._format_display_value(
                item, sort_mode, display_mode
            )

    def _make_full_items_cache_key(self, display_mode: str, filters: FilterParams):
        """Song 모드는 필터에 따라 집계가 달라지므로 필터 해시를 캐시 키에 포함한다."""
        if display_mode == "song":
            return (display_mode, self._make_filter_hash(filters))
        return (display_mode,)

    def _make_filter_hash(self, filters: FilterParams):
        if filters is None:
            return None
        return (
            tuple(sorted(int(v) for v in (filters.difficulties or []))),
            str(filters.level_min_str),
            str(filters.level_max_str),
            bool(filters.bp_mode),
            round(float(filters.bp_min), 4),
            round(float(filters.bp_max), 4),
            str(filters.ignore_chart),
            str(filters.skill_issues),
            int(filters.score_min_rank),
            int(filters.score_max_rank),
            tuple(sorted(int(v) for v in (filters.clear_types or []))),
        )

    def _build_all_chart_items(self) -> list:
        """Chart 모드용 전체 차트 아이템을 빌드한다 (필터 비의존)."""
        items = []
        for song_db_id, song_data in self.songs_data.items():
            arcaea_id = song_data.get('arcaea_id')
            if not arcaea_id:
                continue

            song_total_play_count = self._get_filtered_song_play_count(
                arcaea_id, song_data, None
            )
            for diff in DIFFICULTY_ORDER:
                chart_data = song_data.get('charts', {}).get(diff)
                if not chart_data:
                    continue
                items.append(
                    self._build_chart_item(
                        song_db_id,
                        arcaea_id,
                        song_data,
                        diff,
                        chart_data,
                        None,
                        song_total_play_count=song_total_play_count,
                    )
                )
        return items

    def _build_all_song_items(self, filters: FilterParams = None) -> list:
        """Song 모드용 집계 아이템을 빌드한다."""
        items = []
        for song_db_id, song_data in self.songs_data.items():
            arcaea_id = song_data.get('arcaea_id')
            if not arcaea_id:
                continue

            filtered_diffs = []
            for diff, chart_data in song_data.get('charts', {}).items():
                if filters is None:
                    filtered_diffs.append(diff)
                    continue

                score_data = self.scores_data.get((arcaea_id, diff), {})
                if self._matches_filter(chart_data, score_data, diff, filters):
                    filtered_diffs.append(diff)

            if not filtered_diffs:
                continue

            items.append(
                self._build_song_item(song_db_id, arcaea_id, song_data, filtered_diffs, filters)
            )

        return items

    def _item_matches_chart_filter(self, item: dict, filters: FilterParams) -> bool:
        """Chart 아이템(dict) 기준 필터링."""
        difficulty = item.get('difficulty')
        if difficulty not in filters.difficulties:
            return False

        if filters.bp_mode:
            bp = item.get('bp', 0)
            if bp < filters.bp_min or bp > filters.bp_max:
                return False
        else:
            level_str = item.get('level', '0')
            if level_str in self.available_levels:
                level_idx = self.available_levels.index(level_str)
                min_idx = (
                    self.available_levels.index(filters.level_min_str)
                    if filters.level_min_str in self.available_levels
                    else 0
                )
                max_idx = (
                    self.available_levels.index(filters.level_max_str)
                    if filters.level_max_str in self.available_levels
                    else len(self.available_levels) - 1
                )
                if level_idx < min_idx or level_idx > max_idx:
                    return False

        for flag_name, flag_value in [
            ('ignoreChart', filters.ignore_chart),
            ('skillIssues', filters.skill_issues),
        ]:
            item_flag = item.get(flag_name, False)
            if flag_value == "only" and not item_flag:
                return False
            if flag_value == "off" and item_flag:
                return False

        if item.get('hasScore', False):
            clear_type = item.get('bestClearType', 0)
            if clear_type not in filters.clear_types:
                return False

        rank_idx = self.get_score_rank_index(
            item.get('bestScore', 0),
            item.get('hasScore', False),
            item.get('scoreBelowMax', None),
        )
        if rank_idx < filters.score_min_rank or rank_idx > filters.score_max_rank:
            return False

        return True

    def build_selected_item_details(self, song_db_id: int, filters: FilterParams) -> list:
        """Build detail payload for one selected song only."""
        if song_db_id is None:
            return []
        song_data = self.songs_by_db_id.get(song_db_id)
        if not song_data:
            return []
        arcaea_id = song_data.get('arcaea_id')
        if not arcaea_id:
            return []
        return self._build_all_difficulty_details(arcaea_id, song_data, filters)

    # === 내부 헬퍼 메서드 ===

    def _matches_filter(self, chart_data, score_data, difficulty, filters: FilterParams) -> bool:
        """Check if a chart matches the given filters."""
        # Difficulty filter
        if difficulty not in filters.difficulties:
            return False

        # Level/BP range filter
        if filters.bp_mode:
            bp = chart_data.get('bp', 0)
            if bp < filters.bp_min or bp > filters.bp_max:
                return False
        else:
            level_str = chart_data.get('level', '0')
            # Use available_levels for proper ordering comparison
            if level_str in self.available_levels:
                level_idx = self.available_levels.index(level_str)
                min_idx = self.available_levels.index(filters.level_min_str) if filters.level_min_str in self.available_levels else 0
                max_idx = self.available_levels.index(filters.level_max_str) if filters.level_max_str in self.available_levels else len(self.available_levels) - 1
                if level_idx < min_idx or level_idx > max_idx:
                    return False

        # Chart flags filter
        for flag_name, flag_value in [
            ('ignore_chart', filters.ignore_chart),
            ('skill_issues', filters.skill_issues)
        ]:
            chart_flag = chart_data.get(flag_name, False)
            if flag_value == "only" and not chart_flag:
                return False
            elif flag_value == "contain":
                pass  # Include regardless
            elif flag_value == "off" and chart_flag:
                return False

        # Clear type filter
        if score_data:
            clear_type = score_data.get('best_clear_type', 0)
            if clear_type not in filters.clear_types:
                return False

        # Score rank filter
        score = score_data.get('score', 0) if score_data else 0
        time_played = score_data.get('time_played', 0) if score_data else 0
        has_score = time_played > 0
        score_below_max = score_data.get('score_below_max', None) if score_data else None
        rank_idx = self.get_score_rank_index(score, has_score, score_below_max)
        if rank_idx < filters.score_min_rank or rank_idx > filters.score_max_rank:
            return False

        return True

    def get_score_rank_index(self, score, has_score=None, score_below_max=None) -> int:
        """Convert a score to its rank index in SCORE_RANKS.

        Args:
            score: The score value
            has_score: If True, score=0 means 'D' grade (Track Lost). If None, falls back to score > 0 check.
            score_below_max: If 0, the score is MAX (all shiny perfects). If None, PM and MAX are not distinguished.
        """
        # Determine if this is an actual play record
        is_played = has_score if has_score is not None else (score > 0)

        if not is_played:
            return 0  # '-' (no score/never played)
        elif score < 8600000:
            return 1  # 'D'
        elif score < 8900000:
            return 2  # 'C'
        elif score < 9200000:
            return 3  # 'B'
        elif score < 9500000:
            return 4  # 'A'
        elif score < 9800000:
            return 5  # 'AA'
        elif score < 9900000:
            return 6  # 'EX'
        elif score < 9950000:
            return 7  # 'EX+'
        elif score < 9980000:
            return 8  # '99.5%'
        elif score < 10000000:
            return 9  # '99.8%'
        elif score_below_max is not None and score_below_max == 0:
            return 11  # 'MAX'
        else:
            return 10  # 'PM'

    def _get_filtered_song_play_count(self, arcaea_id, song_data, filters: FilterParams = None) -> int:
        """Calculate total play count for FILTERED difficulties of a song.

        This sums play counts only for difficulties that pass the current filter,
        providing song-mode-style aggregation while respecting filter settings.
        Used for display in the detailed view header.
        """
        total = 0
        for diff, chart_data in song_data.get('charts', {}).items():
            if filters is None:
                total += self.play_counts.get((arcaea_id, diff), 0)
                continue
            score_data = self.scores_data.get((arcaea_id, diff), {})
            if self._matches_filter(chart_data, score_data, diff, filters):
                total += self.play_counts.get((arcaea_id, diff), 0)
        return total

    def _build_chart_item(
        self, song_db_id, arcaea_id, song_data, difficulty, chart_data, filters: FilterParams = None,
        song_total_play_count=None
    ) -> dict:
        """Build a chart item for the list model."""
        score_data = self.scores_data.get((arcaea_id, difficulty), {})
        play_count = self.play_counts.get((arcaea_id, difficulty), 0)
        this_year_play_count = self.this_year_play_counts.get((arcaea_id, difficulty), 0)
        if song_total_play_count is None:
            song_total_play_count = self._get_filtered_song_play_count(
                arcaea_id, song_data, filters
            )

        score = score_data.get('score', 0)
        time_played = score_data.get('time_played', 0)
        # hasScore: True if there's actual play data (time_played > 0 means a record exists)
        has_score = time_played > 0
        rank = calculate_rank(score) if has_score else ""
        best_clear_type = score_data.get('best_clear_type', 0)

        return {
            'songDbId': song_db_id,
            'arcaeaId': arcaea_id,
            'title': song_data['title'],
            'canonical_title': song_data.get('canonical_title', ''),
            'title_en': song_data.get('title_en', ''),
            'title_jp': song_data.get('title_jp', ''),
            'artist': song_data['artist'],
            'length': song_data['length'],
            'bpm': song_data['bpm'],
            'difficulty': difficulty,
            'difficultyName': DIFFICULTY_NAMES.get(difficulty, ''),
            'difficultyColor': DIFFICULTY_COLORS.get(difficulty, '#888'),
            'level': chart_data.get('level', ''),
            'bp': chart_data.get('bp', 0),
            's_bp': chart_data.get('s_bp', 0),
            'perceived_bp': chart_data.get('perceived_bp', 0),
            'noteCount': chart_data.get('note_count', 0),
            'bestScore': score,
            'hasScore': has_score,
            'rank': rank,
            'rankColor': RANK_COLORS.get(rank, DEFAULT_RANK_COLOR) if rank else DEFAULT_RANK_COLOR,
            'clearTypeText': CLEAR_TYPE_TEXTS.get(best_clear_type, '') if has_score else '',
            'clearTypeAbbr': CLEAR_TYPE_ABBREVIATIONS.get(best_clear_type, '') if has_score else '',
            'pure': score_data.get('perfect', 0),
            'shinyPure': score_data.get('shiny_perfect', 0),
            'far': score_data.get('near', 0),
            'lost': score_data.get('miss', 0),
            'bestClearType': best_clear_type,
            'timePlayed': time_played,
            'lastPlayedDate': self._format_full_datetime(time_played),
            'scoreBelowMax': score_data.get('score_below_max', 0),
            'ignoreChart': chart_data.get('ignore_chart', False),
            'skillIssues': chart_data.get('skill_issues', False),
            'totalPlayCount': play_count,
            'thisYearPlayCount': this_year_play_count,
            'songTotalPlayCount': song_total_play_count,
            'potential': calculate_potential(
                chart_data.get('bp', 0),
                chart_data.get('note_count', 0),
                score,
                score_data.get('shiny_perfect', 0),
            ) if has_score else None,
            'displayValue': '',  # Will be set based on sort mode
        }

    def _build_difficulty_summary(self, difficulty, chart_data) -> dict:
        """Build lightweight difficulty summary for song list delegate."""
        return {
            'difficulty': difficulty,
            'level': chart_data.get('level', ''),
            'difficultyColor': DIFFICULTY_COLORS.get(difficulty, '#888'),
            'ignoreChart': chart_data.get('ignore_chart', False),
            'skillIssues': chart_data.get('skill_issues', False),
        }

    def _build_song_item(self, song_db_id, arcaea_id, song_data, filtered_difficulties, filters: FilterParams = None) -> dict:
        """Build a song item aggregating filtered difficulties."""
        # Find best values among filtered difficulties
        best_level = ""
        best_bp = 0
        best_s_bp = 0
        best_perceived_bp = 0
        best_score = 0
        best_rank = ""
        total_play_count = 0
        recent_time_played = 0
        best_score_below_max = 0
        best_max_pure = 0
        best_max_shiny = 0
        best_max_far = 0
        best_max_lost = 0
        total_this_year_play_count = 0

        # Track which difficulty has the best value for each sort criteria
        best_diff_for_score = -1
        best_diff_for_max = -1
        best_diff_for_recent = -1
        best_diff_for_level = -1
        best_diff_for_s_bp = -1
        best_diff_for_perceived_bp = -1
        best_potential = None
        best_diff_for_potential = -1

        # Track highest difficulty for thumbnail (priority: BYD(3) > ETR(4) > FTR(2) > PRS(1) > PST(0))
        thumbnail_difficulty = -1
        THUMBNAIL_PRIORITY = {3: 0, 4: 1, 2: 2, 1: 3, 0: 4}  # Lower value = higher priority

        diff_details = []

        for diff in DIFFICULTY_ORDER:
            if diff not in filtered_difficulties:
                continue

            chart_data = song_data['charts'].get(diff, {})
            if not chart_data:
                continue

            score_data = self.scores_data.get((arcaea_id, diff), {})
            score = score_data.get('score', 0)
            time_played = score_data.get('time_played', 0)
            has_score = time_played > 0
            rank = calculate_rank(score) if has_score else ""
            score_below_max = score_data.get('score_below_max', 0)
            pure = score_data.get('perfect', 0)
            shiny_pure = score_data.get('shiny_perfect', 0)
            far = score_data.get('near', 0)
            lost = score_data.get('miss', 0)
            play_count = self.play_counts.get((arcaea_id, diff), 0)
            this_year_play_count = self.this_year_play_counts.get((arcaea_id, diff), 0)

            diff_details.append(self._build_difficulty_summary(diff, chart_data))

            # Track best potential
            if has_score:
                p = calculate_potential(
                    chart_data.get('bp', 0),
                    chart_data.get('note_count', 0),
                    score,
                    shiny_pure,
                )
                if p is not None and (best_potential is None or p > best_potential):
                    best_potential = p
                    best_diff_for_potential = diff

            # Track highest difficulty for thumbnail
            if thumbnail_difficulty == -1 or THUMBNAIL_PRIORITY.get(diff, 99) < THUMBNAIL_PRIORITY.get(thumbnail_difficulty, 99):
                thumbnail_difficulty = diff

            # Aggregate values and track best difficulty
            if chart_data.get('bp', 0) > best_bp:
                best_bp = chart_data.get('bp', 0)
                best_level = chart_data.get('level', '')
                best_diff_for_level = diff
            if chart_data.get('s_bp', 0) > best_s_bp:
                best_s_bp = chart_data.get('s_bp', 0)
                best_diff_for_s_bp = diff
            if chart_data.get('perceived_bp', 0) > best_perceived_bp:
                best_perceived_bp = chart_data.get('perceived_bp', 0)
                best_diff_for_perceived_bp = diff

            if score > best_score:
                best_score = score
                best_rank = rank
                best_diff_for_score = diff

            total_play_count += play_count
            total_this_year_play_count += this_year_play_count

            if time_played > recent_time_played:
                recent_time_played = time_played
                best_diff_for_recent = diff

            # MAX sort: find chart with smallest (perfect + near + miss - shiny_perfect) value
            # Only consider charts that have been played (hasScore is True)
            if has_score:
                chart_max_val = pure + far + lost - shiny_pure
                current_best_max_val = best_max_pure + best_max_far + best_max_lost - best_max_shiny
                # Use smallest value, or if first played chart
                if best_diff_for_max == -1 or chart_max_val < current_best_max_val or (chart_max_val == current_best_max_val and score_below_max < best_score_below_max):
                    best_score_below_max = score_below_max
                    best_diff_for_max = diff
                    best_max_pure = pure
                    best_max_shiny = shiny_pure
                    best_max_far = far
                    best_max_lost = lost

        # hasScore for song: True if any chart has been played
        has_score = recent_time_played > 0

        return {
            'songDbId': song_db_id,
            'arcaeaId': arcaea_id,
            'title': song_data['title'],
            'canonical_title': song_data.get('canonical_title', ''),
            'title_en': song_data.get('title_en', ''),
            'title_jp': song_data.get('title_jp', ''),
            'artist': song_data['artist'],
            'length': song_data['length'],
            'bpm': song_data['bpm'],
            'level': best_level,
            'bp': best_bp,
            's_bp': best_s_bp,
            'perceived_bp': best_perceived_bp,
            'bestScore': best_score,
            'hasScore': has_score,
            'rank': best_rank,
            'totalPlayCount': total_play_count,
            'thisYearPlayCount': total_this_year_play_count,
            'songTotalPlayCount': self._get_filtered_song_play_count(arcaea_id, song_data, filters),
            'timePlayed': recent_time_played,
            'scoreBelowMax': best_score_below_max,
            'pure': best_max_pure,
            'shinyPure': best_max_shiny,
            'far': best_max_far,
            'lost': best_max_lost,
            'filteredDifficulties': diff_details,
            'displayValue': '',
            # Thumbnail: highest difficulty among filtered
            'thumbnailDifficulty': thumbnail_difficulty,
            # Best difficulty for each sort mode
            'bestDiffForScore': best_diff_for_score,
            'bestDiffForMax': best_diff_for_max,
            'bestDiffForRecent': best_diff_for_recent,
            'bestDiffForLevel': best_diff_for_level,
            'bestDiffForSBp': best_diff_for_s_bp,
            'bestDiffForPerceivedBp': best_diff_for_perceived_bp,
            'bestPotential': best_potential,
            'bestDiffForPotential': best_diff_for_potential,
        }

    def _build_all_difficulty_details(self, arcaea_id, song_data, filters: FilterParams) -> list:
        """Build details for ALL difficulties of a song, with isFiltered flag.

        Used for detailed view to show all difficulties regardless of filter.
        """
        all_details = []
        song_total_play_count = self._get_filtered_song_play_count(
            arcaea_id, song_data, filters
        )

        for diff in DIFFICULTY_ORDER:
            chart_data = song_data.get('charts', {}).get(diff)
            if not chart_data:
                continue

            score_data = self.scores_data.get((arcaea_id, diff), {})

            # Check if this chart is filtered out
            is_filtered = not self._matches_filter(chart_data, score_data, diff, filters)

            # Build the chart item
            chart_item = self._build_chart_item(
                song_data.get('song_db_id'), arcaea_id, song_data, diff, chart_data, filters,
                song_total_play_count=song_total_play_count
            )
            chart_item['isFiltered'] = is_filtered

            all_details.append(chart_item)

        return all_details

    def _get_sort_key(self, item, sort_mode):
        """Get the sort key based on sort mode."""
        if sort_mode == "title":
            return item.get('title', '').lower()
        elif sort_mode == "score":
            # Sort by (hasScore, bestScore) so played records (even score=0) > unplayed records
            has_score = item.get('hasScore', False)
            return (1 if has_score else 0, item.get('bestScore', 0))
        elif sort_mode == "max":
            # Unplayed records: treat as highest MAX value (positive infinity)
            if not item.get('hasScore', False):
                return (float('inf'), float('inf'))
            # Primary: perfect + near + miss - shiny_perfect
            # For MAX records (primary=0), higher BP is better
            # For non-MAX records, lower scoreBelowMax is better
            pure = item.get('pure', 0)
            shiny = item.get('shinyPure', 0)
            far = item.get('far', 0)
            lost = item.get('lost', 0)
            primary_key = pure + far + lost - shiny
            if primary_key == 0:
                return (primary_key, -item.get('bp', 0))
            else:
                return (primary_key, item.get('scoreBelowMax', 0))
        elif sort_mode == "total_play_count":
            return item.get('totalPlayCount', 0)
        elif sort_mode == "this_year_play_count":
            return item.get('thisYearPlayCount', 0)
        elif sort_mode == "recent_played":
            return item.get('timePlayed', 0)
        elif sort_mode == "level":
            return item.get('bp', 0)
        elif sort_mode == "s_bp":
            return item.get('s_bp', 0)
        elif sort_mode == "perceived_bp":
            return item.get('perceived_bp', 0)
        elif sort_mode == "potential":
            has_score = item.get('hasScore', False)
            # Chart 아이템은 'potential', Song 아이템은 'bestPotential'
            potential = item.get('potential') if 'potential' in item else item.get('bestPotential')
            if not has_score or potential is None:
                return (0, float('-inf'))
            return (1, potential)
        elif sort_mode == "length":
            return item.get('length', 0)
        return item.get('title', '').lower()

    def get_best_diff_for_sort(self, item, sort_mode) -> int:
        """Get the best difficulty for the given sort mode from a song item.

        Returns the difficulty number (0-4) if the sort mode highlights a specific difficulty,
        or -1 if the sort mode doesn't highlight any (e.g., title, total_play_count, length).
        """
        if sort_mode == "score":
            return item.get('bestDiffForScore', -1)
        elif sort_mode == "max":
            return item.get('bestDiffForMax', -1)
        elif sort_mode == "recent_played":
            return item.get('bestDiffForRecent', -1)
        elif sort_mode == "level":
            return item.get('bestDiffForLevel', -1)
        elif sort_mode == "s_bp":
            return item.get('bestDiffForSBp', -1)
        elif sort_mode == "perceived_bp":
            return item.get('bestDiffForPerceivedBp', -1)
        elif sort_mode == "potential":
            return item.get('bestDiffForPotential', -1)
        return -1

    def _format_display_value(self, item, sort_mode, display_mode) -> str:
        """Format the display value based on sort mode and display mode."""
        is_chart_mode = display_mode == "chart"

        if sort_mode == "title":
            if is_chart_mode:
                diff_name = item.get('difficultyName', '')
                level = item.get('level', '')
                return f"{diff_name} {level}"
            return ""
        elif sort_mode == "score":
            score = item.get('bestScore', 0)
            rank = item.get('rank', '')
            has_score = item.get('hasScore', False)
            if has_score:
                return f"{score:,}"
            return "-"
        elif sort_mode == "max":
            # Display value: perfect + near + miss - shiny_perfect
            # Show "-" for unplayed records
            if not item.get('hasScore', False):
                return "-"
            pure = item.get('pure', 0)
            shiny = item.get('shinyPure', 0)
            far = item.get('far', 0)
            lost = item.get('lost', 0)
            display_val = pure + far + lost - shiny
            return f"MAX-{display_val}" if display_val > 0 else "MAX"
        elif sort_mode == "total_play_count":
            count = item.get('totalPlayCount', 0)
            if count <= 0:
                return "Never played"
            return f"{count} plays"
        elif sort_mode == "this_year_play_count":
            count = item.get('thisYearPlayCount', 0)
            if count <= 0:
                return "Never played"
            return f"{count} plays"
        elif sort_mode == "recent_played":
            ts = item.get('timePlayed', 0)
            if not ts or ts <= 0:
                return "Never played"
            return self._format_time(ts)
        elif sort_mode == "level":
            if is_chart_mode:
                level = item.get('level', '')
                bp = item.get('bp', 0)
                return f"{level} ({bp:.1f})"
            return item.get('level', '')
        elif sort_mode == "s_bp":
            s_bp = item.get('s_bp', 0)
            if s_bp <= 0:
                return "?"
            return f"{s_bp:.2f}"
        elif sort_mode == "perceived_bp":
            perceived_bp = item.get('perceived_bp', 0)
            if perceived_bp <= 0:
                return "?"
            return f"{perceived_bp:.2f}"
        elif sort_mode == "potential":
            potential = item.get('potential') if is_chart_mode else item.get('bestPotential')
            has_score = item.get('hasScore', False)
            if not has_score or potential is None:
                return "-"
            # 4자리 버림 (round가 아닌 truncate)
            return f"{math.floor(potential * 10000) / 10000:.4f}"
        elif sort_mode == "length":
            length = item.get('length', 0)
            if length <= 0:
                return "?"
            return f"{length // 60}:{length % 60:02d}"
        return ""

    def _format_time(self, timestamp) -> str:
        """Format timestamp to readable string."""
        if not timestamp or timestamp <= 0:
            return ""

        try:
            timestamp = float(timestamp)
            # If timestamp is in milliseconds (13+ digits), convert to seconds
            if timestamp > 100000000000:
                timestamp = timestamp / 1000.0

            dt = datetime.fromtimestamp(timestamp)
        except (OSError, ValueError, OverflowError):
            return ""

        now = datetime.now()

        # Compare dates to allow correct Today/Yesterday logic regardless of time difference
        now_date = now.date()
        play_date = dt.date()
        days_diff = (now_date - play_date).days

        if days_diff == 0:
            return f"Today {dt.strftime('%H:%M')}"
        elif days_diff == 1:
            return "Yesterday"
        elif days_diff < 7:
            return f"{days_diff} days ago"
        else:
            if dt.year == now.year:
                return dt.strftime("%b %d")
            return dt.strftime("%Y-%m-%d")

    def _format_full_datetime(self, timestamp) -> str:
        """Format timestamp to YYYY-MM-DD HH:MM."""
        if not timestamp or timestamp <= 0:
            return "-"

        try:
            timestamp = float(timestamp)
            # If timestamp is in milliseconds (13+ digits), convert to seconds
            if timestamp > 100000000000:
                timestamp = timestamp / 1000.0

            dt = datetime.fromtimestamp(timestamp)
            return dt.strftime("%Y-%m-%d %H:%M")
        except (OSError, ValueError, OverflowError):
            return "-"

    def _calculate_level_bp_boundaries(self):
        """Calculate unique levels, BPs, and level->BP boundary mapping from DB data."""
        # Outliers to exclude from boundary calculation
        OUTLIER_CHARTS = [
            ('dropdead', 2),            # dropdead FTR
            ('internetyamero', 2),      # INTERNET YAMERO FTR (arcaea_id may differ)
        ]

        level_bp_map = {}  # level_str -> list of BP values
        all_bps = set()
        all_levels = set()

        for _, sdata in self.songs_data.items():
            title_lower = sdata.get('title', '').lower().replace(' ', '')
            for diff, cdata in sdata.get('charts', {}).items():
                # Check if this is an outlier
                is_outlier = False
                for (outlier_name, outlier_diff) in OUTLIER_CHARTS:
                    if outlier_name in title_lower and diff == outlier_diff:
                        is_outlier = True
                        break

                level_str = cdata.get('level', '')
                bp = cdata.get('bp', 0)

                if level_str:
                    all_levels.add(level_str)

                # Only add BP to sets if NOT an outlier
                if bp and bp > 0 and not is_outlier:
                    all_bps.add(bp)

                    if level_str:
                        if level_str not in level_bp_map:
                            level_bp_map[level_str] = []
                        level_bp_map[level_str].append(bp)

        # Sort levels: 1, 2, ... 9, 9+, 10, 10+, 11, 11+, 12
        def level_sort_key(lvl):
            try:
                base = int(lvl.replace('+', ''))
                is_plus = '+' in lvl
                return base + (0.5 if is_plus else 0)
            except ValueError:
                return 99

        self.available_levels = sorted(list(all_levels), key=level_sort_key)
        self.available_bps = sorted(list(all_bps))

        # Calculate min/max BP for each level
        self.level_boundaries = {}
        for level_str, bp_list in level_bp_map.items():
            if bp_list:
                self.level_boundaries[level_str] = {
                    'min': min(bp_list),
                    'max': max(bp_list)
                }
