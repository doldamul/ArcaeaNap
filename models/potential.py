"""곡 포텐셜 산출 로직."""
import math


def calculate_potential(
    chart_constant: float,
    note_count: int,
    score: int,
    shiny_perfect: int,
) -> float | None:
    """
    채보 기록의 곡 포텐셜을 산출한다.

    반환값:
    - None: chart_constant/note_count 미제공, 또는 데이터 유효성 실패
    - float >= 0.0: 계산값 (음수이면 0.0으로 클램프, 소수점 이하 6자리 버림)
    """
    if chart_constant <= 0 or note_count <= 0:
        return None

    if shiny_perfect < 0 or shiny_perfect > note_count:
        return None

    # 점수에 대응하는 최소 shiny_perfect 요구량 검사
    min_shiny_required = note_count - math.floor(score * note_count / 5_000_000) / 2
    if min_shiny_required > shiny_perfect:
        return None

    if score >= 10_000_000:
        raw = chart_constant + 2
    elif score >= 9_800_000:
        raw = chart_constant + 1 + (score - 9_800_000) / 200_000
    else:
        raw = chart_constant + (score - 9_500_000) / 300_000

    return math.floor(max(raw, 0.0) * 1_000_000) / 1_000_000
