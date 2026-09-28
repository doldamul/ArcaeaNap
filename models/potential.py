"""곡 포텐셜 산출 로직."""
import math


def calculate_potential(
    chart_constant: float,
    note_count: int,
    score: int,
    shiny_perfect: int,
    is_cleared: bool = False,
) -> float | None:
    """
    채보 기록의 곡 포텐셜을 산출한다 (Arcaea 7.0 공식).

    반환값:
    - None: chart_constant/note_count 미제공, 또는 데이터 유효성 실패
    - float >= 0.0: 계산값 (기본 포텐셜 + 클리어 보너스(+0.2), 소수점 이하 4자리 버림)
    """
    if chart_constant <= 0 or note_count <= 0:
        return None

    if score < 0 or score > 10_000_000 + note_count:
        return None

    if shiny_perfect < 0 or shiny_perfect > note_count:
        return None

    # 점수에 대응하는 최소 shiny_perfect 요구량 검사
    if score > 10_000_000 and shiny_perfect < (score - 10_000_000):
        return None

    min_shiny_required = note_count - math.floor(score * note_count / 5_000_000) / 2
    if min_shiny_required > shiny_perfect:
        return None

    if score >= 10_000_000:
        base = chart_constant + 2.0
    elif score >= 9_800_000:
        base = chart_constant + 1.0 + (score - 9_800_000) / 200_000
    elif score >= 9_500_000:
        base = chart_constant + 0.0 + (score - 9_500_000) / 300_000
    elif score >= 8_600_000:
        base = chart_constant - 1.0 + (score - 8_600_000) / 900_000
    else:
        base = 0.0

    base = max(base, 0.0)
    bonus = 0.2 if is_cleared else 0.0
    final = base + bonus

    return math.floor(round(final * 10_000, 6)) / 10_000


def calculate_total_potential(
    potentials: list[float],
    fixed_denominator: bool = True,
) -> float:
    """
    Arcaea 7.0 최종 포텐셜 (Total Potential)을 산출한다 (B50 + B10 체계).

    공식:
        최종 포텐셜 = (sum(B50) + sum(B10)) / 60
        = (B50 평균 * 5 + B10 평균 * 1) / 6

    매개변수:
    - potentials: 채보별 최고 포텐셜 목록 (float)
    - fixed_denominator: True이면 Arcaea 공식 시스템과 동일하게 분모를 60으로 고정
      (50곡 미만일 경우 미달 슬롯을 0점으로 계산).
      False이면 실제 채보 수 기반 가중치로 계산.

    반환값:
    - float >= 0.0: 최종 포텐셜 (소수점 이하 4자리 버림)
    """
    if not potentials:
        return 0.0

    valid_pots = sorted(
        [p for p in potentials if p is not None and p >= 0.0],
        reverse=True,
    )
    if not valid_pots:
        return 0.0

    b50 = valid_pots[:50]
    b10 = valid_pots[:10]

    sum_b50 = sum(b50)
    sum_b10 = sum(b10)

    if fixed_denominator:
        denom = 60.0
    else:
        denom = float(len(b50) + len(b10))
        if denom <= 0:
            return 0.0

    raw = (sum_b50 + sum_b10) / denom
    return math.floor(round(raw * 10_000, 6)) / 10_000
