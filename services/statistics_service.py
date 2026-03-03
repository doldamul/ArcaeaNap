"""
Statistics 탭 비즈니스 로직.

데이터 로딩, 필터링, 정렬, 아이템 빌드를 담당한다.
PyQt6 의존 없이 순수 Python으로 구현된다.
"""
from dataclasses import dataclass
from datetime import datetime
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
        self.scores_data = {}
        self.play_counts = {}
        self.this_year_play_counts = {}
        # Level/BP 경계
        self.available_levels = []
        self.available_bps = []
        self.level_boundaries = {}

    def load_data(self, cache_path: str):
        """DB에서 데이터 로딩 + 정규화. 경계 계산 포함."""
        # Load raw data
        raw_songs = get_all_songs_with_charts()
        raw_scores = get_best_scores_per_chart(cache_path)
        raw_play_counts = get_play_counts(cache_path)
        raw_this_year_play_counts = get_this_year_play_counts(cache_path)

        # Normalize songs data (ensure diff keys are int)
        self.songs_data = {}
        for sid, sdata in raw_songs.items():
            normalized_charts = {}
            for diff, cdata in sdata.get('charts', {}).items():
                try:
                    normalized_charts[int(diff)] = cdata
                except:
                    normalized_charts[diff] = cdata
            sdata['charts'] = normalized_charts
            self.songs_data[sid] = sdata

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

    def build_filtered_sorted_list(
        self, display_mode, sort_mode, sort_ascending,
        search_text, filters: FilterParams
    ) -> list:
        """필터링 → 정렬 → 아이템 빌드 → 표시값 설정. 완성된 리스트 반환."""
        items = []

        for song_id, song_data in self.songs_data.items():
            # Search filter
            if search_text:
                search_lower = search_text.lower()
                if (search_lower not in song_data['title'].lower() and
                    search_lower not in song_data['artist'].lower()):
                    continue

            arcaea_id = song_data.get('arcaea_id')

            # Get filtered difficulties for this song
            filtered_diffs = []
            for diff, chart_data in song_data.get('charts', {}).items():
                score_data = self.scores_data.get((arcaea_id, diff), {})
                if self._matches_filter(chart_data, score_data, diff, filters):
                    filtered_diffs.append(diff)

            if not filtered_diffs:
                continue

            if display_mode == "chart":
                # Add each chart as separate item
                for diff in DIFFICULTY_ORDER:
                    if diff not in filtered_diffs:
                        continue
                    chart_data = song_data['charts'].get(diff, {})
                    if chart_data:
                        item = self._build_chart_item(
                            arcaea_id, song_data, diff, chart_data, filters
                        )
                        # Add allDifficulties for detailed view
                        item['allDifficulties'] = self._build_all_difficulty_details(
                            arcaea_id, song_data, filters
                        )
                        items.append(item)
            else:
                # Add song with aggregated data
                item = self._build_song_item(
                    arcaea_id, song_data, filtered_diffs, filters
                )
                items.append(item)

        # Sort
        reverse = not sort_ascending
        items.sort(
            key=lambda item: self._get_sort_key(item, sort_mode),
            reverse=reverse
        )

        # Set display values
        for item in items:
            item['displayValue'] = self._format_display_value(
                item, sort_mode, display_mode
            )

        return items

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

    def _get_filtered_song_play_count(self, arcaea_id, song_data, filters: FilterParams) -> int:
        """Calculate total play count for FILTERED difficulties of a song.

        This sums play counts only for difficulties that pass the current filter,
        providing song-mode-style aggregation while respecting filter settings.
        Used for display in the detailed view header.
        """
        total = 0
        for diff, chart_data in song_data.get('charts', {}).items():
            score_data = self.scores_data.get((arcaea_id, diff), {})
            if self._matches_filter(chart_data, score_data, diff, filters):
                total += self.play_counts.get((arcaea_id, diff), 0)
        return total

    def _build_chart_item(self, arcaea_id, song_data, difficulty, chart_data, filters: FilterParams) -> dict:
        """Build a chart item for the list model."""
        score_data = self.scores_data.get((arcaea_id, difficulty), {})
        play_count = self.play_counts.get((arcaea_id, difficulty), 0)
        this_year_play_count = self.this_year_play_counts.get((arcaea_id, difficulty), 0)

        score = score_data.get('score', 0)
        time_played = score_data.get('time_played', 0)
        # hasScore: True if there's actual play data (time_played > 0 means a record exists)
        has_score = time_played > 0
        rank = calculate_rank(score) if has_score else ""
        best_clear_type = score_data.get('best_clear_type', 0)

        return {
            'arcaeaId': arcaea_id,
            'title': song_data['title'],
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
            'songTotalPlayCount': self._get_filtered_song_play_count(arcaea_id, song_data, filters),
            'displayValue': '',  # Will be set based on sort mode
        }

    def _build_song_item(self, arcaea_id, song_data, filtered_difficulties, filters: FilterParams) -> dict:
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

            chart_item = self._build_chart_item(arcaea_id, song_data, diff, chart_data, filters)
            diff_details.append(chart_item)

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

            if chart_item['bestScore'] > best_score:
                best_score = chart_item['bestScore']
                best_rank = chart_item['rank']
                best_diff_for_score = diff

            total_play_count += chart_item['totalPlayCount']
            total_this_year_play_count += chart_item['thisYearPlayCount']

            if chart_item['timePlayed'] > recent_time_played:
                recent_time_played = chart_item['timePlayed']
                best_diff_for_recent = diff

            # MAX sort: find chart with smallest (perfect + near + miss - shiny_perfect) value
            # Only consider charts that have been played (hasScore is True)
            if chart_item['hasScore']:
                chart_max_val = chart_item['pure'] + chart_item['far'] + chart_item['lost'] - chart_item['shinyPure']
                current_best_max_val = best_max_pure + best_max_far + best_max_lost - best_max_shiny
                # Use smallest value, or if first played chart
                if best_diff_for_max == -1 or chart_max_val < current_best_max_val or (chart_max_val == current_best_max_val and chart_item['scoreBelowMax'] < best_score_below_max):
                    best_score_below_max = chart_item['scoreBelowMax']
                    best_diff_for_max = diff
                    best_max_pure = chart_item['pure']
                    best_max_shiny = chart_item['shinyPure']
                    best_max_far = chart_item['far']
                    best_max_lost = chart_item['lost']

        # hasScore for song: True if any chart has been played
        has_score = recent_time_played > 0

        return {
            'arcaeaId': arcaea_id,
            'title': song_data['title'],
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
            'allDifficulties': self._build_all_difficulty_details(arcaea_id, song_data, filters),
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
        }

    def _build_all_difficulty_details(self, arcaea_id, song_data, filters: FilterParams) -> list:
        """Build details for ALL difficulties of a song, with isFiltered flag.

        Used for detailed view to show all difficulties regardless of filter.
        """
        all_details = []

        for diff in DIFFICULTY_ORDER:
            chart_data = song_data.get('charts', {}).get(diff)
            if not chart_data:
                continue

            score_data = self.scores_data.get((arcaea_id, diff), {})

            # Check if this chart is filtered out
            is_filtered = not self._matches_filter(chart_data, score_data, diff, filters)

            # Build the chart item
            chart_item = self._build_chart_item(arcaea_id, song_data, diff, chart_data, filters)
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
