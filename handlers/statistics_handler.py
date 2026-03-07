"""Statistics 탭 핸들러: QML 브릿지, UI 상태 관리."""
from PyQt6.QtCore import QObject, pyqtSlot, pyqtSignal, pyqtProperty, QVariant

from configuration import config
from models.constants import SCORE_RANKS
from services.statistics_service import StatisticsService, FilterParams
from handlers.statistics_list_model import StatisticsListModel


class StatisticsHandler(QObject):
    dataChanged = pyqtSignal()
    selectedItemChanged = pyqtSignal()

    def __init__(self):
        super().__init__()
        self._service = StatisticsService()

        # UI 상태
        self._display_mode = "song"  # "song" or "chart"
        self._sort_mode = "title"
        self._sort_ascending = True
        self._search_text = ""
        self._selected_index = -1

        # Filters
        self._filter_difficulties = [0, 1, 2, 3, 4]  # All difficulties
        self._filter_level_min_str = "1"  # Level string for min
        self._filter_level_max_str = "12"  # Level string for max
        self._filter_bp_mode = False  # False = level range, True = BP range
        self._filter_bp_min = 1.0
        self._filter_bp_max = 13.0
        self._filter_ignore_chart = "contain"  # "off", "contain", "only"
        self._filter_skill_issues = "contain"
        self._filter_score_min_rank = 0  # Index in SCORE_RANKS (0 = '-')
        self._filter_score_max_rank = len(SCORE_RANKS) - 1  # Index in SCORE_RANKS (last = 'PM')
        self._filter_clear_types = [0, 1, 2, 3, 4, 5]  # All clear types

        # Processed list
        self._list_model = StatisticsListModel(self)
        self._selected_item = None

        # Selection state for mode sync
        self._selected_song_id = None  # arcaea_id of selected song
        self._selected_difficulty = 2  # Default to FTR (0=PST,1=PRS,2=FTR,3=BYD,4=ETR)

        self._service.load_data(config['general']['cache_path'])
        self._full_rebuild('first')

    def _get_filter_params(self) -> FilterParams:
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
            score_min_rank=self._filter_score_min_rank,
            score_max_rank=self._filter_score_max_rank,
            clear_types=self._filter_clear_types,
        )

    def _get_item_detail_difficulties(self, item):
        """선택 보정/상세 표시에 필요한 allDifficulties를 on-demand로 조회."""
        if not item:
            return []
        arcaea_id = item.get('arcaeaId')
        if not arcaea_id:
            return []
        return self._service.build_selected_item_details(
            arcaea_id,
            self._get_filter_params()
        )

    def _attach_details_to_selected(self, details=None):
        """현재 선택 아이템에만 상세 payload(allDifficulties)를 주입."""
        if not self._selected_item:
            return
        selected_copy = dict(self._selected_item)
        if details is None:
            details = self._get_item_detail_difficulties(selected_copy)
        selected_copy['allDifficulties'] = details

        # 상세 헤더의 songTotalPlayCount가 항상 현재 필터 기준이 되도록 보정한다.
        if details:
            selected_copy['songTotalPlayCount'] = sum(
                int(d.get('totalPlayCount', 0) or 0)
                for d in details
                if not d.get('isFiltered', False)
            )

        self._selected_item = selected_copy

    def _restore_selection(self, selection_mode: str):
        """리스트 갱신 후 선택 상태를 복원/재설정한다."""
        old_selected_index = self._selected_index
        self._selected_index = -1
        self._selected_item = None
        selected_details = None
        list_items = self._list_model.get_items()

        if selection_mode == 'first':
            if list_items:
                self._selected_index = 0
                self._selected_item = self._list_model.get_item(0)
                self._selected_song_id = self._selected_item.get('arcaeaId')

                if self._display_mode == "chart":
                    self._selected_difficulty = self._selected_item.get('difficulty', 2)
                else:
                    best_diff = self._service.get_best_diff_for_sort(
                        self._selected_item, self._sort_mode
                    )
                    if best_diff >= 0:
                        self._selected_difficulty = best_diff
                    else:
                        all_diffs = self._get_item_detail_difficulties(self._selected_item)
                        selected_details = all_diffs
                        for diff_num in [3, 4, 2, 1, 0]:  # BYD, ETR, FTR, PRS, PST
                            for diff_item in all_diffs:
                                if (
                                    diff_item.get('difficulty') == diff_num
                                    and not diff_item.get('isFiltered', False)
                                ):
                                    self._selected_difficulty = diff_num
                                    break
                            else:
                                continue
                            break

        elif selection_mode == 'adjacent_fallback':
            if self._selected_song_id:
                found = False
                fallback_item = None
                fallback_index = -1

                for i, item in enumerate(list_items):
                    if item.get('arcaeaId') != self._selected_song_id:
                        continue

                    if self._display_mode == "chart":
                        if item.get('difficulty') == self._selected_difficulty:
                            self._selected_index = i
                            self._selected_item = item
                            found = True
                            break
                        if fallback_item is None:
                            fallback_item = item
                            fallback_index = i
                    else:
                        self._selected_index = i
                        self._selected_item = item
                        found = True
                        all_diffs = self._get_item_detail_difficulties(item)
                        selected_details = all_diffs
                        current_diff_available = any(
                            d.get('difficulty') == self._selected_difficulty
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
                                        self._selected_difficulty = diff_num
                                        break
                                else:
                                    continue
                                break
                        break

                if not found and self._display_mode == "chart" and fallback_item:
                    self._selected_index = fallback_index
                    self._selected_item = fallback_item
                    self._selected_difficulty = fallback_item.get('difficulty', 2)

        else:
            if self._selected_song_id:
                for i, item in enumerate(list_items):
                    if item.get('arcaeaId') != self._selected_song_id:
                        continue

                    if self._display_mode == "chart":
                        if item.get('difficulty') == self._selected_difficulty:
                            self._selected_index = i
                            self._selected_item = item
                            break
                    else:
                        self._selected_index = i
                        self._selected_item = item
                        break

        self._attach_details_to_selected(selected_details)
        self.dataChanged.emit()

        if (
            selection_mode in ('first', 'restore_always_emit', 'adjacent_fallback')
            or self._selected_index != old_selected_index
        ):
            self.selectedItemChanged.emit()

    def _full_rebuild(self, selection_mode: str = 'restore'):
        """전체 재빌드 (모드 전환/데이터 갱신 등)."""
        filters = self._get_filter_params()
        full = self._service.build_full_items(self._display_mode, filters)
        filtered = self._service.filter_items(
            full, self._display_mode, self._search_text, filters
        )
        sorted_items = self._service.sort_items(
            filtered, self._sort_mode, self._sort_ascending
        )
        self._service.apply_display_values(
            sorted_items, self._sort_mode, self._display_mode
        )
        self._list_model.reset_items(sorted_items)
        self._restore_selection(selection_mode)

    def _on_sort_mode_changed(self):
        """정렬 모드 변경: 재정렬 + displayValue 갱신만 수행."""
        current_items = list(self._list_model.get_items())
        sorted_items = self._service.sort_items(
            current_items, self._sort_mode, self._sort_ascending
        )
        self._service.apply_display_values(
            sorted_items, self._sort_mode, self._display_mode
        )
        self._list_model.reset_items(sorted_items)
        self._restore_selection('first')

    def _on_sort_order_changed(self):
        """정렬 방향 변경: reverse만 수행."""
        current_items = list(self._list_model.get_items())
        current_items.reverse()
        self._list_model.reset_items(current_items)
        self._restore_selection('first')

    def _on_filter_changed(self, selection_mode: str = 'adjacent_fallback'):
        """필터 변경: 빌드(Song 모드 시) → 필터링 → 정렬 → 리스트 갱신."""
        filters = self._get_filter_params()
        full = self._service.build_full_items(self._display_mode, filters)
        filtered = self._service.filter_items(
            full, self._display_mode, self._search_text, filters
        )
        sorted_items = self._service.sort_items(
            filtered, self._sort_mode, self._sort_ascending
        )
        self._service.apply_display_values(
            sorted_items, self._sort_mode, self._display_mode
        )
        self._list_model.reset_items(sorted_items)
        self._restore_selection(selection_mode)

    def _on_search_changed(self):
        """검색어 변경: 빌드 캐시 히트 → 필터링 → 정렬 → 리스트 갱신."""
        self._on_filter_changed(selection_mode='first')

    def _on_display_mode_changed(self):
        """표시 모드 변경: 전체 재빌드."""
        self._full_rebuild(selection_mode='restore_always_emit')

    def _on_data_refreshed(self):
        """데이터 갱신: 캐시 무효화 → 전체 재빌드."""
        self._service.invalidate_caches()
        self._full_rebuild(selection_mode='first')

    # === QML Properties ===
    @pyqtProperty(QObject, constant=True)
    def listModel(self):
        return self._list_model

    @pyqtProperty(str, notify=dataChanged)
    def displayMode(self):
        return self._display_mode

    @pyqtProperty(str, notify=dataChanged)
    def sortMode(self):
        return self._sort_mode

    @pyqtProperty(bool, notify=dataChanged)
    def sortAscending(self):
        return self._sort_ascending

    @pyqtProperty('QVariantList', notify=dataChanged)
    def availableLevels(self):
        return self._service.available_levels

    @pyqtProperty('QVariantList', notify=dataChanged)
    def availableBPs(self):
        return self._service.available_bps

    @pyqtProperty('QVariant', notify=dataChanged)
    def levelBoundaries(self):
        return self._service.level_boundaries

    @pyqtProperty('QVariantList', notify=dataChanged)
    def scoreRanks(self):
        return SCORE_RANKS

    @pyqtProperty(int, notify=selectedItemChanged)
    def selectedDifficulty(self):
        return self._selected_difficulty

    @pyqtProperty(str, notify=selectedItemChanged)
    def selectedSongId(self):
        return self._selected_song_id or ""

    @pyqtProperty(int, notify=selectedItemChanged)
    def selectedIndex(self):
        return self._selected_index

    # === QML Slots ===
    @pyqtSlot(str)
    def setDisplayMode(self, mode):
        if mode in ["song", "chart"] and mode != self._display_mode:
            self._display_mode = mode
            self._on_display_mode_changed()

    @pyqtSlot(str)
    def setSortMode(self, mode):
        if mode != self._sort_mode:
            self._sort_mode = mode
            self._on_sort_mode_changed()

    @pyqtSlot()
    def toggleSortOrder(self):
        self._sort_ascending = not self._sort_ascending
        self._on_sort_order_changed()

    @pyqtSlot(str)
    def setSearchText(self, text):
        if text != self._search_text:
            self._search_text = text
            self._on_search_changed()

    @pyqtSlot(str, 'QVariant')
    def setFilter(self, filter_type, value):
        """Set a specific filter."""
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
        elif filter_type == 'clear_types':
            self._filter_clear_types = list(value) if value else []
        elif filter_type == 'score_min_rank':
            self._filter_score_min_rank = int(value) if value is not None else 0
        elif filter_type == 'score_max_rank':
            self._filter_score_max_rank = int(value) if value is not None else len(SCORE_RANKS) - 1

        self._on_filter_changed(selection_mode='adjacent_fallback')

    @pyqtSlot(int)
    def selectItem(self, index):
        selected_item = self._list_model.get_item(index)
        if selected_item is None:
            return

        self._selected_index = index
        self._selected_item = selected_item
        selected_details = None

        # Track selection for mode sync
        self._selected_song_id = self._selected_item.get('arcaeaId')

        # In chart mode, also track the difficulty
        if self._display_mode == "chart":
            self._selected_difficulty = self._selected_item.get('difficulty', 2)
        else:
            best_diff = self._service.get_best_diff_for_sort(
                self._selected_item, self._sort_mode
            )

            if best_diff >= 0:
                self._selected_difficulty = best_diff
            else:
                all_diffs = self._get_item_detail_difficulties(self._selected_item)
                selected_details = all_diffs
                current_diff_available = any(
                    d.get('difficulty') == self._selected_difficulty
                    and not d.get('isFiltered', False)
                    for d in all_diffs
                )
                if not current_diff_available and all_diffs:
                    for diff_num in [3, 4, 2, 1, 0]:
                        for diff_item in all_diffs:
                            if (
                                diff_item.get('difficulty') == diff_num
                                and not diff_item.get('isFiltered', False)
                            ):
                                self._selected_difficulty = diff_num
                                break
                        else:
                            continue
                        break

        self._attach_details_to_selected(selected_details)
        self.selectedItemChanged.emit()

    @pyqtSlot(int)
    def setSelectedDifficulty(self, diff):
        """Set the selected difficulty (called when clicking DiffCard).

        In Chart mode, this also updates the list selection to the matching chart.
        """
        if diff not in [0, 1, 2, 3, 4]:
            return

        self._selected_difficulty = diff

        if self._display_mode == "chart" and self._selected_song_id:
            for i, item in enumerate(self._list_model.get_items()):
                if (
                    item.get('arcaeaId') == self._selected_song_id
                    and item.get('difficulty') == diff
                ):
                    self._selected_index = i
                    self._selected_item = item
                    break

        self._attach_details_to_selected()
        self.selectedItemChanged.emit()

    @pyqtSlot(result='QVariant')
    def getSelectedItem(self):
        return self._selected_item

    @pyqtSlot()
    def refreshData(self):
        self._service.load_data(config['general']['cache_path'])
        self._on_data_refreshed()
