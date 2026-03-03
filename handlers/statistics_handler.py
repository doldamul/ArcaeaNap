"""Statistics 탭 핸들러: QML 브릿지, UI 상태 관리."""
from PyQt6.QtCore import QObject, pyqtSlot, pyqtSignal, pyqtProperty, QVariant

from configuration import config
from models.constants import SCORE_RANKS, DIFFICULTY_ORDER
from services.statistics_service import StatisticsService, FilterParams


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
        self._list_model = []
        self._selected_item = None

        # Selection state for mode sync
        self._selected_song_id = None  # arcaea_id of selected song
        self._selected_difficulty = 2  # Default to FTR (0=PST,1=PRS,2=FTR,3=BYD,4=ETR)

        self._pending_selection_mode = 'first'

        self._service.load_data(config['general']['cache_path'])
        self._rebuild_list()

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

    def _rebuild_list(self):
        """서비스에서 리스트 생성 → 선택 관리 → 시그널 emit."""
        items = self._service.build_filtered_sorted_list(
            self._display_mode, self._sort_mode, self._sort_ascending,
            self._search_text, self._get_filter_params()
        )
        self._list_model = items

        # Handle selection based on selection_mode (set by caller)
        old_selected_index = self._selected_index
        self._selected_index = -1
        self._selected_item = None

        selection_mode = getattr(self, '_pending_selection_mode', 'restore')
        self._pending_selection_mode = 'restore'  # Reset to default

        if selection_mode == 'first':
            # Select first item (for sort/search changes)
            if self._list_model:
                self._selected_index = 0
                self._selected_item = self._list_model[0]
                self._selected_song_id = self._selected_item.get('arcaeaId')
                if self._display_mode == "chart":
                    self._selected_difficulty = self._selected_item.get('difficulty', 2)
                else:
                    # Song mode: select best difficulty for current sort mode
                    best_diff = self._service.get_best_diff_for_sort(
                        self._selected_item, self._sort_mode
                    )
                    if best_diff >= 0:
                        self._selected_difficulty = best_diff
                    else:
                        # For sort modes without highlighting, use highest available difficulty
                        all_diffs = self._selected_item.get('allDifficulties', [])
                        for diff_num in [3, 4, 2, 1, 0]:  # BYD, ETR, FTR, PRS, PST
                            for d in all_diffs:
                                if d.get('difficulty') == diff_num and not d.get('isFiltered', False):
                                    self._selected_difficulty = diff_num
                                    break
                            else:
                                continue
                            break
        elif selection_mode == 'adjacent_fallback':
            # Try to restore selection, with fallback to other difficulties if filtered out
            if self._selected_song_id:
                found = False
                fallback_item = None
                fallback_index = -1

                for i, item in enumerate(self._list_model):
                    if item.get('arcaeaId') == self._selected_song_id:
                        if self._display_mode == "chart":
                            # Exact match (same song + difficulty)
                            if item.get('difficulty') == self._selected_difficulty:
                                self._selected_index = i
                                self._selected_item = item
                                found = True
                                break
                            # Track first item of same song as fallback
                            elif fallback_item is None:
                                fallback_item = item
                                fallback_index = i
                        else:
                            # Song mode: found the song
                            self._selected_index = i
                            self._selected_item = item
                            found = True
                            # Check if selected difficulty is still available (not filtered)
                            all_diffs = item.get('allDifficulties', [])
                            current_diff_available = any(
                                d.get('difficulty') == self._selected_difficulty and not d.get('isFiltered', False)
                                for d in all_diffs
                            )
                            if not current_diff_available:
                                # Find highest non-filtered difficulty (BYD, ETR, FTR, PRS, PST)
                                for diff_num in [3, 4, 2, 1, 0]:
                                    for d in all_diffs:
                                        if d.get('difficulty') == diff_num and not d.get('isFiltered', False):
                                            self._selected_difficulty = diff_num
                                            break
                                    else:
                                        continue
                                    break
                            break

                # Chart mode: use fallback if exact match not found
                if not found and self._display_mode == "chart" and fallback_item:
                    self._selected_index = fallback_index
                    self._selected_item = fallback_item
                    self._selected_difficulty = fallback_item.get('difficulty', 2)
            # If item not found, selection stays cleared (-1, None)
        else:
            # Default 'restore' mode - try to restore selection (for mode changes)
            if self._selected_song_id:
                for i, item in enumerate(self._list_model):
                    if item.get('arcaeaId') == self._selected_song_id:
                        if self._display_mode == "chart":
                            if item.get('difficulty') == self._selected_difficulty:
                                self._selected_index = i
                                self._selected_item = item
                                break
                        else:
                            self._selected_index = i
                            self._selected_item = item
                            break

        self.dataChanged.emit()

        # Emit selectedItemChanged if selection changed OR if filter/mode could affect detailed view
        # For 'first', 'restore_always_emit', and 'adjacent_fallback' modes, always emit
        # since the item content or isFiltered status may have changed
        if selection_mode in ('first', 'restore_always_emit', 'adjacent_fallback') or self._selected_index != old_selected_index:
            self.selectedItemChanged.emit()

    # === QML Properties ===
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
            self._pending_selection_mode = 'restore_always_emit'
            self._rebuild_list()

    @pyqtSlot(str)
    def setSortMode(self, mode):
        if mode != self._sort_mode:
            self._sort_mode = mode
            self._pending_selection_mode = 'first'
            self._rebuild_list()

    @pyqtSlot()
    def toggleSortOrder(self):
        self._sort_ascending = not self._sort_ascending
        self._pending_selection_mode = 'first'
        self._rebuild_list()

    @pyqtSlot(str)
    def setSearchText(self, text):
        if text != self._search_text:
            self._search_text = text
            self._pending_selection_mode = 'first'
            self._rebuild_list()

    @pyqtSlot(str, 'QVariant')
    def setFilter(self, filter_type, value):
        """Set a specific filter."""
        # Convert QJSValue to Python type if necessary
        if hasattr(value, 'toVariant'):
            value = value.toVariant()

        if filter_type == 'difficulties':
            # Specify int conversion to avoid any type mismatch (e.g. string/float)
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

        self._pending_selection_mode = 'adjacent_fallback'
        self._rebuild_list()

    @pyqtSlot(int)
    def selectItem(self, index):
        if 0 <= index < len(self._list_model):
            self._selected_index = index
            self._selected_item = self._list_model[index]

            # Track selection for mode sync
            self._selected_song_id = self._selected_item.get('arcaeaId')

            # In chart mode, also track the difficulty
            if self._display_mode == "chart":
                self._selected_difficulty = self._selected_item.get('difficulty', 2)
            else:
                # Song mode: for sort modes that highlight a specific difficulty,
                # automatically select that difficulty
                best_diff = self._service.get_best_diff_for_sort(
                    self._selected_item, self._sort_mode
                )

                if best_diff >= 0:
                    # Use the best difficulty for current sort mode
                    self._selected_difficulty = best_diff
                else:
                    # For other sort modes (title, total_play_count, this_year_play_count, length),
                    # check if current selected difficulty is available for this song
                    all_diffs = self._selected_item.get('allDifficulties', [])
                    current_diff_available = any(
                        d.get('difficulty') == self._selected_difficulty and not d.get('isFiltered', False)
                        for d in all_diffs
                    )
                    if not current_diff_available and all_diffs:
                        # Find highest non-filtered difficulty (reverse order: BYD, ETR, FTR, PRS, PST)
                        for diff_num in [3, 4, 2, 1, 0]:
                            for d in all_diffs:
                                if d.get('difficulty') == diff_num and not d.get('isFiltered', False):
                                    self._selected_difficulty = diff_num
                                    break
                            else:
                                continue
                            break

            self.selectedItemChanged.emit()

    @pyqtSlot(int)
    def setSelectedDifficulty(self, diff):
        """Set the selected difficulty (called when clicking DiffCard).

        In Chart mode, this also updates the list selection to the matching chart.
        """
        if diff not in [0, 1, 2, 3, 4]:
            return

        old_difficulty = self._selected_difficulty
        self._selected_difficulty = diff

        # In Chart mode, find and select the matching item in the list
        if self._display_mode == "chart" and self._selected_song_id:
            for i, item in enumerate(self._list_model):
                if (item.get('arcaeaId') == self._selected_song_id and
                    item.get('difficulty') == diff):
                    self._selected_index = i
                    self._selected_item = item
                    break

        self.selectedItemChanged.emit()

    @pyqtSlot(result='QVariant')
    def getListModel(self):
        return self._list_model

    @pyqtSlot(result='QVariant')
    def getSelectedItem(self):
        return self._selected_item

    @pyqtSlot()
    def refreshData(self):
        self._service.load_data(config['general']['cache_path'])
        self._pending_selection_mode = 'first'
        self._rebuild_list()
