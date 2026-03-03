"""
ArcaeaNap 공통 상수 정의.

모든 난이도/점수/랭크 관련 상수의 단일 진실 공급원(Single Source of Truth).
"""

# === 난이도 상수 ===

# 난이도 코드 문자열 → 정수 매핑
DIFFICULTY_CODE_TO_INT: dict[str, int] = {
    'pst': 0, 'prs': 1, 'ftr': 2, 'byd': 3, 'etr': 4
}

# 난이도 정수 → 약칭 매핑
DIFFICULTY_NAMES: dict[int, str] = {
    0: 'PST', 1: 'PRS', 2: 'FTR', 3: 'BYD', 4: 'ETR'
}

# 난이도 정수 → 색상 코드 매핑
DIFFICULTY_COLORS: dict[int, str] = {
    0: '#00A0E9',  # PST - 파랑
    1: '#50C050',  # PRS - 초록
    2: '#A060FF',  # FTR - 보라
    3: '#E04040',  # BYD - 빨강
    4: '#808080',  # ETR - 회색
}

# UI 표시 순서: PST → PRS → FTR → ETR → BYD
DIFFICULTY_ORDER: list[int] = [0, 1, 2, 4, 3]

# 모든 난이도 정수 집합 (필터링용)
ALL_DIFFICULTIES: set[int] = {0, 1, 2, 3, 4}


# === 점수/랭크 상수 ===

# Score Range 필터용 랭크 라벨 (인덱스 기반)
SCORE_RANKS: list[str] = [
    '-', 'D', 'C', 'B', 'A', 'AA', 'EX', 'EX+', '99.5%', '99.8%', 'PM', 'MAX'
]

# 랭크 계산용 분기점 (score 기준, 내림차순)
# (최소 점수, 랭크 문자열) — 첫 번째로 만족하는 조건이 적용됨
RANK_THRESHOLDS: list[tuple[int, str]] = [
    (10_000_000, 'PM'),
    (9_900_000,  'EX+'),
    (9_800_000,  'EX'),
    (9_500_000,  'AA'),
    (9_200_000,  'A'),
    (8_900_000,  'B'),
    (8_600_000,  'C'),
    (0,          'D'),
]


def calculate_rank(score: int | None) -> str:
    """점수 → 랭크 문자열 변환. RANK_THRESHOLDS 상수 참조."""
    if score is None:
        return ""
    for threshold, rank in RANK_THRESHOLDS:
        if score >= threshold:
            return rank
    return "D"


# === 포텐셜 등급 상수 ===

# (최소 rating, 색상, 뱃지 텍스트, 별 개수)
# 내림차순 정렬. 조회 시 rating >= threshold 인 첫 항목을 사용한다.
# 색상/뱃지/별의 분기점이 각각 다르므로, 모든 고유 분기점을 병합한 통합 테이블이다.
POTENTIAL_GRADES: list[tuple[int, str, str, int]] = [
    (1300, '#D14A6B', 'TRIPLE STAR', 3),
    (1250, '#C12955', 'DOUBLE STAR', 2),
    (1200, '#C12955', 'STAR',        1),
    (1100, '#C62828', 'RED',         0),
    (1000, '#8E24AA', 'PURPLE',      0),
    (700,  '#AB47BC', 'PURPLE',      0),
    (300,  '#4CAF50', 'GREEN',       0),
    (0,    '#29B6F6', 'BLUE',        0),
]

DEFAULT_POTENTIAL_COLOR: str = '#999999'


# === 랭크 색상 상수 ===

RANK_COLORS: dict[str, str] = {
    'PM':  '#00aaaa',
    'EX+': '#5865F2',
    'EX':  '#5865F2',
    'AA':  '#9050B0',
    'A':   '#9050B0',
    'B':   '#D04040',
    'C':   '#D04040',
    'D':   '#D04040',
}

DEFAULT_RANK_COLOR: str = '#666666'


# === 클리어 타입 텍스트 상수 ===

CLEAR_TYPE_TEXTS: dict[int, str] = {
    0: 'Track Lost',
    1: 'Track Complete',
    2: 'Full Recall',
    3: 'Pure Memory',
    4: 'Easy Clear',
    5: 'Hard Clear',
}

CLEAR_TYPE_ABBREVIATIONS: dict[int, str] = {
    0: 'Lost',
    1: 'N. Clear',
    2: 'FR',
    3: 'PM',
    4: 'E. Clear',
    5: 'H. Clear',
}
