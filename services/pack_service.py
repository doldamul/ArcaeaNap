"""
팩 분류 및 통계 집계 서비스 (PackService).

ArcaeaNap의 Pack 모드 백엔드 비즈니스 로직.
엄밀한 분류(Strict) vs 개념적 분류(Conceptual) 팩 매핑,
팩별 통계 산출(7단계 램프, FR.PM/CLR/ALL, FRAME 달성수, 최고 포텐셜, 최고 스코어 MAX 우선),
6대 팩 정렬 및 MAX 다계층 타이브레이커 지원.
PyQt6 의존 없이 순수 Python으로 구현된다.
"""
import math
import re
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple
from models.potential import calculate_potential
from models.constants import (
    DIFFICULTY_NAMES,
    DIFFICULTY_ORDER,
)


class PackService:
    """팩 분류, 통계 집계 및 정렬 서비스."""

    # 정규식 패턴 정의
    PAREN_PATTERN = re.compile(r"^(.+?)\s*\(\s*(.+?)\s*\)$")
    CHAPTER_PATTERN = re.compile(r"^(.+?)\s+Chapter\s+\d+$", re.IGNORECASE)
    CHAPTER_ABBR_PATTERN = re.compile(r"^(.+?)\s+\d+$")
    APPEND_PATTERN = re.compile(r"^(.+?)\s+Pack Append$", re.IGNORECASE)
    WORLD_EXTEND_PATTERN = re.compile(r"^(World\s+Extend|Extend\s+Archive)(?:\s+\d+)?$", re.IGNORECASE)

    # Strict 모드: 독립 Append 팩 명칭 및 축약형 매핑
    APPEND_STRICT_MAPPING: Dict[str, Tuple[str, str]] = {
        "CA": ("Crimson Astral", "CA"),
        "ST": ("Shared Time", "ST"),
        "LoS": ("Light of Salvation", "LoS"),
        "PT": ("Pale Tapestry", "PT"),
        "TJO": ("The Journey Onwards", "TJO"),
        "SV": ("Shifting Veil", "SV"),
    }

    # 난이도 풀네임 매핑 (PST -> Past, PRS -> Present, FTR -> Future, etc.)
    DIFF_FULL_NAMES: Dict[int, str] = {
        0: "Past",
        1: "Present",
        2: "Future",
        3: "Beyond",
        4: "Eternal",
    }

    # 표준 레벨 목록 (FilterParams level 비교용)
    AVAILABLE_LEVELS: List[str] = [
        '1', '2', '3', '4', '5', '6', '7', '7+', '8', '8+', '9', '9+',
        '10', '10+', '11', '11+', '12'
    ]

    def __init__(self, thumbnail_service: Optional[Any] = None):
        self.thumbnail_service = thumbnail_service

    @classmethod
    def build_main_pack_index(cls, songs_data: Any) -> Dict[str, Tuple[str, str]]:
        """
        songs_data(또는 songs.db)를 스캔하여 괄호나 Chapter/Append가 없는
        순수 본편 팩의 {pack_abbr: (pack_name, pack_abbr)} 동적 색인을 생성한다.
        """
        if not songs_data:
            return {}

        items = songs_data.values() if isinstance(songs_data, dict) else songs_data
        main_index: Dict[str, Tuple[str, str]] = {}

        for s in items:
            raw_pack = (s.get('pack') or '').strip()
            raw_abbr = (s.get('pack_abbr') or '').strip()
            if not raw_pack or not raw_abbr:
                continue

            # 괄호 팩, 챕터 팩, 어펜드 팩은 본편 색인 대상에서 제외
            if cls.PAREN_PATTERN.match(raw_abbr):
                continue
            if cls.CHAPTER_PATTERN.match(raw_pack):
                continue
            if cls.APPEND_PATTERN.match(raw_pack):
                continue

            if raw_abbr not in main_index:
                main_index[raw_abbr] = (raw_pack, raw_abbr)

        return main_index

    @classmethod
    def parse_pack_info(
        cls,
        pack: str,
        pack_abbr: str,
        classification_mode: str = "strict",
        main_pack_index: Optional[Dict[str, Tuple[str, str]]] = None,
    ) -> Tuple[str, str]:
        """
        'A ( B )', Chapter N, Pack Append 패턴 파싱 및 분류 모드(Strict vs Conceptual)에 따른 (pack_name, pack_abbr) 반환.
        고정 상수 딕셔너리 없이 main_pack_index(songs.db 동적 색인) 및 패턴 규칙에 의존한다.
        """
        raw_pack = (pack or "").strip()
        raw_abbr = (pack_abbr or "").strip()
        mode = (classification_mode or "strict").lower().strip()

        # pack 정보가 완전히 결측된 경우 "Uncategorized" 단일 팩으로 안전하게 수렴
        if not raw_pack:
            return ("Uncategorized", "???")

        # World Extend / Extend Archive는 항상 넘버링에 무관하게 독립 팩 원본 유지
        if cls.WORLD_EXTEND_PATTERN.match(raw_pack):
            return (raw_pack, raw_abbr)

        m_paren = cls.PAREN_PATTERN.match(raw_abbr)

        if mode == "conceptual":
            index = main_pack_index or {}

            # 1. Chapter 패턴: ... Chapter N -> 본편
            m_chap = cls.CHAPTER_PATTERN.match(raw_pack)
            if m_chap:
                m_abbr = cls.CHAPTER_ABBR_PATTERN.match(raw_abbr)
                parent_abbr = m_abbr.group(1).strip() if m_abbr else raw_abbr
                if parent_abbr in index:
                    return index[parent_abbr]
                parent_name = m_chap.group(1).strip()
                return (parent_name, parent_abbr)

            # 2. Pack Append 패턴: ... Pack Append -> 본편
            m_app = cls.APPEND_PATTERN.match(raw_pack)
            if m_app:
                prefix = m_app.group(1).strip()
                for a, (p, pa) in index.items():
                    if p.startswith(prefix) or prefix.startswith(p):
                        return (p, pa)
                return (prefix, raw_abbr)

            # 3. 괄호 패턴: A ( B )
            if m_paren:
                abbr_a = m_paren.group(1).strip()
                abbr_b = m_paren.group(2).strip()

                if abbr_a == "MA":
                    # Memory Archive 간접 연관곡
                    if abbr_b in index:
                        return index[abbr_b]
                    b_clean = re.sub(r'\d+$', '', abbr_b)
                    if b_clean in index:
                        return index[b_clean]
                    # 본편 팩이 존재하지 않는 단독 콜라보 그룹 (HTC, Stl)
                    STANDALONE_MA = {
                        "HTC": ("HARDCORE TANO*C", "HTC"),
                        "Stl": ("Stellights", "Stl"),
                    }
                    if b_clean in STANDALONE_MA:
                        return STANDALONE_MA[b_clean]
                    return ("Memory Archive", "MA")

                # 일반 스토리 어펜드 팩 (A ( B ))
                if abbr_a in index:
                    return index[abbr_a]
                return (raw_pack, abbr_a)

        else:
            # Strict 모드:
            if m_paren:
                abbr_a = m_paren.group(1).strip()
                abbr_b = m_paren.group(2).strip()
                if abbr_a == "MA":
                    return ("Memory Archive", "MA")
                if abbr_b in cls.APPEND_STRICT_MAPPING:
                    return cls.APPEND_STRICT_MAPPING[abbr_b]
                return (raw_pack, raw_abbr)

        return (raw_pack, raw_abbr)

    @classmethod
    def normalize_pack_id(cls, name: str, abbr: str = "") -> str:
        """팩 정식 명칭 기반 고유 식별자(ID) 정규화."""
        target = name.strip() if name else abbr.strip()
        normalized = re.sub(r'[^a-zA-Z0-9]+', '_', target.lower()).strip('_')
        return normalized or "unknown"

    @classmethod
    def parse_version_tuple(cls, version_str: str, ascending: bool = True) -> Tuple[Any, Any, Any]:
        """
        SemVer 버전 문자열 -> 정수 튜플.
        버전이 없는 경우(결측치) 항상 정렬 방향에 관계없이 최하단에 배치되도록
        ascending=True(오름차순)이면 (inf, inf, inf),
        ascending=False(내림차순)이면 (-inf, -inf, -inf)를 반환.
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
        return tuple(int_nums[:3])

    @classmethod
    def parse_bpm_num(cls, bpm: Any, ascending: bool = True) -> float:
        """BPM 문자열에서 정렬용 대표 수치를 추출한다."""
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
    def format_timestamp(timestamp) -> str:
        """타임스탬프를 읽기 쉬운 문자열로 변환 (StatisticsService와 동일)."""
        if not timestamp or timestamp <= 0:
            return "Never played"
        try:
            ts = float(timestamp)
            if ts > 100000000000:
                ts = ts / 1000.0
            dt = datetime.fromtimestamp(ts)
        except Exception:
            return "Never played"
        now = datetime.now()
        days_diff = (now.date() - dt.date()).days
        if days_diff == 0:
            return f"Today {dt.strftime('%H:%M')}"
        elif days_diff == 1:
            return "Yesterday"
        elif days_diff < 7:
            return f"{days_diff} days ago"
        else:
            return dt.strftime('%Y-%m-%d')

    @classmethod
    def format_pack_display_value(cls, pack: dict, sort_mode: str) -> str:
        """팩 정렬 모드에 따른 카드 우측 displayValue 문자열 포맷."""
        mode = (sort_mode or "").lower().strip()
        if mode in ('total_play', 'total_plays', 'play_count'):
            mode = 'total_play_count'
        elif mode in ('bp',):
            mode = 'level'

        if mode == "version":
            v = pack.get('version')
            return f"v{v}" if v else "-"
        elif mode == "score":
            avg = pack.get('avg_score', 0)
            return f"{avg:,}" if avg > 0 else "-"
        elif mode == "potential":
            pot = pack.get('top_potential', {}).get('value', 0.0)
            return f"{pot:.4f}" if pot > 0 else "-"
        elif mode == "max":
            mc = pack.get('max_count', 0)
            if mc > 0:
                return f"{mc} MAX"
            s_below = pack.get('top_score_below_max', 0)
            return f"MAX-{s_below}" if s_below > 0 else "-"
        elif mode == "total_play_count":
            c = pack.get('total_plays', 0)
            return f"{c} plays" if c > 0 else "Never played"
        elif mode == "this_year_play_count":
            c = pack.get('this_year_total_plays', 0)
            return f"{c} plays" if c > 0 else "Never played"
        elif mode == "length":
            sec = int(pack.get('total_length', 0))
            if sec <= 0:
                return "-"
            m = sec // 60
            s = sec % 60
            if m >= 60:
                h = m // 60
                m = m % 60
                return f"{h}:{m:02d}:{s:02d}"
            return f"{m}:{s:02d}"
        elif mode == "recent_played":
            t = pack.get('latest_played_time', 0)
            return cls.format_timestamp(t)
        elif mode == "level":
            bp = float(pack.get('top_bp', 0.0))
            return f"{bp:.1f}" if bp > 0 else "?"
        elif mode == "s_bp":
            sbp = float(pack.get('top_s_bp', 0.0))
            return f"{sbp:.2f}" if sbp > 0 else "?"
        elif mode == "perceived_bp":
            pbp = float(pack.get('top_perceived_bp', 0.0))
            return f"{pbp:.2f}" if pbp > 0 else "?"
        elif mode == "note_count":
            nc = int(pack.get('top_note_count', 0))
            return f"{nc:,}" if nc > 0 else "-"
        elif mode == "bpm":
            b_str = pack.get('top_bpm_str')
            b_val = pack.get('top_bpm', 0.0)
            if b_str:
                return str(b_str)
            return str(int(b_val)) if b_val > 0 else "-"
        return ""

    @classmethod
    def format_song_display_value(cls, song: dict, sort_mode: str) -> str:
        """팩 내 수록곡 정렬 모드에 따른 카드 우측 displayValue 문자열 포맷 (Song 모드와 동일)."""
        mode = (sort_mode or "score").lower().strip()
        if mode in ('bp',):
            mode = 'level'
        elif mode in ('total_play', 'total_plays', 'play_count'):
            mode = 'total_play_count'

        if mode == "title":
            return ""
        elif mode == "score":
            s = song.get('bestScore', 0)
            return f"{s:,}" if song.get('hasScore') else "-"
        elif mode == "max":
            if not song.get('hasScore'):
                return "-"
            loss = song.get('scoreBelowMax', 0)
            return f"MAX-{loss}" if loss > 0 else "MAX"
        elif mode == "total_play_count":
            c = song.get('total_plays', 0)
            return f"{c} plays" if c > 0 else "Never played"
        elif mode == "this_year_play_count":
            c = song.get('this_year_plays', 0)
            return f"{c} plays" if c > 0 else "Never played"
        elif mode == "recent_played":
            t = song.get('recent_played', 0)
            return cls.format_timestamp(t) if t > 0 else "Never played"
        elif mode == "level":
            lvl = song.get('level', '')
            return str(lvl) if lvl else "?"
        elif mode == "s_bp":
            s_bp = song.get('s_bp', 0.0)
            return f"{s_bp:.2f}" if s_bp > 0 else "?"
        elif mode == "perceived_bp":
            p_bp = song.get('perceived_bp', 0.0)
            return f"{p_bp:.2f}" if p_bp > 0 else "?"
        elif mode == "potential":
            pot = song.get('potential', 0.0)
            if not song.get('hasScore') or pot <= 0:
                return "-"
            return f"{math.floor(pot * 10000 + 1e-6) / 10000:.4f}"
        elif mode == "length":
            l = song.get('length', 0)
            return f"{l // 60}:{l % 60:02d}" if l > 0 else "?"
        elif mode == "bpm":
            bpm = song.get('bpm', '')
            return str(bpm) if bpm else "?"
        elif mode == "note_count":
            nc = song.get('note_count', 0)
            return str(nc) if nc > 0 else "?"
        elif mode == "version":
            v = song.get('version')
            return str(v) if v else "-"
        return ""

    @staticmethod
    def get_score_rank_index(
        score: int,
        has_score: bool = False,
        score_below_max: Optional[int] = None,
        cut_200: Optional[int] = None
    ) -> int:
        """점수를 SCORE_RANKS 인덱스(0~12)로 변환."""
        if not has_score:
            return 0  # '-'
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
        elif score_below_max is not None and cut_200 is not None and score_below_max + cut_200 <= 0:
            return 11  # 'FRAME'
        else:
            return 10  # 'PM'

    def get_packs(
        self,
        songs_data: Dict[Any, dict],
        scores_data: Optional[Dict[Tuple[str, int], dict]] = None,
        play_counts: Optional[Dict[Tuple[str, int], int]] = None,
        this_year_play_counts: Optional[Dict[Tuple[str, int], int]] = None,
        classification_mode: str = "strict",
        active_filters: Optional[Any] = None,
        sort_mode: str = "version",
        is_desc: bool = True,
        song_sort_mode: Optional[str] = None,
        song_is_desc: Optional[bool] = None,
        potential_rank_map: Optional[Dict[Tuple[str, int], int]] = None,
        excluded_packs: Optional[Any] = None,
    ) -> List[dict]:
        """
        모든 팩을 분류, 집계하고 정렬된 리스트로 반환.
        """
        # Defensive defaults
        scores_data = scores_data or {}
        play_counts = play_counts or {}
        this_year_play_counts = this_year_play_counts or {}

        # 제외 팩 목록 확보
        if excluded_packs is None:
            try:
                from utils.configuration import config
                excluded_packs = set(config['general']['excluded_packs'])
            except Exception:
                excluded_packs = set()
        else:
            excluded_packs = set(excluded_packs)

        # 전역 평균 곡 길이 계산 (결측치 보정용)
        global_known_lengths = [
            int(s.get('length')) for s in songs_data.values()
            if s.get('length') and int(s.get('length')) > 0
        ]
        global_avg_length = (
            sum(global_known_lengths) / len(global_known_lengths)
            if global_known_lengths else 135.0
        )

        # 1. 팩별 곡 그룹핑
        pack_groups: Dict[Tuple[str, str], List[dict]] = {}
        main_pack_index = self.build_main_pack_index(songs_data)

        for song_id, song_data in songs_data.items():
            raw_pack = song_data.get('pack', '')
            raw_abbr = song_data.get('pack_abbr', '')

            norm_name, norm_abbr = self.parse_pack_info(
                raw_pack, raw_abbr, classification_mode, main_pack_index=main_pack_index
            )

            # 제외 팩 판정:
            # 1. raw_pack이 excluded_packs에 직접 포함된 경우
            # 2. conceptual 모드이고 norm_name(부모 팩/메인 팩)이 excluded_packs에 포함된 경우
            if excluded_packs:
                if raw_pack in excluded_packs:
                    continue
                if classification_mode == "conceptual" and norm_name in excluded_packs:
                    continue

            key = (norm_name, norm_abbr)
            if key not in pack_groups:
                pack_groups[key] = []
            pack_groups[key].append(song_data)

        # 2. 팩별 통계 산출
        result_packs: List[dict] = []

        # 팩 내 곡 정렬 모드 결정
        if song_sort_mode is not None:
            effective_song_sort_mode = song_sort_mode
            effective_song_is_desc = is_desc if song_is_desc is None else song_is_desc
        else:
            if sort_mode == "version":
                # 동일버전 내 bp가 가장 높은 악곡이 속한 팩이 위로 오고, 동일팩 내 악곡끼리는 bp정렬
                effective_song_sort_mode = "bp"
                effective_song_is_desc = True
            else:
                effective_song_sort_mode = sort_mode
                effective_song_is_desc = is_desc

        # 전역 올해 총 플레이 시간 계산 (올해 점유율 계산용)
        global_this_year_play_time_seconds = 0
        for s in songs_data.values():
            slen = int(s.get('length') or 0)
            if slen <= 0:
                slen = int(round(global_avg_length))
            sid = s.get('arcaea_id') or str(s.get('song_db_id') or s.get('id') or '')
            charts = s.get('charts') or {}
            if isinstance(charts, dict):
                chart_keys = charts.keys()
            elif isinstance(charts, list):
                chart_keys = range(len(charts))
            else:
                chart_keys = []
            for diff in chart_keys:
                d_val = int(diff) if isinstance(diff, str) and diff.isdigit() else diff
                typ = this_year_play_counts.get((sid, d_val), 0)
                global_this_year_play_time_seconds += slen * typ

        for (pack_name, pack_abbr), group_songs in pack_groups.items():
            pack_id = self.normalize_pack_id(pack_name, pack_abbr)

            pack_stats = self._calculate_single_pack_stats(
                pack_id=pack_id,
                pack_name=pack_name,
                pack_abbr=pack_abbr,
                group_songs=group_songs,
                scores_data=scores_data,
                play_counts=play_counts,
                this_year_play_counts=this_year_play_counts,
                active_filters=active_filters,
                song_sort_mode=effective_song_sort_mode,
                song_is_desc=effective_song_is_desc,
                potential_rank_map=potential_rank_map,
                global_avg_length=global_avg_length,
                global_this_year_play_time_seconds=global_this_year_play_time_seconds,
            )
            # 필터 적용 시 통과한 수록곡이 없는 팩은 리스트에서 제외
            if active_filters is not None and not pack_stats.get('songs'):
                continue

            result_packs.append(pack_stats)

        # 3. 팩 정렬 적용
        sorted_packs = self.sort_packs(result_packs, sort_mode=sort_mode, is_desc=is_desc)
        return sorted_packs

    def _calculate_single_pack_stats(
        self,
        pack_id: str,
        pack_name: str,
        pack_abbr: str,
        group_songs: List[dict],
        scores_data: Dict[Tuple[str, int], dict],
        play_counts: Dict[Tuple[str, int], int],
        this_year_play_counts: Dict[Tuple[str, int], int],
        active_filters: Optional[Any],
        song_sort_mode: str,
        song_is_desc: bool,
        potential_rank_map: Optional[Dict[Tuple[str, int], int]],
        global_avg_length: float = 135.0,
        global_this_year_play_time_seconds: int = 0,
    ) -> dict:
        """단일 팩의 7단계 램프, 점수, 포텐셜, 플레이 횟수 통계 산출."""
        total_songs_count = len(group_songs)
        total_charts_count = 0
        played_songs_set = set()

        # 팩 색상 추출 (수록곡 중 pack_color가 있는 첫 번째 곡 기준)
        pack_color = ""
        for s in group_songs:
            c = s.get('pack_color')
            if c:
                pack_color = c
                break

        total_plays = 0
        this_year_total_plays = 0
        pack_play_time_seconds = 0
        pack_this_year_play_time_seconds = 0

        # 대표곡 비교 및 총 러닝타임 추적 변수
        # 팩 내 절대 최고치(MAX) - Version 정렬 등에서 기준값으로 사용
        max_bp: float = 0.0

        # song_is_desc(내림차순 True vs 오름차순 False)에 따른 대표 채보 추적
        rep_bp: float = -1.0 if song_is_desc else float('inf')
        rep_bp_record = None
        rep_s_bp: float = -1.0 if song_is_desc else float('inf')
        rep_s_bp_record = None
        rep_perceived_bp: float = -1.0 if song_is_desc else float('inf')
        rep_perceived_bp_record = None
        rep_note_count: int = -1 if song_is_desc else float('inf')
        rep_note_count_record = None
        rep_max_loss: int = float('inf') if song_is_desc else -1
        rep_max_record = None

        top_bpm: float = 0.0
        top_bpm_str: str = ""
        top_bpm_record = None
        latest_played_time: int = 0
        latest_played_record = None

        # Version 정렬 전용: 팩 출시 버전과 일치하는 채보 중 최고 BP 채보 추적
        version_top_bp: float = -1.0
        version_top_bp_record = None
        version_base_top_bp: float = -1.0
        version_base_top_bp_record = None

        # 팩 러닝타임 계산: 미지정 곡은 팩 평균(또는 전역 평균)으로 보정
        pack_known_lengths = [
            int(s.get('length')) for s in group_songs
            if s.get('length') and int(s.get('length')) > 0
        ]
        pack_avg_length = (
            sum(pack_known_lengths) / len(pack_known_lengths)
            if pack_known_lengths else global_avg_length
        )

        total_length: int = 0
        for s in group_songs:
            l = s.get('length')
            if l and int(l) > 0:
                total_length += int(l)
            else:
                total_length += int(round(pack_avg_length))

        lamp_counts = {
            'pm': 0,
            'fr': 0,
            'hard': 0,
            'complete': 0,
            'easy': 0,
            'lost': 0,
            'unplayed': 0,
        }

        score_grade_counts = {
            'pm': 0,
            'ex_plus': 0,
            'ex': 0,
            'aa': 0,
            'a': 0,
            'b': 0,
            'c': 0,
            'd': 0,
            'unplayed': 0,
            'other': 0,  # 하위 호환성 유지
        }

        frame_count = 0
        max_count = 0
        scores_below_max_list: List[int] = []

        top_potential_record = {
            'value': 0.0,
            'potential': 0.0,
            'song_title': '',
            'diff_name': '',
            'diff_index': -1,
            'diff_color_tag': '',
            'is_inscribed': False,
            'jacket_path': '',
            'song_id': '',
            'level_str': '',
            'diff_with_level': '',
        }
        best_potential_val: float = -1.0

        top_score_record = {
            'value': 0,
            'score': 0,
            'is_max': False,
            'song_title': '',
            'diff_name': '',
            'diff_index': -1,
            'diff_color_tag': '',
            'is_inscribed': False,
            'jacket_path': '',
            'song_id': '',
            'level_str': '',
            'diff_with_level': '',
        }
        # MAX 우선 비교 튜플: (1 if is_max else 0, score, -score_below_max)
        best_score_tuple: Tuple[int, int, int] = (-1, -1, -9999999)

        # 팩 출시(가장 이른) 버전 사전 산출 (악곡 순서 의존성 0% 차단)
        earliest_version_tuple: Tuple[int, int, int] = (999999, 999999, 999999)
        earliest_version_str: str = ""
        for sdata in group_songs:
            s_ver = sdata.get('version') or ''
            if s_ver:
                v_tuple = self.parse_version_tuple(s_ver, ascending=True)
                if v_tuple < earliest_version_tuple:
                    earliest_version_tuple = v_tuple
                    earliest_version_str = s_ver

        # 플레이된 각 곡의 최고 점수 리스트 (평균 점수 계산용)
        song_best_scores: List[int] = []

        # 팩 내 수록곡 목록 빌드
        built_songs: List[dict] = []

        # 최다 플레이 곡(Most Played) 추적 (동점 시 첫 번째 곡 우선, 미플레이 시 group_songs[0] fallback)
        most_played_song_id: str = ""
        most_played_thumb_diff: int = 2
        most_played_song_title: str = group_songs[0].get('title') or group_songs[0].get('canonical_title') or '' if group_songs else ''
        most_played_song_count: int = 0
        max_song_plays: int = -1

        for sdata in group_songs:
            song_id = sdata.get('arcaea_id') or str(sdata.get('song_db_id', ''))
            song_db_id = sdata.get('song_db_id') or sdata.get('id')
            song_title = sdata.get('title') or sdata.get('canonical_title') or 'Unknown'
            song_artist = sdata.get('artist') or ''
            song_version = sdata.get('version') or ''

            charts = sdata.get('charts', {})
            total_charts_count += len(charts)

            song_has_play = False
            cur_song_best_score = 0
            cur_song_best_bp = 0.0
            cur_song_best_level = ""
            cur_song_best_s_bp = 0.0
            cur_song_best_perceived_bp = 0.0
            cur_song_best_note_count = -1 if song_is_desc else 999999
            cur_song_best_diff_for_note_count = -1
            cur_song_latest_played = 0
            cur_song_best_potential = 0.0
            cur_song_best_loss = 999999
            cur_song_filtered_charts_count = 0
            cur_song_best_diff_for_score = -1
            cur_song_best_diff_for_max = -1
            cur_song_best_diff_for_recent = -1
            cur_song_best_diff_for_level = -1
            cur_song_best_diff_for_s_bp = -1
            cur_song_best_diff_for_perceived_bp = -1
            cur_song_best_diff_for_potential = -1

            # Song 모드 카드 호환 메타데이터 추적
            filtered_diffs_list: List[dict] = []
            thumbnail_difficulty = -1
            thumbnail_is_ins = False
            THUMBNAIL_PRIORITY = {3: 0, 4: 1, 2: 2, 1: 3, 0: 4}

            for diff in DIFFICULTY_ORDER:
                cdata = charts.get(diff)
                if not cdata:
                    continue

                scdata = scores_data.get((song_id, diff))

                # 활성 필터 검증
                if not self._chart_passes_filters(cdata, diff, sdata, scdata, active_filters):
                    continue

                cur_song_filtered_charts_count += 1
                bp = float(cdata.get('bp', 0.0) or 0.0)
                if bp > cur_song_best_bp:
                    cur_song_best_bp = bp
                    cur_song_best_level = str(cdata.get('level_str') or cdata.get('level', '') or '')
                    cur_song_best_diff_for_level = diff
                if bp > max_bp:
                    max_bp = bp

                s_bp = float(cdata.get('s_bp', 0.0) or 0.0)
                if s_bp > cur_song_best_s_bp:
                    cur_song_best_s_bp = s_bp
                    cur_song_best_diff_for_s_bp = diff

                perceived_bp = float(cdata.get('perceived_bp', 0.0) or 0.0)
                if perceived_bp > cur_song_best_perceived_bp:
                    cur_song_best_perceived_bp = perceived_bp
                    cur_song_best_diff_for_perceived_bp = diff

                note_count = int(cdata.get('note_count', 0) or 0)
                if note_count > 0:
                    is_better_nc = (note_count > cur_song_best_note_count) if song_is_desc else (note_count < cur_song_best_note_count)
                    if cur_song_best_diff_for_note_count == -1 or is_better_nc:
                        cur_song_best_note_count = note_count
                        cur_song_best_diff_for_note_count = diff

                p_count = play_counts.get((song_id, diff), 0)
                typ_count = this_year_play_counts.get((song_id, diff), 0)

                s_len = int(sdata.get('length') or 0)
                if s_len <= 0:
                    s_len = int(round(pack_avg_length))

                total_plays += p_count
                this_year_total_plays += typ_count
                pack_play_time_seconds += s_len * p_count
                pack_this_year_play_time_seconds += s_len * typ_count

                has_score = bool(scdata and (scdata.get('time_played', 0) > 0 or scdata.get('score', 0) > 0))
                best_clear_type = scdata.get('best_clear_type', 0) if scdata else 0
                clear_type = scdata.get('clear_type', 0) if scdata else 0
                score = scdata.get('score', 0) if scdata else 0
                shiny_perfect = scdata.get('shiny_perfect', 0) if scdata else 0
                score_below_max = scdata.get('score_below_max') if scdata else None
                cut_200 = cdata.get('cut_200')

                # 판정 수 기반 실제 손실 계산 (Song 모드와 동일)
                loss = None
                if has_score and scdata:
                    pure = scdata.get('perfect', 0)
                    shiny = scdata.get('shiny_perfect', 0)
                    far = scdata.get('near', 0)
                    lost = scdata.get('miss', 0)
                    if pure > 0 or shiny > 0 or far > 0 or lost > 0:
                        loss = pure + far + lost - shiny
                if loss is None and score_below_max is not None:
                    loss = int(score_below_max) if score_below_max < 100000 else None

                is_max = bool(has_score and ((loss is not None and loss == 0) or (score_below_max is not None and score_below_max == 0)))

                # Inscribed 난이도 태깅 (diff == 3 and is_inscribed == 1)
                is_ins = bool(cdata.get('is_inscribed', False)) and diff == 3
                if is_ins:
                    diff_name = "Inscribed"
                    diff_color_tag = "ins"
                    short_diff_name = "INS"
                else:
                    diff_name = self.DIFF_FULL_NAMES.get(diff, DIFFICULTY_NAMES.get(diff, ''))
                    diff_color_tag = DIFFICULTY_NAMES.get(diff, '').lower()
                    short_diff_name = DIFFICULTY_NAMES.get(diff, '')

                level_str = str(cdata.get('level_str') or cdata.get('level', '') or '')
                diff_with_level = f"{diff_name} {level_str}".strip() if level_str else diff_name

                # 대표곡 레코드 후보 갱신 (BP, S-BP, Perceived BP, Note Count)
                jacket_path = self._resolve_jacket_path(song_id, diff)

                # 1) Level (BP) 대표 채보: 내림차순 MAX / 오름차순 MIN
                is_better_bp = (bp > rep_bp) if song_is_desc else (bp < rep_bp)
                if rep_bp_record is None or is_better_bp:
                    rep_bp = bp
                    rep_bp_record = {
                        'song_id': song_id,
                        'song_title': song_title,
                        'diff_name': diff_name,
                        'diff_index': diff,
                        'diff_color_tag': diff_color_tag,
                        'is_inscribed': is_ins,
                        'jacket_path': jacket_path,
                        'level_str': level_str,
                        'diff_with_level': diff_with_level,
                        'value': bp,
                    }

                # 2) S-BP 대표 채보: 내림차순 MAX / 오름차순 MIN
                is_better_sbp = (s_bp > rep_s_bp) if song_is_desc else (s_bp < rep_s_bp)
                if rep_s_bp_record is None or is_better_sbp:
                    rep_s_bp = s_bp
                    rep_s_bp_record = {
                        'song_id': song_id,
                        'song_title': song_title,
                        'diff_name': diff_name,
                        'diff_index': diff,
                        'diff_color_tag': diff_color_tag,
                        'is_inscribed': is_ins,
                        'jacket_path': jacket_path,
                        'level_str': level_str,
                        'diff_with_level': diff_with_level,
                        'value': s_bp,
                    }

                # 3) Perceived BP 대표 채보: 내림차순 MAX / 오름차순 MIN
                is_better_pbp = (perceived_bp > rep_perceived_bp) if song_is_desc else (perceived_bp < rep_perceived_bp)
                if rep_perceived_bp_record is None or is_better_pbp:
                    rep_perceived_bp = perceived_bp
                    rep_perceived_bp_record = {
                        'song_id': song_id,
                        'song_title': song_title,
                        'diff_name': diff_name,
                        'diff_index': diff,
                        'diff_color_tag': diff_color_tag,
                        'is_inscribed': is_ins,
                        'jacket_path': jacket_path,
                        'level_str': level_str,
                        'diff_with_level': diff_with_level,
                        'value': perceived_bp,
                    }

                # 4) Note Count 대표 채보: 내림차순 MAX / 오름차순 MIN
                is_better_notes = (note_count > rep_note_count) if song_is_desc else (note_count < rep_note_count)
                if rep_note_count_record is None or is_better_notes:
                    rep_note_count = note_count
                    rep_note_count_record = {
                        'song_id': song_id,
                        'song_title': song_title,
                        'diff_name': diff_name,
                        'diff_index': diff,
                        'diff_color_tag': diff_color_tag,
                        'is_inscribed': is_ins,
                        'jacket_path': jacket_path,
                        'level_str': level_str,
                        'diff_with_level': diff_with_level,
                        'value': note_count,
                    }

                # 5) Version 정렬 전용: 팩 출시 버전 당시에 존재했던 본편 채보 중 최고 BP 채보 (방안 A)
                # 후속 업데이트로 추가된 채보(차트 버전이 팩 출시 버전보다 최신이거나 3.0 이전 팩의 BYD)는 배제
                c_ver_raw = cdata.get('version')
                chart_ver = c_ver_raw or song_version or ''
                c_ver_tuple = self.parse_version_tuple(c_ver_raw, ascending=True) if c_ver_raw else None

                is_subsequent = False
                if c_ver_tuple and c_ver_tuple > earliest_version_tuple:
                    is_subsequent = True
                elif diff == 3:
                    if earliest_version_tuple < (3, 0, 0):
                        is_subsequent = True
                    elif c_ver_tuple and c_ver_tuple != earliest_version_tuple:
                        is_subsequent = True

                # 본편 채보(diff != 3) 중 최고 BP 채보 (안전한 fallback용)
                if diff != 3 and not is_subsequent:
                    if bp > version_base_top_bp or version_base_top_bp_record is None:
                        version_base_top_bp = bp
                        version_base_top_bp_record = {
                            'song_id': song_id,
                            'song_title': song_title,
                            'diff_name': diff_name,
                            'diff_index': diff,
                            'diff_color_tag': diff_color_tag,
                            'is_inscribed': is_ins,
                            'jacket_path': jacket_path,
                            'level_str': level_str,
                            'diff_with_level': diff_with_level,
                            'value': bp,
                        }

                if not is_subsequent:
                    chart_ver_tuple = self.parse_version_tuple(chart_ver, ascending=True)
                    if chart_ver_tuple == earliest_version_tuple:
                        if bp > version_top_bp or version_top_bp_record is None:
                            version_top_bp = bp
                            version_top_bp_record = {
                                'song_id': song_id,
                                'song_title': song_title,
                                'diff_name': diff_name,
                                'diff_index': diff,
                                'diff_color_tag': diff_color_tag,
                                'is_inscribed': is_ins,
                                'jacket_path': jacket_path,
                                'level_str': level_str,
                                'diff_with_level': diff_with_level,
                                'value': bp,
                            }

                # 6) MAX 정렬 전용: 손실 판정(loss) 기준 대표 채보 추적
                if has_score and loss is not None:
                    if loss < cur_song_best_loss:
                        cur_song_best_loss = loss
                        cur_song_best_diff_for_max = diff

                    if loss is not None:
                        if song_is_desc:
                            is_better_max = (rep_max_record is None) or (loss < rep_max_loss) or (
                                loss == rep_max_loss and (score > rep_max_record.get('score', 0) or (
                                    score == rep_max_record.get('score', 0) and bp > rep_max_record.get('bp', 0)
                                ))
                            )
                        else:
                            is_better_max = (rep_max_record is None) or (loss > rep_max_loss) or (
                                loss == rep_max_loss and (score < rep_max_record.get('score', 0) or (
                                    score == rep_max_record.get('score', 0) and bp < rep_max_record.get('bp', 0)
                                ))
                            )
                        if is_better_max:
                            rep_max_loss = loss
                            rep_max_record = {
                                'song_id': song_id,
                                'song_title': song_title,
                                'diff_name': diff_name,
                                'diff_index': diff,
                                'diff_color_tag': diff_color_tag,
                                'is_inscribed': is_ins,
                                'jacket_path': jacket_path,
                                'level_str': level_str,
                                'diff_with_level': diff_with_level,
                                'score': score,
                                'bp': bp,
                                'value': loss,
                                'is_max': is_max,
                            }

                if thumbnail_difficulty == -1 or THUMBNAIL_PRIORITY.get(diff, 99) < THUMBNAIL_PRIORITY.get(thumbnail_difficulty, 99):
                    thumbnail_difficulty = diff
                    thumbnail_is_ins = is_ins

                p_rank = potential_rank_map.get((song_id, diff), 0) if potential_rank_map else 0

                filtered_diffs_list.append({
                    'difficulty': diff,
                    'difficultyName': short_diff_name,
                    'diffColorTag': diff_color_tag,
                    'isInscribed': is_ins,
                    'level': str(cdata.get('level', '')),
                    'bp': bp,
                    'score': score,
                    'hasScore': has_score,
                    'ignoreChart': bool(cdata.get('ignore_chart', False)),
                    'skillIssues': bool(cdata.get('skill_issues', False)),
                    'hardBpm': bool(cdata.get('hard_bpm', False)),
                    'potentialRank': p_rank,
                })

                if has_score:
                    song_has_play = True
                    played_songs_set.add(song_id)

                    t_played = int(scdata.get('time_played', 0) or 0)
                    if t_played > cur_song_latest_played:
                        cur_song_latest_played = t_played
                        cur_song_best_diff_for_recent = diff
                    if t_played > latest_played_time or latest_played_record is None:
                        latest_played_time = t_played
                        latest_played_record = {
                            'song_id': song_id,
                            'song_title': song_title,
                            'diff_name': diff_name,
                            'diff_index': diff,
                            'diff_color_tag': diff_color_tag,
                            'is_inscribed': is_ins,
                            'jacket_path': jacket_path,
                            'level_str': level_str,
                            'diff_with_level': diff_with_level,
                            'value': t_played,
                        }

                    if score > cur_song_best_score:
                        cur_song_best_score = score
                        cur_song_best_diff_for_score = diff

                    # 램프 카운트 분류
                    if best_clear_type == 3:
                        lamp_counts['pm'] += 1
                    elif best_clear_type == 2:
                        lamp_counts['fr'] += 1
                    elif best_clear_type == 5:
                        lamp_counts['hard'] += 1
                    elif best_clear_type == 1:
                        lamp_counts['complete'] += 1
                    elif best_clear_type == 4:
                        lamp_counts['easy'] += 1
                    elif best_clear_type == 0:
                        lamp_counts['lost'] += 1
                    else:
                        lamp_counts['complete'] += 1

                    # 9단계 점수 등급 분류 (PM, EX+, EX, AA, A, B, C, D)
                    if score >= 10000000:
                        score_grade_counts['pm'] += 1
                    elif score >= 9900000:
                        score_grade_counts['ex_plus'] += 1
                    elif score >= 9800000:
                        score_grade_counts['ex'] += 1
                    elif score >= 9500000:
                        score_grade_counts['aa'] += 1
                    elif score >= 9200000:
                        score_grade_counts['a'] += 1
                        score_grade_counts['other'] += 1
                    elif score >= 8900000:
                        score_grade_counts['b'] += 1
                        score_grade_counts['other'] += 1
                    elif score >= 8600000:
                        score_grade_counts['c'] += 1
                        score_grade_counts['other'] += 1
                    else:
                        score_grade_counts['d'] += 1
                        score_grade_counts['other'] += 1

                    # FRAME 달성 판정 (MAX 달성이거나 score_below_max + cut_200 <= 0)
                    if is_max or (score_below_max is not None and cut_200 is not None and float(score_below_max) + float(cut_200) <= 0):
                        frame_count += 1

                    # MAX 달성 및 직전 최고 점수 추적
                    if is_max:
                        max_count += 1
                    else:
                        if loss is not None and loss > 0:
                            scores_below_max_list.append(loss)

                    # 포텐셜 계산
                    pot = calculate_potential(
                        cdata.get('bp', 0),
                        cdata.get('note_count', 0),
                        score,
                        shiny_perfect,
                        is_cleared=(clear_type != 0),
                    )
                    if pot is not None:
                        if pot > cur_song_best_potential:
                            cur_song_best_potential = pot
                            cur_song_best_diff_for_potential = diff
                        if pot > best_potential_val:
                            best_potential_val = pot
                            jacket_path = self._resolve_jacket_path(song_id, diff)
                            top_potential_record = {
                                'value': round(pot, 4),
                                'potential': round(pot, 4),
                                'song_title': song_title,
                                'diff_name': diff_name,
                                'diff_index': diff,
                                'diff_color_tag': diff_color_tag,
                                'is_inscribed': is_ins,
                                'jacket_path': jacket_path,
                                'song_id': song_id,
                                'level_str': level_str,
                                'diff_with_level': diff_with_level,
                            }

                    # 최고 점수 추적 (MAX 우선 비교 튜플: (1 if is_max else 0, score, -loss_cmp))
                    loss_cmp = loss if loss is not None else 999999
                    score_cmp = (1 if is_max else 0, score, -loss_cmp)
                    if score_cmp > best_score_tuple:
                        best_score_tuple = score_cmp
                        jacket_path = self._resolve_jacket_path(song_id, diff)
                        top_score_record = {
                            'value': score,
                            'score': score,
                            'is_max': is_max,
                            'song_title': song_title,
                            'diff_name': diff_name,
                            'diff_index': diff,
                            'diff_color_tag': diff_color_tag,
                            'is_inscribed': is_ins,
                            'jacket_path': jacket_path,
                            'song_id': song_id,
                            'level_str': level_str,
                            'diff_with_level': diff_with_level,
                        }
                else:
                    lamp_counts['unplayed'] += 1
                    score_grade_counts['unplayed'] += 1
                    score_grade_counts['other'] += 1

            # 썸네일 난이도 fallback (통과 채보가 없는 경우 charts 내 최고 난이도 선정)
            if thumbnail_difficulty == -1:
                for diff in DIFFICULTY_ORDER:
                    if diff in charts:
                        cdata = charts[diff]
                        is_ins = bool(cdata.get('is_inscribed', False)) and diff == 3
                        if thumbnail_difficulty == -1 or THUMBNAIL_PRIORITY.get(diff, 99) < THUMBNAIL_PRIORITY.get(thumbnail_difficulty, 99):
                            thumbnail_difficulty = diff
                            thumbnail_is_ins = is_ins

            if thumbnail_is_ins:
                thumb_diff_color_tag = "ins"
                thumb_diff_name = "INS"
            elif thumbnail_difficulty >= 0:
                thumb_diff_color_tag = DIFFICULTY_NAMES.get(thumbnail_difficulty, 'ftr').lower()
                thumb_diff_name = DIFFICULTY_NAMES.get(thumbnail_difficulty, 'FTR')
            else:
                thumbnail_difficulty = 2
                thumb_diff_color_tag = 'ftr'
                thumb_diff_name = 'FTR'

            # 곡별 총 플레이 횟수 집계 및 최다 플레이 곡(Most Played) 갱신
            song_total_plays = sum(
                play_counts.get((song_id, int(d) if isinstance(d, str) and d.isdigit() else d), 0)
                for d in charts
            )
            song_this_year_plays = sum(
                this_year_play_counts.get((song_id, int(d) if isinstance(d, str) and d.isdigit() else d), 0)
                for d in charts
            )
            if song_total_plays > max_song_plays:
                max_song_plays = song_total_plays
                most_played_song_id = song_id
                most_played_thumb_diff = thumbnail_difficulty
                most_played_song_title = song_title
                most_played_song_count = song_total_plays

            if song_has_play and cur_song_best_score > 0:
                song_best_scores.append(cur_song_best_score)

            # 곡 BPM 파싱
            song_bpm_str = sdata.get('bpm', '')
            song_bpm_num = self.parse_bpm_num(song_bpm_str, ascending=False)
            if song_bpm_num != float('-inf') and (song_bpm_num > top_bpm or top_bpm_record is None):
                top_bpm = song_bpm_num
                top_bpm_str = song_bpm_str
                top_bpm_record = {
                    'song_id': song_id,
                    'song_title': song_title,
                    'diff_name': thumb_diff_name,
                    'diff_index': thumbnail_difficulty,
                    'diff_color_tag': thumb_diff_color_tag,
                    'is_inscribed': thumbnail_is_ins,
                    'jacket_path': self._resolve_jacket_path(song_id, thumbnail_difficulty),
                    'level_str': '',
                    'diff_with_level': thumb_diff_name,
                    'value': song_bpm_num,
                }

            # 필터 적용 시 통과한 채보가 있는 곡만 songs 목록에 포함 (필터 미지정 시 전곡)
            if active_filters is None or cur_song_filtered_charts_count > 0:
                s_strict_pack, s_strict_abbr = self.parse_pack_info(
                    sdata.get('pack', ''), sdata.get('pack_abbr', ''), classification_mode="strict"
                )
                built_songs.append({
                    'id': song_id,
                    'song_id': song_id,
                    'songDbId': song_db_id,
                    'arcaeaId': song_id,
                    'title': song_title,
                    'artist': song_artist,
                    'bp': cur_song_best_bp,
                    'level': cur_song_best_level,
                    's_bp': cur_song_best_s_bp,
                    'perceived_bp': cur_song_best_perceived_bp,
                    'score': cur_song_best_score,
                    'bestScore': cur_song_best_score,
                    'best_score': cur_song_best_score,
                    'hasScore': song_has_play,
                    'has_score': song_has_play,
                    'scoreBelowMax': cur_song_best_loss if (song_has_play and cur_song_best_loss != 999999) else 0,
                    'loss': cur_song_best_loss if (song_has_play and cur_song_best_loss != 999999) else 0,
                    'version': song_version,
                    'bpm': song_bpm_str,
                    'bpm_num': song_bpm_num if song_bpm_num != float('-inf') else 0.0,
                    'length': sdata.get('length', 0),
                    'note_count': cur_song_best_note_count,
                    'recent_played': cur_song_latest_played,
                    'potential': cur_song_best_potential,
                    'total_plays': song_total_plays,
                    'this_year_plays': song_this_year_plays,
                    'pack': s_strict_pack,
                    'packAbbr': s_strict_abbr,
                    'strictPack': s_strict_pack,
                    'strictPackAbbr': s_strict_abbr,
                    'thumbnailDifficulty': thumbnail_difficulty,
                    'diffColorTag': thumb_diff_color_tag,
                    'difficultyName': thumb_diff_name,
                    'filteredDifficulties': filtered_diffs_list,
                    'bestDiffForScore': cur_song_best_diff_for_score,
                    'bestDiffForMax': cur_song_best_diff_for_max,
                    'bestDiffForRecent': cur_song_best_diff_for_recent,
                    'bestDiffForLevel': cur_song_best_diff_for_level,
                    'bestDiffForSBp': cur_song_best_diff_for_s_bp,
                    'bestDiffForPerceivedBp': cur_song_best_diff_for_perceived_bp,
                    'bestDiffForPotential': cur_song_best_diff_for_potential,
                    'bestDiffForNoteCount': cur_song_best_diff_for_note_count,
                    'raw_data': sdata,
                })

        # 곡 목록 Song 모드 정렬
        self._sort_song_list(built_songs, sort_mode=song_sort_mode, is_desc=song_is_desc)

        # 팩 내 수록곡 카드 우측 displayValue 주입 (Song 모드와 동일)
        for s in built_songs:
            s['displayValue'] = self.format_song_display_value(s, song_sort_mode)

        # 진척도 카운트 계산
        frpm_count = lamp_counts['pm'] + lamp_counts['fr']
        clr_count = (
            lamp_counts['pm']
            + lamp_counts['fr']
            + lamp_counts['hard']
            + lamp_counts['complete']
            + lamp_counts['easy']
        )
        all_count = sum(lamp_counts.values())

        # 평균 점수 (플레이된 곡 기준)
        if song_best_scores:
            avg_score = int(round(sum(song_best_scores) / len(song_best_scores)))
        else:
            avg_score = 0

        # MAX 타이브레이커 속성 계산 (손실 판정이 가장 적은 값을 대표값으로 산출)
        if scores_below_max_list:
            top_score_below_max = min(scores_below_max_list)
            count_at_top_score_below_max = scores_below_max_list.count(top_score_below_max)
        else:
            top_score_below_max = 0
            count_at_top_score_below_max = 0

        # Most Played 자켓 썸네일 경로 도출
        most_played_jacket_path = self._resolve_jacket_path(most_played_song_id, most_played_thumb_diff)

        # 활성 필터 적용 시 팩 단위 통계 동적 갱신
        if active_filters is not None:
            effective_song_count = len(built_songs)
            effective_chart_count = sum(len(s.get('filteredDifficulties', [])) for s in built_songs)
            effective_total_length = 0
            for s in built_songs:
                l = s.get('length')
                if l and int(l) > 0:
                    effective_total_length += int(l)
                else:
                    effective_total_length += int(round(pack_avg_length))
        else:
            effective_song_count = total_songs_count
            effective_chart_count = total_charts_count
            effective_total_length = total_length
        # 플레이 시간 및 점유율 환산
        hours = pack_play_time_seconds // 3600
        mins = (pack_play_time_seconds % 3600) // 60
        play_time_str = f"{hours}h {mins}m" if hours > 0 else f"{mins}m"

        ty_hours = pack_this_year_play_time_seconds // 3600
        ty_mins = (pack_this_year_play_time_seconds % 3600) // 60
        this_year_play_time_str = f"{ty_hours}h {ty_mins}m" if ty_hours > 0 else f"{ty_mins}m"

        if global_this_year_play_time_seconds > 0:
            this_year_play_time_share = round(
                (pack_this_year_play_time_seconds / global_this_year_play_time_seconds * 100), 1
            )
        else:
            this_year_play_time_share = 0.0

        ex_plus_count = score_grade_counts['pm'] + score_grade_counts['ex_plus']
        ex_plus_rate = round((ex_plus_count / all_count * 100), 1) if all_count > 0 else 0.0
        clear_count = clr_count
        clear_rate = round((clear_count / all_count * 100), 1) if all_count > 0 else 0.0

        from datetime import datetime
        current_year = datetime.now().year

        return {
            'id': pack_id,
            'name': pack_name,
            'abbr': pack_abbr,
            'color': pack_color,
            'pack_color': pack_color,
            'version': earliest_version_str,
            'song_count': effective_song_count,
            'chart_count': effective_chart_count,
            'played_song_count': len(played_songs_set),
            'total_plays': total_plays,
            'this_year_total_plays': this_year_total_plays,
            'avg_score': avg_score,
            'frpm_count': frpm_count,
            'clr_count': clr_count,
            'all_count': all_count,
            'pm_count': lamp_counts['pm'],
            'clear_count': clear_count,
            'clear_rate': clear_rate,
            'score_grade_counts': score_grade_counts,
            'ex_plus_count': ex_plus_count,
            'ex_plus_rate': ex_plus_rate,
            'play_time_seconds': pack_play_time_seconds,
            'play_time_str': play_time_str,
            'this_year_play_time_seconds': pack_this_year_play_time_seconds,
            'this_year_play_time_str': this_year_play_time_str,
            'this_year_play_time_share': this_year_play_time_share,
            'most_played_song_title': most_played_song_title,
            'most_played_song_count': most_played_song_count,
            'current_year': current_year,
            'frame_count': frame_count,
            'max_count': max_count,
            'top_score_below_max': top_score_below_max,
            'count_at_top_score_below_max': count_at_top_score_below_max,
            'top_max_record': rep_max_record,
            'top_potential': top_potential_record,
            'top_score': top_score_record,
            'top_bp': round(rep_bp, 4) if rep_bp_record else 0.0,
            'top_bp_record': rep_bp_record,
            'max_bp': round(max_bp, 4),
            'top_s_bp': round(rep_s_bp, 4) if rep_s_bp_record else 0.0,
            'top_s_bp_record': rep_s_bp_record,
            'top_perceived_bp': round(rep_perceived_bp, 4) if rep_perceived_bp_record else 0.0,
            'top_perceived_bp_record': rep_perceived_bp_record,
            'top_note_count': rep_note_count if rep_note_count_record else 0,
            'top_note_count_record': rep_note_count_record,
            'version_rep_record': version_top_bp_record or version_base_top_bp_record or rep_bp_record,
            'top_bpm': top_bpm,
            'top_bpm_str': top_bpm_str,
            'top_bpm_record': top_bpm_record,
            'latest_played_time': latest_played_time,
            'latest_played_record': latest_played_record,
            'total_length': effective_total_length,
            'displayValue': '',
            'most_played_jacket_path': most_played_jacket_path,
            'most_played_song_id': most_played_song_id,
            'most_played_thumb_diff': most_played_thumb_diff,
            'lamp_counts': lamp_counts,
            'songs': built_songs,
        }

    def _chart_passes_filters(
        self,
        chart_data: dict,
        difficulty: int,
        song_data: dict,
        score_data: Optional[dict],
        active_filters: Optional[Any]
    ) -> bool:
        """활성 필터 조건 만족 여부 판정."""
        if active_filters is None:
            return True

        has_score = bool(score_data and (score_data.get('time_played', 0) > 0 or score_data.get('score', 0) > 0))
        score = score_data.get('score', 0) if score_data else 0
        score_below_max = score_data.get('score_below_max') if score_data else None
        cut_200 = chart_data.get('cut_200')
        clear_type = score_data.get('best_clear_type', 0) if score_data else 0

        # active_filters가 딕셔너리인 경우 (예: {'PST': True, 'PRS': False, ...})
        if isinstance(active_filters, dict):
            diff_name = DIFFICULTY_NAMES.get(difficulty, '')
            is_ins = bool(chart_data.get('is_inscribed', False)) and difficulty == 3
            filter_key = 'INS' if is_ins else diff_name
            return bool(active_filters.get(filter_key, True))

        # FilterParams 객체인 경우
        if hasattr(active_filters, 'difficulties'):
            # 1. 난이도 필터
            if difficulty == 3:
                is_ins = bool(chart_data.get('is_inscribed', False))
                if is_ins:
                    if not getattr(active_filters, 'include_inscribed', True):
                        return False
                else:
                    if 3 not in active_filters.difficulties:
                        return False
            elif difficulty not in active_filters.difficulties:
                return False

            # 2. Level / BP 범위 필터
            if active_filters.bp_mode:
                bp = float(chart_data.get('bp', 0.0))
                if bp < active_filters.bp_min or bp > active_filters.bp_max:
                    return False
            else:
                level_str = str(chart_data.get('level', '')).strip()
                if level_str in self.AVAILABLE_LEVELS:
                    level_idx = self.AVAILABLE_LEVELS.index(level_str)
                    min_idx = (
                        self.AVAILABLE_LEVELS.index(active_filters.level_min_str)
                        if active_filters.level_min_str in self.AVAILABLE_LEVELS
                        else 0
                    )
                    max_idx = (
                        self.AVAILABLE_LEVELS.index(active_filters.level_max_str)
                        if active_filters.level_max_str in self.AVAILABLE_LEVELS
                        else len(self.AVAILABLE_LEVELS) - 1
                    )
                    if level_idx < min_idx or level_idx > max_idx:
                        return False

            # 3. 차트 플래그 필터 (ignore_chart, skill_issues, hard_bpm)
            for flag_name, flag_val in [
                ('ignore_chart', getattr(active_filters, 'ignore_chart', 'contain')),
                ('skill_issues', getattr(active_filters, 'skill_issues', 'contain')),
                ('hard_bpm', getattr(active_filters, 'hard_bpm', 'contain')),
            ]:
                chart_flag = bool(chart_data.get(flag_name, False))
                if flag_val == "only" and not chart_flag:
                    return False
                elif flag_val == "off" and chart_flag:
                    return False

            # 4. Clear Type 필터
            if active_filters.clear_types is not None:
                if has_score:
                    if clear_type not in active_filters.clear_types:
                        return False
                else:
                    # 미플레이 채보: PM/FR/Hard/Complete/Easy 등 클리어 타입만 선택된 경우 미플레이는 통과 불가
                    if set(active_filters.clear_types) != {0, 1, 2, 3, 4, 5}:
                        return False

            # 5. Score Rank 필터 (score_min_rank, score_max_rank)
            rank_idx = self.get_score_rank_index(score, has_score, score_below_max, cut_200)
            if rank_idx < active_filters.score_min_rank or rank_idx > active_filters.score_max_rank:
                return False

        return True

    def _resolve_jacket_path(self, arcaea_id: str, difficulty: int) -> str:
        """자켓 썸네일 이미지 경로 추출."""
        if self.thumbnail_service and hasattr(self.thumbnail_service, 'get_path_for_difficulty'):
            try:
                return self.thumbnail_service.get_path_for_difficulty(arcaea_id, difficulty) or ""
            except Exception:
                pass
        return ""

    def _sort_song_list(self, songs: List[dict], sort_mode: str = "score", is_desc: bool = True):
        """팩 내 수록곡 목록 정렬 (in-place). 타이브레이커는 항상 곡명 A->Z."""
        mode = (sort_mode or "score").lower().strip()
        if mode in ('bp',):
            mode = 'level'
        elif mode in ('total_play', 'total_plays', 'play_count'):
            mode = 'total_play_count'

        if mode == "title":
            songs.sort(key=lambda s: s.get('title', '').lower(), reverse=is_desc)
        elif mode == "level":
            if is_desc:
                songs.sort(key=lambda s: (-s.get('bp', 0.0), s.get('title', '').lower()))
            else:
                songs.sort(key=lambda s: (s.get('bp', 0.0), s.get('title', '').lower()))
        elif mode == "s_bp":
            if is_desc:
                songs.sort(key=lambda s: (-s.get('s_bp', 0.0), s.get('title', '').lower()))
            else:
                songs.sort(key=lambda s: (s.get('s_bp', 0.0), s.get('title', '').lower()))
        elif mode == "perceived_bp":
            if is_desc:
                songs.sort(key=lambda s: (-s.get('perceived_bp', 0.0), s.get('title', '').lower()))
            else:
                songs.sort(key=lambda s: (s.get('perceived_bp', 0.0), s.get('title', '').lower()))
        elif mode == "note_count":
            if is_desc:
                songs.sort(key=lambda s: (-s.get('note_count', 0), s.get('title', '').lower()))
            else:
                songs.sort(key=lambda s: (s.get('note_count', 0), s.get('title', '').lower()))
        elif mode == "bpm":
            if is_desc:
                songs.sort(key=lambda s: (-s.get('bpm_num', 0.0), s.get('title', '').lower()))
            else:
                songs.sort(key=lambda s: (s.get('bpm_num', 0.0), s.get('title', '').lower()))
        elif mode == "length":
            if is_desc:
                songs.sort(key=lambda s: (-s.get('length', 0), s.get('title', '').lower()))
            else:
                songs.sort(key=lambda s: (s.get('length', 0), s.get('title', '').lower()))
        elif mode == "recent_played":
            if is_desc:
                songs.sort(key=lambda s: (-s.get('recent_played', 0), s.get('title', '').lower()))
            else:
                songs.sort(key=lambda s: (
                    s.get('recent_played', 0) if s.get('recent_played', 0) > 0 else float('inf'),
                    s.get('title', '').lower()
                ))
        elif mode == "total_play_count":
            if is_desc:
                songs.sort(key=lambda s: (-s.get('total_plays', 0), s.get('title', '').lower()))
            else:
                songs.sort(key=lambda s: (s.get('total_plays', 0), s.get('title', '').lower()))
        elif mode == "this_year_play_count":
            if is_desc:
                songs.sort(key=lambda s: (-s.get('this_year_plays', 0), s.get('title', '').lower()))
            else:
                songs.sort(key=lambda s: (s.get('this_year_plays', 0), s.get('title', '').lower()))
        elif mode == "potential":
            if is_desc:
                songs.sort(key=lambda s: (-s.get('potential', 0.0), s.get('title', '').lower()))
            else:
                songs.sort(key=lambda s: (s.get('potential', 0.0), s.get('title', '').lower()))
        elif mode == "max":
            def song_max_key_desc(s: dict):
                if not s.get('hasScore', False):
                    return (1, float('inf'), float('inf'), s.get('title', '').lower())
                loss = s.get('scoreBelowMax', float('inf'))
                bp = float(s.get('bp', 0.0) or 0.0)
                return (0, loss, -bp, s.get('title', '').lower())

            def song_max_key_asc(s: dict):
                if not s.get('hasScore', False):
                    return (1, float('-inf'), float('inf'), s.get('title', '').lower())
                loss = s.get('scoreBelowMax', 0)
                bp = float(s.get('bp', 0.0) or 0.0)
                return (0, -loss, bp, s.get('title', '').lower())

            if is_desc:
                songs.sort(key=song_max_key_desc)
            else:
                songs.sort(key=song_max_key_asc)
        elif mode == "version":
            # Version 정렬 시 팩 내부 악곡끼리는 항상 최고 난이도 BP 내림차순(가장 어려운 곡이 상단), 동률 시 title A->Z
            songs.sort(key=lambda s: (-s.get('bp', 0.0), s.get('title', '').lower()))
        else:
            # 기본값: score
            if is_desc:
                songs.sort(key=lambda s: (-s.get('score', 0), -s.get('bp', 0.0), s.get('title', '').lower()))
            else:
                songs.sort(key=lambda s: (s.get('score', 0), s.get('bp', 0.0), s.get('title', '').lower()))

    def sort_packs(
        self,
        packs: List[dict],
        sort_mode: str = "version",
        is_desc: bool = True
    ) -> List[dict]:
        """
        팩 정렬 및 다계층 타이브레이커 적용.
        모든 내림차순 정렬은 수치 키를 음수화하고 reverse=False로 정렬하여,
        문자열 타이브레이커의 prefix 순서("Pack" < "Pack Two") 및 A->Z 순서를 완벽히 보존한다.
        """
        mode = (sort_mode or "version").lower().strip()
        if mode in ('total_play', 'total_plays', 'play_count'):
            mode = 'total_play_count'
        elif mode in ('bp',):
            mode = 'level'

        sorted_packs = []

        if mode == "version":
            # SemVer 정수 튜플 정렬
            # 2순위 타이브레이커: 동일버전 내에서는 bp가 가장 높은 악곡이 속해있는 팩이 위로 (-top_bp)
            # 3순위 타이브레이커: 팩명 알파벳순 (A->Z 자연 순서)
            if is_desc:
                def v_desc_key(p: dict):
                    v = self.parse_version_tuple(p.get('version', ''), ascending=False)
                    if v == (float('-inf'), float('-inf'), float('-inf')):
                        v_key = (float('inf'), float('inf'), float('inf'))
                    else:
                        v_key = (-v[0], -v[1], -v[2])
                    return (v_key, -float(p.get('max_bp', p.get('top_bp', 0.0))), p.get('name', '').lower())

                sorted_packs = sorted(packs, key=v_desc_key, reverse=False)
            else:
                def v_asc_key(p: dict):
                    v = self.parse_version_tuple(p.get('version', ''), ascending=True)
                    # 동일버전 내에서는 bp가 가장 높은 악곡이 속해있는 팩이 위로 (-max_bp)
                    return (v, -float(p.get('max_bp', p.get('top_bp', 0.0))), p.get('name', '').lower())

                sorted_packs = sorted(packs, key=v_asc_key, reverse=False)

        elif mode == "title":
            sorted_packs = sorted(
                packs,
                key=lambda p: p.get('name', '').lower(),
                reverse=is_desc
            )

        elif mode == "score":
            if is_desc:
                sorted_packs = sorted(
                    packs,
                    key=lambda p: (-p.get('avg_score', 0), p.get('name', '').lower()),
                    reverse=False
                )
            else:
                sorted_packs = sorted(
                    packs,
                    key=lambda p: (p.get('avg_score', 0), p.get('name', '').lower()),
                    reverse=False
                )

        elif mode == "potential":
            if is_desc:
                sorted_packs = sorted(
                    packs,
                    key=lambda p: (-p.get('top_potential', {}).get('value', 0.0), p.get('name', '').lower()),
                    reverse=False
                )
            else:
                sorted_packs = sorted(
                    packs,
                    key=lambda p: (p.get('top_potential', {}).get('value', 0.0), p.get('name', '').lower()),
                    reverse=False
                )

        elif mode == "max":
            def _get_loss_key(s_below):
                if s_below <= 0:
                    return float('inf')
                # 원시 점수가 전달된 경우(목 데이터 테스트 등 9900000+): 점수가 높을수록 손실 적음
                if s_below > 10000:
                    return -s_below
                # 손실 판정 수가 전달된 경우: 손실이 적을수록 MAX에 가까움
                return s_below

            if is_desc:
                def max_desc_key(p: dict):
                    mc = p.get('max_count', 0)
                    s_below = p.get('top_score_below_max', 0)
                    loss_key = _get_loss_key(s_below)
                    cnt = p.get('count_at_top_score_below_max', 0)
                    return (-mc, loss_key, -cnt, p.get('name', '').lower())

                sorted_packs = sorted(packs, key=max_desc_key, reverse=False)
            else:
                def max_asc_key(p: dict):
                    mc = p.get('max_count', 0)
                    s_below = p.get('top_score_below_max', 0)
                    loss_key = _get_loss_key(s_below)
                    rev_loss_key = -loss_key if loss_key != float('inf') else float('-inf')
                    cnt = p.get('count_at_top_score_below_max', 0)
                    return (mc, rev_loss_key, cnt, p.get('name', '').lower())

                sorted_packs = sorted(packs, key=max_asc_key, reverse=False)

        elif mode == "total_play_count":
            if is_desc:
                sorted_packs = sorted(
                    packs,
                    key=lambda p: (-p.get('total_plays', 0), p.get('name', '').lower()),
                    reverse=False
                )
            else:
                sorted_packs = sorted(
                    packs,
                    key=lambda p: (p.get('total_plays', 0), p.get('name', '').lower()),
                    reverse=False
                )

        elif mode == "this_year_play_count":
            if is_desc:
                sorted_packs = sorted(
                    packs,
                    key=lambda p: (-p.get('this_year_total_plays', 0), p.get('name', '').lower()),
                    reverse=False
                )
            else:
                sorted_packs = sorted(
                    packs,
                    key=lambda p: (p.get('this_year_total_plays', 0), p.get('name', '').lower()),
                    reverse=False
                )

        elif mode == "length":
            # 팩별 곡 길이 합산(=팩의 총 러닝타임)
            if is_desc:
                sorted_packs = sorted(
                    packs,
                    key=lambda p: (-p.get('total_length', 0), p.get('name', '').lower()),
                    reverse=False
                )
            else:
                sorted_packs = sorted(
                    packs,
                    key=lambda p: (p.get('total_length', 0), p.get('name', '').lower()),
                    reverse=False
                )

        elif mode == "recent_played":
            if is_desc:
                sorted_packs = sorted(
                    packs,
                    key=lambda p: (-p.get('latest_played_time', 0), p.get('name', '').lower()),
                    reverse=False
                )
            else:
                sorted_packs = sorted(
                    packs,
                    key=lambda p: (
                        p.get('latest_played_time', 0) if p.get('latest_played_time', 0) > 0 else float('inf'),
                        p.get('name', '').lower()
                    ),
                    reverse=False
                )

        elif mode == "level":
            # 팩 내 최고 BP 악곡 기준 비교
            if is_desc:
                sorted_packs = sorted(
                    packs,
                    key=lambda p: (-float(p.get('top_bp', 0.0)), p.get('name', '').lower()),
                    reverse=False
                )
            else:
                sorted_packs = sorted(
                    packs,
                    key=lambda p: (float(p.get('top_bp', 0.0)), p.get('name', '').lower()),
                    reverse=False
                )

        elif mode == "s_bp":
            # 팩 내 최고 S-BP 악곡 기준 비교
            if is_desc:
                sorted_packs = sorted(
                    packs,
                    key=lambda p: (-float(p.get('top_s_bp', 0.0)), p.get('name', '').lower()),
                    reverse=False
                )
            else:
                sorted_packs = sorted(
                    packs,
                    key=lambda p: (float(p.get('top_s_bp', 0.0)), p.get('name', '').lower()),
                    reverse=False
                )

        elif mode == "perceived_bp":
            # 팩 내 최고 Perceived-BP 악곡 기준 비교
            if is_desc:
                sorted_packs = sorted(
                    packs,
                    key=lambda p: (-float(p.get('top_perceived_bp', 0.0)), p.get('name', '').lower()),
                    reverse=False
                )
            else:
                sorted_packs = sorted(
                    packs,
                    key=lambda p: (float(p.get('top_perceived_bp', 0.0)), p.get('name', '').lower()),
                    reverse=False
                )

        elif mode == "note_count":
            # 팩 내 최고 Note Count 악곡 기준 비교
            if is_desc:
                sorted_packs = sorted(
                    packs,
                    key=lambda p: (-int(p.get('top_note_count', 0)), p.get('name', '').lower()),
                    reverse=False
                )
            else:
                sorted_packs = sorted(
                    packs,
                    key=lambda p: (int(p.get('top_note_count', 0)), p.get('name', '').lower()),
                    reverse=False
                )

        elif mode == "bpm":
            # 팩 내 최고 BPM 악곡 기준 비교
            if is_desc:
                sorted_packs = sorted(
                    packs,
                    key=lambda p: (-float(p.get('top_bpm', 0.0)), p.get('name', '').lower()),
                    reverse=False
                )
            else:
                sorted_packs = sorted(
                    packs,
                    key=lambda p: (float(p.get('top_bpm', 0.0)), p.get('name', '').lower()),
                    reverse=False
                )

        else:
            sorted_packs = list(packs)

        # displayValue 및 top_representative 설정
        for p in sorted_packs:
            p['displayValue'] = self.format_pack_display_value(p, mode)
            p['top_representative'] = self.build_top_representative(p, mode)

        return sorted_packs

    @classmethod
    def build_top_representative(cls, pack: dict, sort_mode: str) -> dict:
        """정렬 모드에 맞춰 팩 대표곡의 썸네일, 타이틀, 난이도, 수치 메타데이터 패키징."""
        mode = (sort_mode or "").lower().strip()
        if mode in ('total_play', 'total_plays', 'play_count'):
            mode = 'total_play_count'
        elif mode in ('bp',):
            mode = 'level'

        rec = None
        val_str = ""
        is_max = False

        if mode == "score":
            rec = pack.get('top_score')
            if rec and (rec.get('score', 0) > 0 or rec.get('value', 0) > 0):
                s = rec.get('score', 0) or rec.get('value', 0)
                val_str = f"{s:,}"
                is_max = bool(rec.get('is_max', False))
            else:
                rec = None
        elif mode == "potential":
            rec = pack.get('top_potential')
            if rec and (rec.get('potential', 0.0) > 0 or rec.get('value', 0.0) > 0):
                pot = rec.get('potential', 0.0) or rec.get('value', 0.0)
                val_str = f"{pot:.4f}"
            else:
                rec = None
        elif mode == "max":
            rec = pack.get('top_max_record') or pack.get('top_score')
            if rec and (rec.get('score', 0) > 0 or rec.get('value', 0) is not None or rec.get('song_id')):
                mc = pack.get('max_count', 0)
                if mc > 0:
                    val_str = f"{mc} MAX"
                    is_max = True
                else:
                    s_below = pack.get('top_score_below_max', 0)
                    val_str = f"MAX-{s_below}" if s_below > 0 else "-"
            else:
                rec = None
        elif mode == "level":
            rec = pack.get('top_bp_record')
            if rec and rec.get('value', 0.0) > 0:
                val_str = f"{float(rec.get('value', 0.0)):.1f}"
            else:
                rec = None
        elif mode == "s_bp":
            rec = pack.get('top_s_bp_record')
            if rec and rec.get('value', 0.0) > 0:
                val_str = f"{float(rec.get('value', 0.0)):.2f}"
            else:
                rec = None
        elif mode == "perceived_bp":
            rec = pack.get('top_perceived_bp_record')
            if rec and rec.get('value', 0.0) > 0:
                val_str = f"{float(rec.get('value', 0.0)):.2f}"
            else:
                rec = None
        elif mode == "note_count":
            rec = pack.get('top_note_count_record')
            if rec and rec.get('value', 0) > 0:
                val_str = f"{int(rec.get('value', 0)):,}"
            else:
                rec = None
        elif mode == "bpm":
            rec = pack.get('top_bpm_record')
            if rec:
                b_str = pack.get('top_bpm_str')
                b_val = pack.get('top_bpm', 0.0)
                val_str = str(b_str) if b_str else (str(int(b_val)) if b_val > 0 else "")
                rec = dict(rec)
                rec['diff_with_level'] = ""
            else:
                rec = None
        elif mode == "recent_played":
            rec = pack.get('latest_played_record')
            if rec and pack.get('latest_played_time', 0) > 0:
                val_str = cls.format_timestamp(pack.get('latest_played_time', 0))
            else:
                rec = None
        elif mode == "version":
            rec = pack.get('version_rep_record') or pack.get('top_bp_record')
            if rec:
                v = pack.get('version')
                val_str = f"v{v}" if v else ""
            else:
                rec = None

        if not rec or not rec.get('song_id'):
            return {
                'has_song': False,
                'song_id': '',
                'song_title': '',
                'diff_name': '',
                'diff_index': -1,
                'diff_color_tag': '',
                'level_str': '',
                'diff_with_level': '',
                'value_str': '',
                'jacket_path': '',
                'is_max': False,
            }

        return {
            'has_song': True,
            'song_id': rec.get('song_id', ''),
            'song_title': rec.get('song_title', ''),
            'diff_name': rec.get('diff_name', ''),
            'diff_index': rec.get('diff_index', -1),
            'diff_color_tag': rec.get('diff_color_tag', ''),
            'level_str': rec.get('level_str', ''),
            'diff_with_level': rec.get('diff_with_level', ''),
            'value_str': val_str or pack.get('displayValue', ''),
            'jacket_path': rec.get('jacket_path', ''),
            'is_max': is_max,
        }
