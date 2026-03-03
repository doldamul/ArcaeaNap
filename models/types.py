"""
ArcaeaNap 공통 타입 정의.

게임 도메인의 열거형 타입을 정의한다.
"""
from enum import IntEnum


class Difficulty(IntEnum):
    """Arcaea 난이도. 값은 Arcaea Online 내부 코드를 따른다."""
    PST = 0
    PRS = 1
    FTR = 2
    ETR = 4  # 주의: 3이 아닌 4
    BYD = 3  # 주의: 4가 아닌 3


class ClearType(IntEnum):
    """Arcaea 클리어 타입."""
    TRACK_LOST = 0
    COMPLETE = 1
    FULL_RECALL = 2
    PURE_MEMORY = 3
    EASY_CLEAR = 4
    HARD_CLEAR = 5
