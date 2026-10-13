"""
Statistics 탭 비즈니스 로직.

데이터 로딩, 필터링, 정렬, 아이템 빌드를 담당한다.
PyQt6 의존 없이 순수 Python으로 구현된다.
"""
import math
import os
import re
from dataclasses import dataclass
from datetime import datetime
from models.potential import calculate_potential, calculate_total_potential
from services.score_query_service import (
    get_best_scores_per_chart, get_play_counts,
    get_this_year_play_counts
)
from repositories.song_repository import get_all_songs_with_charts, get_db_path
from models.constants import (
    calculate_rank,
    DIFFICULTY_ORDER, DIFFICULTY_NAMES, SCORE_RANKS,
    CLEAR_TYPE_TEXTS, CLEAR_TYPE_ABBREVIATIONS
)
from utils.configuration import config
from services.pack_service import PackService


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
    hard_bpm: str
    score_min_rank: int
    score_max_rank: int
    clear_types: list  # [int]
    include_inscribed: bool = True


class _ReverseCompare:
    """Helper class to invert comparison order of wrapped values in descending sorts."""
    __slots__ = ('val',)

    def __init__(self, val):
        self.val = val

    def __lt__(self, other):
        return self.val > other.val

    def __gt__(self, other):
        return self.val < other.val

    def __eq__(self, other):
        return self.val == other.val

    def __le__(self, other):
        return self.val >= other.val

    def __ge__(self, other):
        return self.val <= other.val


