from typing import Any
from models.constants import SCORE_RANKS
from services.statistics_service import FilterParams


class StatisticsFilterManager:
    """Manages filter states, parameters, available options, active filter models, and selection restoration."""

    def __init__(self, handler: Any, service: Any):
        self._handler = handler
        self._service = service

        # Filter states
        self._filter_difficulties = [0, 1, 2, 3, 4]  # All difficulties
        self._filter_include_inscribed = True  # Inscribed filter (default: True)
        self._filter_level_min_str = "1"  # Level string for min
        self._filter_level_max_str = "12"  # Level string for max
        self._filter_bp_mode = False  # False = level range, True = BP range
        self._filter_bp_min = 1.0
        self._filter_bp_max = 13.0
        self._filter_ignore_chart = "contain"  # "off", "contain", "only"
        self._filter_skill_issues = "contain"
        self._filter_hard_bpm = "contain"
        self._filter_score_min_rank = 0  # Index in SCORE_RANKS (0 = '-')
        self._filter_score_max_rank = len(SCORE_RANKS) - 1  # Index in SCORE_RANKS (last = 'PM')
        self._filter_clear_types = [0, 1, 2, 3, 4, 5]  # All clear types

    def get_filter_params(self) -> FilterParams:
        """현재 필터 상태를 FilterParams로 변환."""
        return FilterParams(
            difficulties=self._filter_difficulties,
            level_min_str=self._filter_level_min_str,
            level_max_str=self._filter_level_max_str,
            bp_mode=self._filter_bp_mode,
            bp_min=self._filter_bp_min,
            bp_max=self._filter_bp_max,
            ignore_chart=self._filter_ignore_chart,
            skill_issues=self._filter_skill_issues,
            hard_bpm=self._filter_hard_bpm,
            score_min_rank=self._filter_score_min_rank,
            score_max_rank=self._filter_score_max_rank,
            clear_types=self._filter_clear_types,
            include_inscribed=self._filter_include_inscribed,
        )

    def set_filter(self, filter_type: str, value: Any):
        """Set a specific filter value."""
        if hasattr(value, 'toVariant'):
            value = value.toVariant()

        if filter_type == 'difficulties':
            try:
                self._filter_difficulties = [int(v) for v in value] if value else []
            except Exception as e:
                print(f"Error converting difficulties filter: {e}")
                self._filter_difficulties = list(value) if value else []
        elif filter_type == 'level_min_str':
            self._filter_level_min_str = str(value) if value is not None else "1"
        elif filter_type == 'level_max_str':
            self._filter_level_max_str = str(value) if value is not None else "12"
        elif filter_type == 'bp_mode':
            self._filter_bp_mode = bool(value)
        elif filter_type == 'bp_min':
            self._filter_bp_min = float(value) if value is not None else 1.0
        elif filter_type == 'bp_max':
            self._filter_bp_max = float(value) if value is not None else 13.0
        elif filter_type == 'ignore_chart':
            self._filter_ignore_chart = str(value) if value else 'off'
        elif filter_type == 'skill_issues':
            self._filter_skill_issues = str(value) if value else 'off'
        elif filter_type == 'hard_bpm':
            self._filter_hard_bpm = str(value) if value else 'off'
        elif filter_type == 'clear_types':
            self._filter_clear_types = list(value) if value else []
        elif filter_type == 'score_min_rank':
            self._filter_score_min_rank = int(value) if value is not None else 0
        elif filter_type == 'score_max_rank':
            self._filter_score_max_rank = int(value) if value is not None else len(SCORE_RANKS) - 1
        elif filter_type in ('include_inscribed', 'includeInscribed'):
            self._filter_include_inscribed = bool(value)

    @property
    def available_levels(self):
        return self._service.available_levels

    @property
    def available_bps(self):
        return self._service.available_bps

    @property
    def level_boundaries(self):
        return self._service.level_boundaries

    @property
    def score_ranks(self):
        return SCORE_RANKS

    @property
    def active_filters_model(self):
        filters = []

        # Flags Filter
        flags = []
        if self._filter_ignore_chart != "contain":
            flags.append({"icon": "⛔", "state": self._filter_ignore_chart})
        if self._filter_skill_issues != "contain":
            flags.append({"icon": "⚠️", "state": self._filter_skill_issues})
        if self._filter_hard_bpm != "contain":
            flags.append({"icon": "⏪", "state": self._filter_hard_bpm})

        if flags:
            filters.append({
                "type": "flags",
                "data": flags
            })

        # Clear Type Filter
        if len(self._filter_clear_types) < 6:
            if self._filter_clear_types:
                LOGICAL_ORDER = [0, 4, 1, 5, 2, 3]
                SHORT_NAMES = {0: "L", 4: "C", 1: "C", 5: "C", 2: "F", 3: "P"}

                indices = [LOGICAL_ORDER.index(ct) for ct in self._filter_clear_types if ct in LOGICAL_ORDER]
                if indices:
                    min_idx = min(indices)
                    max_idx = max(indices)
                    filters.append({
                        "type": "clear",
                        "minIdx": min_idx,
                        "maxIdx": max_idx,
                        "minStr": SHORT_NAMES[LOGICAL_ORDER[min_idx]],
                        "maxStr": SHORT_NAMES[LOGICAL_ORDER[max_idx]],
                        "isSingle": len(indices) == 1
                    })

        # Score Range Filter
        if self._filter_score_min_rank != 0 or self._filter_score_max_rank != len(SCORE_RANKS) - 1:
            filters.append({
                "type": "score",
                "minIdx": self._filter_score_min_rank,
                "maxIdx": self._filter_score_max_rank,
                "minStr": SCORE_RANKS[self._filter_score_min_rank],
                "maxStr": SCORE_RANKS[self._filter_score_max_rank]
            })

        # Level / BP Range Filter
        if self._filter_bp_mode:
            bps = self._service.available_bps
            min_bp = bps[0] if bps else 1.0
            max_bp = bps[-1] if bps else 13.0
            if abs(self._filter_bp_min - min_bp) > 1e-4 or abs(self._filter_bp_max - max_bp) > 1e-4:
                filters.append({
                    "type": "bp",
                    "min": self._filter_bp_min,
                    "max": self._filter_bp_max
                })
        else:
            if self._filter_level_min_str != "1" or self._filter_level_max_str != "12":
                filters.append({
                    "type": "level",
                    "min": self._filter_level_min_str.replace("+", "⁺"),
                    "max": self._filter_level_max_str.replace("+", "⁺")
                })

        # Difficulty Filter (Always shown)
        byd_active = (3 in self._filter_difficulties)
        ins_active = self._filter_include_inscribed
        has_ins = self._service.has_any_inscribed_played()
        show_ins_mark = has_ins and (byd_active != ins_active)

        filters.append({
            "type": "difficulties",
            "data": [
                {"diff": d, "active": d in self._filter_difficulties}
                for d in [0, 1, 2, 4, 3]
            ],
            "showInsMark": show_ins_mark,
            "insActive": ins_active,
        })

        return filters

    def restore_selection(self, selection_mode: str):
        """리스트 갱신 후 선택 상태를 복원/재설정한다."""
        old_selected_index = self._handler._selected_index
        self._handler._selected_index = -1
        self._handler._selected_item = None
        selected_details = None
        list_items = self._handler._list_model.get_items()

        if selection_mode == 'first':
            if list_items:
                self._handler._selected_index = 0
                self._handler._selected_item = self._handler._list_model.get_item(0)
                self._handler._selected_song_db_id = self._handler._selected_item.get('songDbId')

                if self._handler._display_mode == "chart":
                    self._handler._selected_difficulty = self._handler._selected_item.get('difficulty', 2)
                else:
                    best_diff = self._service.get_best_diff_for_sort(
                        self._handler._selected_item, self._handler._sort_mode
                    )
                    if best_diff >= 0:
                        self._handler._selected_difficulty = best_diff
                    else:
                        all_diffs = self._handler._get_item_detail_difficulties(self._handler._selected_item)
                        selected_details = all_diffs
                        for diff_num in [3, 4, 2, 1, 0]:  # BYD, ETR, FTR, PRS, PST
                            for diff_item in all_diffs:
                                if (
                                    diff_item.get('difficulty') == diff_num
                                    and not diff_item.get('isFiltered', False)
                                ):
                                    self._handler._selected_difficulty = diff_num
                                    break
                            else:
                                continue
                            break

        elif selection_mode == 'adjacent_fallback':
            if self._handler._selected_song_db_id is not None:
                found = False
                fallback_item = None
                fallback_index = -1

                for i, item in enumerate(list_items):
                    if item.get('songDbId') != self._handler._selected_song_db_id:
                        continue

                    if self._handler._display_mode == "chart":
                        if item.get('difficulty') == self._handler._selected_difficulty:
                            self._handler._selected_index = i
                            self._handler._selected_item = item
                            found = True
                            break
                        if fallback_item is None:
                            fallback_item = item
                            fallback_index = i
                    else:
                        self._handler._selected_index = i
                        self._handler._selected_item = item
                        found = True
                        all_diffs = self._handler._get_item_detail_difficulties(item)
                        selected_details = all_diffs
                        current_diff_available = any(
                            d.get('difficulty') == self._handler._selected_difficulty
                            and not d.get('isFiltered', False)
                            for d in all_diffs
                        )
                        if not current_diff_available:
                            for diff_num in [3, 4, 2, 1, 0]:
                                for diff_item in all_diffs:
                                    if (
                                        diff_item.get('difficulty') == diff_num
                                        and not diff_item.get('isFiltered', False)
                                    ):
                                        self._handler._selected_difficulty = diff_num
                                        break
                                else:
                                    continue
                                break
                        break

                if not found and self._handler._display_mode == "chart" and fallback_item:
                    self._handler._selected_index = fallback_index
                    self._handler._selected_item = fallback_item
                    self._handler._selected_difficulty = fallback_item.get('difficulty', 2)

        else:
            if self._handler._selected_song_db_id is not None:
                for i, item in enumerate(list_items):
                    if item.get('songDbId') != self._handler._selected_song_db_id:
                        continue

                    if self._handler._display_mode == "chart":
                        if item.get('difficulty') == self._handler._selected_difficulty:
                            self._handler._selected_index = i
                            self._handler._selected_item = item
                            break
                    else:
                        self._handler._selected_index = i
                        self._handler._selected_item = item
                        break

        self._handler._attach_details_to_selected(selected_details)
        self._handler.dataChanged.emit()

        if (
            selection_mode in ('first', 'restore_always_emit', 'adjacent_fallback')
            or self._handler._selected_index != old_selected_index
        ):
            self._handler.selectedItemChanged.emit()