class StatisticsService:
    """Statistics 탭 비즈니스 로직: 데이터 로딩, 필터링, 정렬, 아이템 빌드."""

    def __init__(self):
        # 데이터 캐시
        self.songs_data = {}
        self.songs_by_db_id = {}
        self.scores_data = {}
        self.play_counts = {}
        self.this_year_play_counts = {}
        self.is_songs_db_available = True

        # 중간 결과 캐시
        self._full_items_cache = None
        self._full_items_cache_key = None
        self._filtered_items_cache = None
        self._filtered_cache_key = None
        self._pack_items_cache = None
        self._pack_cache_key = None
        self._base_pack_items_cache = None
        self._base_pack_cache_key = None

        # 팩 서비스 연동
        self.pack_service = PackService()
        self._main_pack_index = None

        # Level/BP 경계
        self.available_levels = []
        self.available_bps = []
        self.level_boundaries = {}

        # 전역 potential 순위 맵: (arcaea_id, difficulty) → rank (1-based, 0=미플레이)
        self._potential_rank_map: dict = {}
        # Arcaea 7.0 상위 10개 슬롯 (Best 10) 튜플 집합: {(arcaea_id, difficulty), ...}
        self._best10_slots: set = set()

    @staticmethod
    def _normalize_level(level) -> str:
        """Normalize level text for consistent backend->QML contract."""
        return str(level or "").strip()

    @staticmethod
    def _parse_bpm_for_sort(bpm, ascending: bool = True) -> float:
        """Extract a numeric sort key from a BPM string.

        - No BPM: sorts last (inf ascending, -inf descending)
        - Range e.g. "35-400": min value ascending, max value descending
        - Text e.g. "170?", "195✝": extracts first numeric value
        """
        if not bpm:
            return float('inf') if ascending else float('-inf')
        nums = re.findall(r'\d+(?:\.\d+)?', str(bpm))
        if not nums:
            return float('inf') if ascending else float('-inf')
        vals = [float(n) for n in nums]
        if len(vals) >= 2:
            return min(vals) if ascending else max(vals)
        return vals[0]

    @staticmethod
    def _parse_version_for_sort(version_str, ascending: bool = True) -> tuple:
        """Extract numeric version tuple for sorting.

        - No version: sorts last (inf ascending, -inf descending)
        - Normal e.g. "7.0.0", "3.12.10", "1.5": parses as tuple of integers padded to 3 parts.
        """
        if not version_str:
            last = float('inf') if ascending else float('-inf')
            return (last, last, last)
        nums = re.findall(r'\d+', str(version_str))
        if not nums:
            last = float('inf') if ascending else float('-inf')
            return (last, last, last)
        int_nums = [int(n) for n in nums]
        while len(int_nums) < 3:
            int_nums.append(0)
        return tuple(int_nums)

    @staticmethod
    def _effective_note_count(chart_data: dict, score_data: dict) -> int:
        """Note count for sorting/display.

        Prefers the stored chart note_count; if that's missing, falls back to
        pure+far+lost from an actual play record; otherwise 0.
        """
        note_count = chart_data.get('note_count', 0)
        if note_count > 0:
            return note_count
        if score_data.get('time_played', 0) > 0:
            return (
                score_data.get('perfect', 0)
                + score_data.get('near', 0)
                + score_data.get('miss', 0)
            )
        return 0

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

        # Check songs.db availability
        try:
            db_path = get_db_path()
            db_exists = bool(db_path and os.path.exists(db_path))
        except Exception:
            db_exists = False
        self.is_songs_db_available = bool(db_exists and raw_songs)

        # In-memory artist 백필 및 동적 가상 차트(Virtual Chart) 합성
        aid_to_songs = {}
        for s in self.songs_data.values():
            aid = s.get('arcaea_id')
            if aid:
                aid_to_songs.setdefault(aid, []).append(s)

        # Fallback/신곡 보완: scores_data에는 존재하지만 songs_data에 없는 arcaea_id가 있다면 가상 악곡 합성
        next_synth_id = (max([k for k in self.songs_data.keys() if isinstance(k, int)], default=0) + 1)
        for (aid, diff), scdata in self.scores_data.items():
            if aid not in aid_to_songs:
                t_en = str(scdata.get('title_en') or '').strip()
                t_jp = str(scdata.get('title_jp') or '').strip()
                artist = str(scdata.get('artist') or '').strip() or 'Unknown'
                title = (t_jp or t_en) if lang == 'jp' else (t_en or t_jp)
                if not title:
                    title = aid
                synth_song = {
                    'song_db_id': next_synth_id,
                    'arcaea_id': aid,
                    'canonical_title': title,
                    'title_en': t_en or aid,
                    'title_jp': t_jp,
                    'title': title,
                    'artist': artist,
                    'length': 0,
                    'bpm': '-',
                    'pack': 'Uncategorized',
                    'pack_abbr': '???',
                    'version': '-',
                    'charts': {}
                }
                self.songs_data[next_synth_id] = synth_song
                self.songs_by_db_id[next_synth_id] = synth_song
                aid_to_songs[aid] = [synth_song]
                next_synth_id += 1

        for (aid, diff), scdata in self.scores_data.items():
            songs_for_aid = aid_to_songs.get(aid, [])
            if not songs_for_aid:
                continue

            # 동일 arcaea_id를 공유하는 악곡들(예: dropdead 본편 vs overdead.) 중 해당 diff를 소유한 곡을 특정
            matching_songs = [s for s in songs_for_aid if diff in s.get('charts', {})]
            target_songs = matching_songs if matching_songs else songs_for_aid

            for song_item in target_songs:
                # 1. Artist 백필 (songs.db artist 결측 시 user_scores.db의 artist 주입)
                curr_artist = str(song_item.get('artist') or '').strip()
                sc_artist = str(scdata.get('artist') or '').strip()
                if (not curr_artist or curr_artist.lower() == 'unknown') and sc_artist:
                    song_item['artist'] = sc_artist

                # 1.1 Title 백필 (title이 결측이거나 미분류 합성곡 arcaea_id인 경우 user_scores.db의 title_en/title_jp 주입)
                curr_title = str(song_item.get('title') or '').strip()
                curr_canonical = str(song_item.get('canonical_title') or '').strip()
                sc_en = str(scdata.get('title_en') or '').strip()
                sc_jp = str(scdata.get('title_jp') or '').strip()
                sc_title = (sc_jp or sc_en) if lang == 'jp' else (sc_en or sc_jp)

                is_title_missing = not curr_title or curr_title.lower() == 'unknown'
                # 가상 합성 곡 등으로 canonical_title마저 aid인 경우에만 arcaea_id 대체로 간주
                is_synthetic_aid = (curr_title == aid and (not curr_canonical or curr_canonical == aid))

                if (is_title_missing or is_synthetic_aid) and sc_title:
                    song_item['title'] = sc_title
                    if not curr_canonical or curr_canonical == aid:
                        song_item['canonical_title'] = sc_title
                    if sc_en and not song_item.get('title_en'):
                        song_item['title_en'] = sc_en
                    if sc_jp and not song_item.get('title_jp'):
                        song_item['title_jp'] = sc_jp

            # 2. 동적 가상 차트 합성 (charts 테이블에 없는 신곡 난이도 보완)
            # 동일 arcaea_id를 공유하는 악곡들(예: ignotus 본편 vs BYD) 중 어느 한 악곡이라도 해당 diff를 소유하고 있다면 가상 차트 합성 건너뜀
            has_chart_already = any(diff in s.get('charts', {}) for s in songs_for_aid)
            if not has_chart_already:
                target_song = songs_for_aid[0]
                charts = target_song.setdefault('charts', {})
                perfect = scdata.get('perfect', 0) or 0
                near = scdata.get('near', 0) or 0
                miss = scdata.get('miss', 0) or 0
                note_cnt = perfect + near + miss
                charts[diff] = {
                    'level': '?',
                    'bp': 0.0,
                    's_bp': 0.0,
                    'perceived_bp': 0.0,
                    'note_count': note_cnt,
                    'ignore_chart': False,
                    'skill_issues': False,
                    'hard_bpm': False,
                    'cut_200': 0,
                    'is_inscribed': False,
                    'version': target_song.get('version') or '',
                    'is_virtual': True,
                }

        # Calculate Level/BP boundaries
        self._calculate_level_bp_boundaries()

        # Compute global potential rankings across all played charts
        self._rebuild_potential_ranks()

        # 데이터 원본이 바뀌었으므로 중간 캐시는 전부 무효화
        self.invalidate_caches()

    def _rebuild_potential_ranks(self):
        """전체 플레이 기록을 potential 및 타이브레이커 기준 내림차순 정렬하여 순위를 매기고 Best 10 슬롯을 판정한다."""
        entries = []
        for song_data in self.songs_data.values():
            arcaea_id = song_data.get('arcaea_id', '')
            if not arcaea_id:
                continue
            for diff, chart_data in song_data.get('charts', {}).items():
                score_data = self.scores_data.get((arcaea_id, diff), {})
                if not score_data or score_data.get('time_played', 0) <= 0:
                    continue
                clear_type = score_data.get('clear_type', 0)
                potential = calculate_potential(
                    chart_data.get('bp', 0),
                    chart_data.get('note_count', 0),
                    score_data.get('score', 0),
                    score_data.get('shiny_perfect', 0),
                    is_cleared=(clear_type != 0),
                )
                if potential is not None:
                    entries.append((
                        arcaea_id,
                        diff,
                        potential,
                        score_data.get('score', 0),
                        score_data.get('time_played', 0),
                    ))

        # 타이브레이커: potential 내림차순 -> score 내림차순 -> time_played 내림차순 -> arcaea_id 오름차순 -> diff 오름차순
        entries.sort(key=lambda x: (-x[2], -x[3], -x[4], x[0], x[1]))

        self._potential_rank_map = {}
        self._best10_slots = set((e[0], e[1]) for e in entries[:10])

        for idx, entry in enumerate(entries):
            arcaea_id, diff, *_ = entry
            self._potential_rank_map[(arcaea_id, diff)] = idx + 1

    def is_inscribed_unlocked(self) -> bool:
        """
        DEINOS PHAINEIN의 Inscribed(BYD, difficulty=3) 차트에 플레이 기록이 존재하는지 확인한다.
        """
        score_data = self.scores_data.get(('deinosphainein', 3), {})
        return (score_data.get('score', 0) > 0) or (score_data.get('time_played', 0) > 0)

    def has_any_inscribed_played(self) -> bool:
        """
        Inscribed 차트(difficulty=3, is_inscribed=1) 중 하나라도 플레이 기록(score > 0 또는 time_played > 0)이 존재하는지 확인한다.
        """
        for song_data in self.songs_data.values():
            arcaea_id = song_data.get('arcaea_id', '')
            if not arcaea_id:
                continue
            chart_3 = song_data.get('charts', {}).get(3, {})
            if chart_3.get('is_inscribed', 0):
                score_data = self.scores_data.get((arcaea_id, 3), {})
                if (score_data.get('score', 0) > 0) or (score_data.get('time_played', 0) > 0):
                    return True
        return False

    def get_user_total_potential(self, fixed_denominator: bool = True) -> float:
        """
        현재 사용자의 최고 성적 기반 Arcaea 7.0 최종 포텐셜 (B50 + B10)을 반환한다.
        """
        potentials = []
        for song_data in self.songs_data.values():
            arcaea_id = song_data.get('arcaea_id', '')
            if not arcaea_id:
                continue
            for diff, chart_data in song_data.get('charts', {}).items():
                score_data = self.scores_data.get((arcaea_id, diff), {})
                if not score_data or score_data.get('time_played', 0) <= 0:
                    continue
                clear_type = score_data.get('clear_type', 0)
                pot = calculate_potential(
                    chart_data.get('bp', 0),
                    chart_data.get('note_count', 0),
                    score_data.get('score', 0),
                    score_data.get('shiny_perfect', 0),
                    is_cleared=(clear_type != 0),
                )
                if pot is not None and pot >= 0.0:
                    potentials.append(pot)

        return calculate_total_potential(potentials, fixed_denominator=fixed_denominator)

    def invalidate_caches(self):
        """중간 결과 캐시를 모두 무효화한다."""
        self._full_items_cache = None
        self._full_items_cache_key = None
        self._filtered_items_cache = None
        self._filtered_cache_key = None
        self._pack_items_cache = None
        self._pack_cache_key = None
        self._base_pack_items_cache = None
        self._base_pack_cache_key = None
        self._main_pack_index = None

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

    def get_pack_items(
        self,
        filters: FilterParams = None,
        sort_mode: str = "version",
        sort_ascending: bool = False,
        song_sort_mode: str = None,
        song_sort_ascending: bool = None,
        search_text: str = "",
        classification_mode: str = None
    ) -> list:
        """
        Pack 모드용 팩 집계 아이템 리스트 반환 (캐싱, 정렬, 검색 지원).
        """
        if classification_mode is None:
            try:
                classification_mode = config['general']['pack_classification_mode']
            except Exception:
                classification_mode = "strict"

        # sort_mode 정규화
        PACK_SORT_MODES = {
            'version', 'title', 'score', 'potential', 'max', 'play_count',
            'total_play_count', 'this_year_play_count', 'recent_played',
            'level', 'bp', 's_bp', 'perceived_bp', 'note_count', 'bpm', 'length'
        }
        norm_sort_mode = (sort_mode or "version").strip().lower()
        if norm_sort_mode in ('total_play', 'total_plays', 'play_count'):
            norm_sort_mode = 'total_play_count'
        elif norm_sort_mode in ('bp',):
            norm_sort_mode = 'level'
        elif norm_sort_mode not in PACK_SORT_MODES:
            norm_sort_mode = 'version'

        # version 정렬 시 팩 내 악곡은 bp 내림차순 정렬, 대표곡 정렬 시에도 동기화
        if song_sort_mode is not None:
            eff_song_sort_mode = song_sort_mode
            eff_song_sort_asc = bool(song_sort_ascending) if song_sort_ascending is not None else False
        elif norm_sort_mode == "version":
            eff_song_sort_mode = "bp"
            eff_song_sort_asc = False
        else:
            eff_song_sort_mode = norm_sort_mode
            eff_song_sort_asc = sort_ascending

        # 캐시 키 검사
        filter_hash = self._make_filter_hash(filters) if filters else None
        clean_search = (search_text or "").strip().lower()
        excluded_packs, _ = self._get_pack_exclusion_settings()
        excluded_packs_tuple = tuple(sorted(excluded_packs))
        base_cache_key = (
            filter_hash,
            norm_sort_mode,
            bool(sort_ascending),
            eff_song_sort_mode,
            bool(eff_song_sort_asc),
            classification_mode,
            excluded_packs_tuple,
        )
        cache_key = (
            filter_hash,
            norm_sort_mode,
            bool(sort_ascending),
            eff_song_sort_mode,
            bool(eff_song_sort_asc),
            clean_search,
            classification_mode,
            excluded_packs_tuple,
        )

        # 1. Base packs 캐시 확인 및 집계
        if self._base_pack_cache_key == base_cache_key and self._base_pack_items_cache is not None:
            packs = self._base_pack_items_cache
        else:
            packs = self.pack_service.get_packs(
                songs_data=self.songs_data,
                scores_data=self.scores_data,
                play_counts=self.play_counts,
                this_year_play_counts=self.this_year_play_counts,
                classification_mode=classification_mode,
                active_filters=filters,
                sort_mode=norm_sort_mode,
                is_desc=(not sort_ascending),
                song_sort_mode=eff_song_sort_mode,
                song_is_desc=(not eff_song_sort_asc),
                potential_rank_map=self._potential_rank_map,
                excluded_packs=excluded_packs,
            )
            self._base_pack_items_cache = packs
            self._base_pack_cache_key = base_cache_key

        # 2. 검색어가 없으면 Base packs 캐시 결과를 그대로 반환
        if not clean_search:
            self._pack_items_cache = packs
            self._pack_cache_key = cache_key
            return packs

        # 3. 검색어가 있는 경우 검색 캐시 확인
        if self._pack_cache_key == cache_key and self._pack_items_cache is not None:
            return self._pack_items_cache

        # 4. In-memory 빠른 검색 필터링 (팩명 매칭 또는 수록곡 매칭 팩 보존)
        filtered_packs = []
        for pack in packs:
            pack_name = str(pack.get('name') or '').lower()
            pack_abbr = str(pack.get('abbr') or '').lower()
            if clean_search in pack_name or clean_search in pack_abbr:
                filtered_packs.append(pack)
                continue

            song_matched = False
            for s in pack.get('songs', []):
                title = str(s.get('title') or '').lower()
                artist = str(s.get('artist') or '').lower()
                song_id = str(s.get('id') or s.get('song_id') or '').lower()
                raw = s.get('raw_data') or {}
                raw_canonical = str(raw.get('canonical_title') or '').lower()
                raw_en = str(raw.get('title_en') or '').lower()
                raw_jp = str(raw.get('title_jp') or '').lower()
                if (
                    clean_search in title
                    or clean_search in artist
                    or clean_search in song_id
                    or clean_search in raw_canonical
                    or clean_search in raw_en
                    or clean_search in raw_jp
                ):
                    song_matched = True
                    break

            if song_matched:
                filtered_packs.append(pack)

        self._pack_items_cache = filtered_packs
        self._pack_cache_key = cache_key
        return filtered_packs

    def build_song_item(self, song_data: dict, filters: FilterParams = None) -> dict:
        """단일 곡에 대한 Song 모드 아이템을 빌드한다."""
        if not song_data:
            return None
        song_db_id = song_data.get('song_db_id') or song_data.get('id')
        arcaea_id = song_data.get('arcaea_id')
        if not arcaea_id:
            return None

        filtered_diffs = []
        for diff, chart_data in song_data.get('charts', {}).items():
            if filters is None:
                filtered_diffs.append(diff)
                continue
            score_data = self.scores_data.get((arcaea_id, diff), {})
            if self._matches_filter(chart_data, score_data, diff, filters):
                filtered_diffs.append(diff)

        # 필터 매칭 난이도가 없을 경우 전체 난이도로 fallback
        if not filtered_diffs:
            filtered_diffs = list(song_data.get('charts', {}).keys())

        return self._build_song_item(song_db_id, arcaea_id, song_data, filtered_diffs, filters)

    def _get_pack_exclusion_settings(self):
        """설정에서 제외 팩 세트와 팩 분류 모드를 가져온다."""
        try:
            classification_mode = config['general']['pack_classification_mode']
        except Exception:
            classification_mode = 'strict'
        try:
            excluded_packs = set(config['general']['excluded_packs'])
        except Exception:
            excluded_packs = set()
        return excluded_packs, classification_mode

    @property
    def main_pack_index(self):
        if not hasattr(self, '_main_pack_index') or self._main_pack_index is None:
            if self.songs_data:
                self._main_pack_index = self.pack_service.build_main_pack_index(self.songs_data)
            else:
                self._main_pack_index = {}
        return self._main_pack_index

    def _is_pack_excluded(self, song_data: dict, excluded_packs: set, classification_mode: str) -> bool:
        """곡의 팩이 제외 대상인지 판정 (Strict 및 Conceptual 모드 종속 Append 팩 포함)."""
        if not excluded_packs or not song_data:
            return False
        raw_pack = song_data.get('pack', '')
        if raw_pack in excluded_packs:
            return True
        if classification_mode == 'conceptual':
            raw_abbr = song_data.get('pack_abbr', '')
            norm_name, _ = self.pack_service.parse_pack_info(
                raw_pack, raw_abbr, 'conceptual', main_pack_index=self.main_pack_index
            )
            if norm_name in excluded_packs:
                return True
        return False

    def build_full_items(self, display_mode: str, filters: FilterParams = None) -> list:
        """필터 전(Chart) 또는 필터 반영 집계(Song) 기준의 전체 아이템을 빌드한다."""
        excluded_packs, classification_mode = self._get_pack_exclusion_settings()
        excluded_packs_tuple = tuple(sorted(excluded_packs))
        cache_key = self._make_full_items_cache_key(
            display_mode, filters, excluded_packs_tuple, classification_mode
        )
        if self._full_items_cache_key == cache_key and self._full_items_cache is not None:
            return self._full_items_cache

        if display_mode == "chart":
            items = self._build_all_chart_items(excluded_packs, classification_mode)
        else:
            items = self._build_all_song_items(filters, excluded_packs, classification_mode)

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
        # MAX 정렬은 "MAX에 가까울수록 높다"는 직관에 맞추기 위해 방향을 반전한다.
        # (미기록 항목은 방향과 무관하게 항상 하단에 유지된다.)
        effective_ascending = not sort_ascending if sort_mode == "max" else sort_ascending
        return sorted(
            items,
            key=lambda item: self._get_sort_key(item, sort_mode, effective_ascending),
            reverse=not effective_ascending,
        )

    def apply_display_values(self, items: list, sort_mode: str, display_mode: str):
        """정렬된 리스트의 displayValue를 in-place로 갱신한다."""
        for item in items:
            item['displayValue'] = self._format_display_value(
                item, sort_mode, display_mode
            )

    def _make_full_items_cache_key(
        self, display_mode: str, filters: FilterParams,
        excluded_packs: tuple = (), classification_mode: str = "strict"
    ):
        """Song 모드는 필터에 따라 집계가 달라지므로 필터 해시를 캐시 키에 포함한다."""
        if display_mode == "song":
            return (display_mode, self._make_filter_hash(filters), excluded_packs, classification_mode)
        return (display_mode, excluded_packs, classification_mode)

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
            str(filters.hard_bpm),
            int(filters.score_min_rank),
            int(filters.score_max_rank),
            tuple(sorted(int(v) for v in (filters.clear_types or []))),
            bool(getattr(filters, 'include_inscribed', True)),
        )

    def _build_all_chart_items(
        self, excluded_packs: set = None, classification_mode: str = None
    ) -> list:
        """Chart 모드용 전체 차트 아이템을 빌드한다 (필터 비의존, 제외 팩 반영)."""
        items = []
        for song_db_id, song_data in self.songs_data.items():
            if self._is_pack_excluded(song_data, excluded_packs, classification_mode):
                continue

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

    def _build_all_song_items(
        self, filters: FilterParams = None,
        excluded_packs: set = None, classification_mode: str = None
    ) -> list:
        """Song 모드용 집계 아이템을 빌드한다 (제외 팩 반영)."""
        items = []
        for song_db_id, song_data in self.songs_data.items():
            if self._is_pack_excluded(song_data, excluded_packs, classification_mode):
                continue

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
        if difficulty == 3:
            is_ins = bool(item.get('isInscribed', False))
            if is_ins:
                if not getattr(filters, 'include_inscribed', True):
                    return False
            else:
                if 3 not in filters.difficulties:
                    return False
        elif difficulty not in filters.difficulties:
            return False

        level_str = item.get('level', '0')
        if level_str != '?':
            if filters.bp_mode:
                bp = item.get('bp', 0)
                if bp < filters.bp_min or bp > filters.bp_max:
                    return False
            else:
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
            ('hardBpm', filters.hard_bpm),
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
            item.get('cut200', None),
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
        # Difficulty filter (Arcaea 7.0 Inscribed 호환)
        if difficulty == 3:
            is_ins = bool(chart_data.get('is_inscribed', False))
            if is_ins:
                if not getattr(filters, 'include_inscribed', True):
                    return False
            else:
                if 3 not in filters.difficulties:
                    return False
        elif difficulty not in filters.difficulties:
            return False

        # Level/BP range filter ('?' 레벨 차트는 범위 필터에 항상 포함)
        level_str = chart_data.get('level', '0')
        if level_str != '?':
            if filters.bp_mode:
                bp = chart_data.get('bp', 0)
                if bp < filters.bp_min or bp > filters.bp_max:
                    return False
            else:
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
            ('skill_issues', filters.skill_issues),
            ('hard_bpm', filters.hard_bpm),
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
        cut_200 = chart_data.get('cut_200', None) if chart_data else None
        rank_idx = self.get_score_rank_index(score, has_score, score_below_max, cut_200)
        if rank_idx < filters.score_min_rank or rank_idx > filters.score_max_rank:
            return False

        return True

    def get_score_rank_index(self, score, has_score=None, score_below_max=None, cut_200=None) -> int:
        """Convert a score to its rank index in SCORE_RANKS.

        Args:
            score: The score value
            has_score: If True, score=0 means 'D' grade (Track Lost). If None, falls back to score > 0 check.
            score_below_max: If 0, the score is MAX (all shiny perfects). If None, PM/FRAME/MAX are not distinguished.
            cut_200: Frame-limited offset (<=0) from Consultant Sheet. FRAME when score_below_max + cut_200 <= 0.
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
            return 12  # 'MAX'
        elif (score_below_max is not None and cut_200 is not None
              and score_below_max + cut_200 <= 0):
            return 11  # 'FRAME' (frame-limited max 도달, but not a full MAX)
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
        clear_type = score_data.get('clear_type', 0)

        is_inscribed = bool(chart_data.get('is_inscribed', False)) and difficulty == 3
        is_unlocked = self.is_inscribed_unlocked()
        if is_inscribed:
            diff_name = 'INS' if is_unlocked else '???'
            diff_color_tag = 'ins'
        else:
            diff_name = DIFFICULTY_NAMES.get(difficulty, '')
            diff_color_tag = DIFFICULTY_NAMES.get(difficulty, '').lower()

        strict_pack, strict_abbr = PackService.parse_pack_info(
            song_data.get('pack', ''), song_data.get('pack_abbr', ''), classification_mode="strict"
        )

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
            'pack': strict_pack,
            'packAbbr': strict_abbr,
            'strictPack': strict_pack,
            'strictPackAbbr': strict_abbr,
            'version': chart_data.get('version') or song_data.get('version', ''),
            'songVersion': song_data.get('version', ''),
            'packColor': song_data.get('pack_color', ''),
            'difficulty': difficulty,
            'difficultyName': diff_name,
            'diffColorTag': diff_color_tag,
            'isInscribed': is_inscribed,
            'level': chart_data.get('level', ''),
            'bp': chart_data.get('bp', 0),
            's_bp': chart_data.get('s_bp', 0),
            'perceived_bp': chart_data.get('perceived_bp', 0),
            'noteCount': self._effective_note_count(chart_data, score_data),
            'bestScore': score,
            'hasScore': has_score,
            'rank': rank,
            'clearTypeText': CLEAR_TYPE_TEXTS.get(best_clear_type, '') if has_score else '',
            'clearTypeAbbr': CLEAR_TYPE_ABBREVIATIONS.get(best_clear_type, '') if has_score else '',
            'pure': score_data.get('perfect', 0),
            'shinyPure': score_data.get('shiny_perfect', 0),
            'far': score_data.get('near', 0),
            'lost': score_data.get('miss', 0),
            'clearType': clear_type,
            'bestClearType': best_clear_type,
            'timePlayed': time_played,
            'lastPlayedDate': self._format_full_datetime(time_played),
            'scoreBelowMax': score_data.get('score_below_max', 0),
            'cut200': chart_data.get('cut_200', 0),
            'ignoreChart': chart_data.get('ignore_chart', False),
            'skillIssues': chart_data.get('skill_issues', False),
            'hardBpm': chart_data.get('hard_bpm', False),
            'totalPlayCount': play_count,
            'thisYearPlayCount': this_year_play_count,
            'songTotalPlayCount': song_total_play_count,
            'potential': calculate_potential(
                chart_data.get('bp', 0),
                chart_data.get('note_count', 0),
                score,
                score_data.get('shiny_perfect', 0),
                is_cleared=(clear_type != 0),
            ) if has_score else None,
            'potentialRank': self._potential_rank_map.get((arcaea_id, difficulty), 0),
            'isBest10': (arcaea_id, difficulty) in self._best10_slots,
            'displayValue': '',  # Will be set based on sort mode
        }

    def _build_difficulty_summary(self, difficulty, chart_data, score_data: dict, arcaea_id: str = '') -> dict:
        """Build lightweight difficulty summary for song list delegate."""
        has_score = score_data.get('time_played', 0) > 0
        is_inscribed = bool(chart_data.get('is_inscribed', False)) and difficulty == 3
        is_unlocked = self.is_inscribed_unlocked()
        if is_inscribed:
            diff_name = 'INS' if is_unlocked else '???'
            diff_color_tag = 'ins'
        else:
            diff_name = DIFFICULTY_NAMES.get(difficulty, '')
            diff_color_tag = DIFFICULTY_NAMES.get(difficulty, '').lower()

        return {
            'difficulty': difficulty,
            'difficultyName': diff_name,
            'diffColorTag': diff_color_tag,
            'isInscribed': is_inscribed,
            'level': chart_data.get('level', ''),
            'ignoreChart': chart_data.get('ignore_chart', False),
            'skillIssues': chart_data.get('skill_issues', False),
            'hardBpm': chart_data.get('hard_bpm', False),
            'score': score_data.get('score', 0),
            'hasScore': has_score,
            'version': chart_data.get('version', ''),
            'potentialRank': self._potential_rank_map.get((arcaea_id, difficulty), 0),
            'isBest10': bool(arcaea_id) and (arcaea_id, difficulty) in self._best10_slots,
        }

    def _build_song_item(self, song_db_id, arcaea_id, song_data, filtered_difficulties, filters: FilterParams = None) -> dict:
        """Build a song item aggregating filtered difficulties."""
        # Find best values among filtered difficulties
        best_level = ""
        best_bp = 0
        best_s_bp = 0
        best_perceived_bp = 0
        best_note_count = 0
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
        best_diff_for_note_count = -1
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

            diff_details.append(self._build_difficulty_summary(diff, chart_data, score_data, arcaea_id=arcaea_id))

            # Track best potential
            if has_score:
                p = calculate_potential(
                    chart_data.get('bp', 0),
                    chart_data.get('note_count', 0),
                    score,
                    shiny_pure,
                    is_cleared=(score_data.get('clear_type', 0) != 0),
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
            chart_note_count = self._effective_note_count(chart_data, score_data)
            if chart_note_count > best_note_count:
                best_note_count = chart_note_count
                best_diff_for_note_count = diff

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

        # Strict pack metadata for header and drill-down
        strict_pack, strict_abbr = PackService.parse_pack_info(
            song_data.get('pack', ''), song_data.get('pack_abbr', ''), classification_mode="strict"
        )

        return {
            'songDbId': song_db_id,
            'arcaeaId': arcaea_id,
            'title': song_data['title'],
            'canonical_title': song_data.get('canonical_title', ''),
            'title_en': song_data.get('title_en', ''),
            'title_jp': song_data.get('title_jp', ''),
            'artist': song_data['artist'],
            'length': song_data.get('length', 0),
            'bpm': song_data.get('bpm', ''),
            'pack': strict_pack,
            'packAbbr': strict_abbr,
            'strictPack': strict_pack,
            'strictPackAbbr': strict_abbr,
            'version': song_data.get('version', ''),
            'packColor': song_data.get('pack_color', ''),
            'level': best_level,
            'bp': best_bp,
            's_bp': best_s_bp,
            'perceived_bp': best_perceived_bp,
            'noteCount': best_note_count,
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
            'bestDiffForNoteCount': best_diff_for_note_count,
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

    def _get_sort_key(self, item, sort_mode, sort_ascending: bool = True):
        """Get the sort key based on sort mode."""
        _last = float('inf') if sort_ascending else float('-inf')

        if sort_mode == "title":
            return item.get('title', '').lower()
        elif sort_mode == "score":
            has_score = item.get('hasScore', False)
            if not has_score:
                return (_last, 0)
            return (0, item.get('bestScore', 0))
        elif sort_mode == "max":
            if not item.get('hasScore', False):
                return (_last, _last)
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
            ts = item.get('timePlayed', 0)
            if not ts or ts <= 0:
                return _last
            return ts
        elif sort_mode == "level":
            if item.get('level') == '?':
                return _last
            bp = item.get('bp', 0)
            if not bp or bp <= 0:
                return _last
            return bp
        elif sort_mode == "s_bp":
            s_bp = item.get('s_bp', 0)
            if not s_bp or s_bp <= 0:
                return _last
            return s_bp
        elif sort_mode == "perceived_bp":
            perceived_bp = item.get('perceived_bp', 0)
            if not perceived_bp or perceived_bp <= 0:
                return _last
            return perceived_bp
        elif sort_mode == "potential":
            has_score = item.get('hasScore', False)
            potential = item.get('potential') if 'potential' in item else item.get('bestPotential')
            if not has_score or potential is None:
                return (_last, _last)
            return (0, potential)
        elif sort_mode == "length":
            length = item.get('length', 0)
            if not length or length <= 0:
                return _last
            return length
        elif sort_mode == "bpm":
            return self._parse_bpm_for_sort(item.get('bpm', ''), sort_ascending)
        elif sort_mode == "note_count":
            note_count = item.get('noteCount', 0)
            if not note_count or note_count <= 0:
                return _last
            return note_count
        elif sort_mode == "version":
            ver_tuple = self._parse_version_for_sort(item.get('version'), sort_ascending)
            pack = (item.get('pack') or item.get('packAbbr') or '').strip()
            bp = float(item.get('bp', 0) or 0)
            title = (item.get('title') or '').strip().lower()

            if not sort_ascending:
                # Descending (reverse=True): larger key comes first
                # 1. Version: (7, 0, 0) > (1, 0, 0)
                # 2. Pack: A > Z -> _ReverseCompare
                pack_key = (0, _ReverseCompare(pack.lower())) if pack else (-1, _ReverseCompare(''))
                # 3. BP: 12.0 > 9.0
                bp_key = bp
                # 4. Title: A > Z -> _ReverseCompare
                title_key = _ReverseCompare(title)
                return (ver_tuple, pack_key, bp_key, title_key)
            else:
                # Ascending (reverse=False): smaller key comes first
                # 1. Version: (1, 0, 0) < (7, 0, 0)
                # 2. Pack: A < Z -> normal lowercase
                pack_key = (0, pack.lower()) if pack else (1, '')
                # 3. BP: 12.0 comes first -> -12.0 < -9.0
                bp_key = -bp
                # 4. Title: A comes first -> normal lowercase
                title_key = title
                return (ver_tuple, pack_key, bp_key, title_key)
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
            # 4자리 버림 (부동소수점 오차 보정)
            return f"{math.floor(potential * 10000 + 1e-6) / 10000:.4f}"
        elif sort_mode == "length":
            length = item.get('length', 0)
            if length <= 0:
                return "?"
            return f"{length // 60}:{length % 60:02d}"
        elif sort_mode == "bpm":
            bpm = item.get('bpm', '')
            return str(bpm) if bpm else "?"
        elif sort_mode == "note_count":
            note_count = item.get('noteCount', 0)
            return str(note_count) if note_count and note_count > 0 else "?"
        elif sort_mode == "version":
            ver = item.get('version')
            return str(ver) if ver else "-"
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

                if level_str and level_str != '?':
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
