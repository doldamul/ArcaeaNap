from typing import Any
from PyQt6.QtCore import QObject, pyqtSlot, pyqtSignal, pyqtProperty, QVariant

from utils.configuration import config, get_cache_dir
from models.constants import SCORE_RANKS
from services.statistics_service import StatisticsService, FilterParams
from handlers.statistics_list_model import StatisticsListModel
from services.thumbnail_service import ThumbnailService
from handlers.statistics_pack_manager import StatisticsPackManager
from handlers.statistics_filter_manager import StatisticsFilterManager


class StatisticsHandler(QObject):
    dataChanged = pyqtSignal()
    displayModeChanged = pyqtSignal()
    selectedItemChanged = pyqtSignal()
    currentPackChanged = pyqtSignal()
    isPackDetailViewChanged = pyqtSignal()
    packItemsChanged = pyqtSignal()
    expandedPackIdsChanged = pyqtSignal()
    isSongsDbAvailableChanged = pyqtSignal()
    thumbnailVersionChanged = pyqtSignal()
    favoriteFilterChanged = pyqtSignal()
    isFavoriteTogglingChanged = pyqtSignal(bool)

    _DIRECTION_DEPENDENT_SORT_MODES = {
        "bpm", "score", "max", "recent_played",
        "level", "s_bp", "perceived_bp", "potential", "length", "note_count",
        "version",
    }

    def __init__(self, service: StatisticsService | None = None, settings_handler: Any = None):
        super().__init__()
        self._service = service if service is not None else StatisticsService()

        # UI 상태
        self._display_mode = "song"  # "song", "chart", or "pack"
        self._sort_mode = "title"
        self._sort_ascending = False
        self._search_text = ""
        self._selected_index = -1
        self._is_favorite_toggling = False

        # Processed list & selection
        self._list_model = StatisticsListModel(self)
        self._selected_item = None
        self._selected_song_db_id = None  # songs.id of selected song
        self._last_selected_song_db_id = None  # Cache for restoring selection
        self._selected_difficulty = 2  # Default to FTR (0=PST,1=PRS,2=FTR,3=BYD,4=ETR)

        # Domain Managers
        self._pack_manager = StatisticsPackManager(self, self._service)
        self._filter_manager = StatisticsFilterManager(self, self._service)

        self._settings_handler = None
        self._thumbnail_service = ThumbnailService.get_instance()
        self._thumbnail_service.thumbnailVersionChanged.connect(self.thumbnailVersionChanged)

        if not self._service.songs_data:
            self._service.load_data(
                get_cache_dir(),
                config['general']['song_title_language'],
            )
        self._full_rebuild('first')

        if settings_handler is not None:
            self.set_settings_handler(settings_handler)

    # === Backwards Compatibility Properties ===
    @property
    def _pack_items(self):
        return self._pack_manager.pack_items

    @_pack_items.setter
    def _pack_items(self, val):
        self._pack_manager.pack_items = val

    @property
    def _pack_items_dirty(self):
        return self._pack_manager.pack_items_dirty

    @_pack_items_dirty.setter
    def _pack_items_dirty(self, val):
        self._pack_manager.pack_items_dirty = val

    @property
    def _expanded_pack_ids(self):
        return self._pack_manager.expanded_pack_ids

    @_expanded_pack_ids.setter
    def _expanded_pack_ids(self, val):
        self._pack_manager.expanded_pack_ids = val

    @property
    def _current_pack(self):
        return self._pack_manager.current_pack

    @_current_pack.setter
    def _current_pack(self, val):
        self._pack_manager.current_pack = val

    @property
    def _is_pack_detail_view(self):
        return self._pack_manager.is_pack_detail_view

    @_is_pack_detail_view.setter
    def _is_pack_detail_view(self, val):
        self._pack_manager.is_pack_detail_view = val

    @property
    def _filter_difficulties(self):
        return self._filter_manager._filter_difficulties

    @_filter_difficulties.setter
    def _filter_difficulties(self, val):
        self._filter_manager._filter_difficulties = val

    @property
    def _filter_include_inscribed(self):
        return self._filter_manager._filter_include_inscribed

    @_filter_include_inscribed.setter
    def _filter_include_inscribed(self, val):
        self._filter_manager._filter_include_inscribed = val

    @property
    def _filter_level_min_str(self):
        return self._filter_manager._filter_level_min_str

    @_filter_level_min_str.setter
    def _filter_level_min_str(self, val):
        self._filter_manager._filter_level_min_str = val

    @property
    def _filter_level_max_str(self):
        return self._filter_manager._filter_level_max_str

    @_filter_level_max_str.setter
    def _filter_level_max_str(self, val):
        self._filter_manager._filter_level_max_str = val

    @property
    def _filter_bp_mode(self):
        return self._filter_manager._filter_bp_mode

    @_filter_bp_mode.setter
    def _filter_bp_mode(self, val):
        self._filter_manager._filter_bp_mode = val

    @property
    def _filter_bp_min(self):
        return self._filter_manager._filter_bp_min

    @_filter_bp_min.setter
    def _filter_bp_min(self, val):
        self._filter_manager._filter_bp_min = val

    @property
    def _filter_bp_max(self):
        return self._filter_manager._filter_bp_max

    @_filter_bp_max.setter
    def _filter_bp_max(self, val):
        self._filter_manager._filter_bp_max = val

    @property
    def _filter_ignore_chart(self):
        return self._filter_manager._filter_ignore_chart

    @_filter_ignore_chart.setter
    def _filter_ignore_chart(self, val):
        self._filter_manager._filter_ignore_chart = val

    @property
    def _filter_skill_issues(self):
        return self._filter_manager._filter_skill_issues

    @_filter_skill_issues.setter
    def _filter_skill_issues(self, val):
        self._filter_manager._filter_skill_issues = val

    @property
    def _filter_hard_bpm(self):
        return self._filter_manager._filter_hard_bpm

    @_filter_hard_bpm.setter
    def _filter_hard_bpm(self, val):
        self._filter_manager._filter_hard_bpm = val

    @property
    def _filter_score_min_rank(self):
        return self._filter_manager._filter_score_min_rank

    @_filter_score_min_rank.setter
    def _filter_score_min_rank(self, val):
        self._filter_manager._filter_score_min_rank = val

    @property
    def _filter_score_max_rank(self):
        return self._filter_manager._filter_score_max_rank

    @_filter_score_max_rank.setter
    def _filter_score_max_rank(self, val):
        self._filter_manager._filter_score_max_rank = val

    @property
    def _filter_clear_types(self):
        return self._filter_manager._filter_clear_types

    @_filter_clear_types.setter
    def _filter_clear_types(self, val):
        self._filter_manager._filter_clear_types = val

    # === Internal Delegations & Helpers ===
    def _get_filter_params(self) -> FilterParams:
        return self._filter_manager.get_filter_params()

    def _get_item_detail_difficulties(self, item):
        """선택 보정/상세 표시에 필요한 allDifficulties를 on-demand로 조회."""
        if not item:
            return []
        song_db_id = item.get('songDbId')
        if song_db_id is None:
            return []
        return self._service.build_selected_item_details(
            song_db_id,
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

        if details:
            selected_copy['songTotalPlayCount'] = sum(
                int(d.get('totalPlayCount', 0) or 0)
                for d in details
                if not d.get('isFiltered', False)
            )

        self._selected_item = selected_copy

    def _restore_selection(self, selection_mode: str):
        self._filter_manager.restore_selection(selection_mode)

    def _rebuild_pack_items(self):
        self._pack_manager.rebuild_pack_items()

    def _full_rebuild(self, selection_mode: str = 'restore'):
        """전체 재빌드 (모드 전환/데이터 갱신 등)."""
        if self._display_mode == "pack":
            self._pack_manager.rebuild_pack_items()
            self.dataChanged.emit()
            return

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
        """정렬 모드 변경: 재정렬 + displayValue 갱신만 수행. 하트필터 활성 시 지연 제외 재필터링 보장."""
        self._pack_manager.pack_items_dirty = True
        if self._display_mode == "pack":
            self._pack_manager.rebuild_pack_items()
            self.dataChanged.emit()
            return

        if self.favoriteFilterActive:
            self._full_rebuild(selection_mode='retain_or_first')
            return

        current_items = list(self._list_model.get_items())
        sorted_items = self._service.sort_items(
            current_items, self._sort_mode, self._sort_ascending
        )
        self._service.apply_display_values(
            sorted_items, self._sort_mode, self._display_mode
        )
        self._list_model.reset_items(sorted_items)
        self._restore_selection('first')
        self.dataChanged.emit()

    def _on_sort_order_changed(self):
        """정렬 방향 변경: 방향 의존 키 모드는 전체 재정렬, 그 외는 reverse. 하트필터 활성 시 지연 제외 재필터링 보장."""
        self._pack_manager.pack_items_dirty = True
        if self._display_mode == "pack":
            self._pack_manager.rebuild_pack_items()
            self.dataChanged.emit()
            return

        if self.favoriteFilterActive:
            self._full_rebuild(selection_mode='retain_or_first')
            return

        current_items = list(self._list_model.get_items())
        if self._sort_mode in self._DIRECTION_DEPENDENT_SORT_MODES:
            sorted_items = self._service.sort_items(
                current_items, self._sort_mode, self._sort_ascending
            )
            self._service.apply_display_values(
                sorted_items, self._sort_mode, self._display_mode
            )
            self._list_model.reset_items(sorted_items)
        else:
            current_items.reverse()
            self._list_model.reset_items(current_items)
        self._restore_selection('first')
        self.dataChanged.emit()

    def _on_filter_changed(self, selection_mode: str = 'adjacent_fallback'):
        """필터 변경: 빌드(Song 모드 시) → 필터링 → 정렬 → 리스트 갱신."""
        self._pack_manager.pack_items_dirty = True
        if self._display_mode == "pack":
            self._pack_manager.rebuild_pack_items()
            if not self._pack_manager.is_pack_detail_view and self._selected_item:
                song_db_id = self._selected_item.get('songDbId') or self._selected_song_db_id
                song_data = None
                if song_db_id is not None:
                    song_data = self._service.songs_data.get(song_db_id) or self._service.songs_by_db_id.get(song_db_id)
                if song_data:
                    filters = self._get_filter_params()
                    self._selected_item = self._service.build_song_item(song_data, filters=filters)
                    self._attach_details_to_selected()
                    self.selectedItemChanged.emit()
            self.dataChanged.emit()
            return

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
        self.dataChanged.emit()

    def _on_search_changed(self):
        """검색어 변경: 빌드 캐시 히트 → 필터링 → 정렬 → 리스트 갱신."""
        self._pack_manager.pack_items_dirty = True
        if self._display_mode == "pack":
            self._pack_manager.rebuild_pack_items()
            self.dataChanged.emit()
            return
        self._on_filter_changed(selection_mode='first')

    def _on_display_mode_changed(self):
        """표시 모드 변경: 전체 재빌드."""
        self._full_rebuild(selection_mode='restore_always_emit')

    def _on_data_refreshed(self):
        """데이터 갱신: 캐시 무효화 → 전체 재빌드."""
        self._pack_manager.pack_items_dirty = True
        self._service.invalidate_caches()
        self.isSongsDbAvailableChanged.emit()
        self._full_rebuild(selection_mode='first')

    # === QML Properties ===
    @pyqtProperty(bool, notify=isSongsDbAvailableChanged)
    def isSongsDbAvailable(self):
        return bool(getattr(self._service, 'is_songs_db_available', True))

    @pyqtProperty(QObject, constant=True)
    def listModel(self):
        return self._list_model

    @pyqtProperty(str, notify=displayModeChanged)
    def displayMode(self):
        return self._display_mode

    @pyqtProperty('QVariantMap', notify=currentPackChanged)
    def currentPack(self):
        return self._pack_manager.get_current_pack()

    @pyqtProperty(bool, notify=isPackDetailViewChanged)
    def isPackDetailView(self):
        return self._pack_manager.is_pack_detail_view

    @pyqtProperty(str, notify=dataChanged)
    def packClassificationMode(self):
        try:
            return config['general']['pack_classification_mode']
        except Exception:
            return "strict"

    @pyqtProperty('QVariantList', notify=packItemsChanged)
    def packItems(self):
        return self._pack_manager.get_pack_items_for_qml()

    @pyqtProperty('QVariantList', notify=expandedPackIdsChanged)
    def expandedPackIds(self):
        return list(self._pack_manager.expanded_pack_ids)

    @pyqtProperty(str, notify=dataChanged)
    def sortMode(self):
        return self._sort_mode

    @pyqtProperty(bool, notify=dataChanged)
    def sortAscending(self):
        return self._sort_ascending

    @pyqtProperty('QVariantList', notify=dataChanged)
    def availableLevels(self):
        return self._filter_manager.available_levels

    @pyqtProperty('QVariantList', notify=dataChanged)
    def availableBPs(self):
        return self._filter_manager.available_bps

    @pyqtProperty('QVariant', notify=dataChanged)
    def levelBoundaries(self):
        return self._filter_manager.level_boundaries

    @pyqtProperty('QVariantList', notify=dataChanged)
    def scoreRanks(self):
        return self._filter_manager.score_ranks

    @pyqtProperty(int, notify=selectedItemChanged)
    def selectedDifficulty(self):
        return self._selected_difficulty

    @pyqtProperty(str, notify=selectedItemChanged)
    def selectedSongId(self):
        if self._selected_item:
            return self._selected_item.get('arcaeaId', '')
        return ""

    @pyqtProperty(int, notify=selectedItemChanged)
    def selectedIndex(self):
        return self._selected_index

    @pyqtProperty(bool, notify=dataChanged)
    def hasInscribedScore(self) -> bool:
        return self._service.has_any_inscribed_played()

    @pyqtProperty(bool, notify=dataChanged)
    def isInscribedUnlocked(self) -> bool:
        return self._service.is_inscribed_unlocked()

    @pyqtProperty('QVariantList', notify=dataChanged)
    def activeFiltersModel(self):
        return self._filter_manager.active_filters_model

    @pyqtProperty(bool, notify=favoriteFilterChanged)
    def favoriteFilterActive(self) -> bool:
        return self._filter_manager.favorite_only

    @pyqtProperty(bool, notify=isFavoriteTogglingChanged)
    def isFavoriteToggling(self) -> bool:
        return self._is_favorite_toggling

    @pyqtProperty(int, notify=thumbnailVersionChanged)
    def thumbnailVersion(self) -> int:
        return self._thumbnail_service.thumbnail_version

    # === QML Slots ===
    @pyqtSlot()
    def toggleFavoriteFilter(self):
        """즐겨찾기 전용 필터 토글."""
        self._filter_manager.toggle_favorite_filter()
        self._on_filter_changed(selection_mode='retain_or_first')
        self.favoriteFilterChanged.emit()

    @pyqtSlot(str)
    def togglePackFavorite(self, pack_name: str):
        """
        팩 즐겨찾기 토글.
        하트필터 활성 여부와 무관하게 항상 인플레이스 갱신으로 뷰포트/스크롤 및 목록 100% 보존.
        """
        is_fav = self._service.toggle_pack_favorite(pack_name)
        self._is_favorite_toggling = True
        try:
            self.isFavoriteTogglingChanged.emit(True)
            self._pack_manager.update_pack_favorite_inplace(pack_name, is_fav)
            self.packItemsChanged.emit()
            self.currentPackChanged.emit()
        finally:
            self._is_favorite_toggling = False
            self.isFavoriteTogglingChanged.emit(False)

    @pyqtSlot(str)
    def toggleSongFavorite(self, arcaea_id: str):
        """
        곡 즐겨찾기 토글.
        하트필터 활성 여부와 무관하게 항상 인플레이스 갱신으로 뷰포트/스크롤 및 목록 100% 보존.
        """
        is_fav = self._service.toggle_song_favorite(arcaea_id)
        self._is_favorite_toggling = True
        try:
            self.isFavoriteTogglingChanged.emit(True)
            self._list_model.update_favorite_status('song', arcaea_id, -1, is_fav)
            if self._selected_item and self._selected_item.get('arcaeaId') == arcaea_id:
                new_item = dict(self._selected_item)
                new_item['isSongFavorite'] = is_fav
                self._selected_item = new_item
                self.selectedItemChanged.emit()
            if self._display_mode == 'pack':
                self._pack_manager.update_song_favorite_inplace(arcaea_id, is_fav)
                self.packItemsChanged.emit()
                self.currentPackChanged.emit()
        finally:
            self._is_favorite_toggling = False
            self.isFavoriteTogglingChanged.emit(False)

    @pyqtSlot(str, int)
    def toggleChartFavorite(self, arcaea_id: str, diff: int):
        """
        채보 즐겨찾기 토글.
        하트필터 활성 여부와 무관하게 항상 인플레이스 갱신으로 뷰포트/스크롤 및 목록 100% 보존.
        """
        diff_int = int(diff)
        is_fav = self._service.toggle_chart_favorite(arcaea_id, diff_int)
        self._is_favorite_toggling = True
        try:
            self.isFavoriteTogglingChanged.emit(True)
            self._list_model.update_favorite_status('chart', arcaea_id, diff_int, is_fav)
            if self._selected_item and self._selected_item.get('arcaeaId') == arcaea_id:
                new_item = dict(self._selected_item)
                chart_favs = set(new_item.get('chartFavorites', []))
                if is_fav:
                    chart_favs.add(diff_int)
                else:
                    chart_favs.discard(diff_int)
                new_item['chartFavorites'] = list(sorted(chart_favs))

                new_diffs = [dict(d) for d in new_item.get('allDifficulties', [])]
                for d in new_diffs:
                    if d.get('difficulty') == diff_int:
                        d['isFavorite'] = is_fav
                        d['isChartFavorite'] = is_fav
                new_item['allDifficulties'] = new_diffs

                if self._display_mode == 'chart' and new_item.get('difficulty') == diff_int:
                    new_item['isChartFavorite'] = is_fav
                    new_item['isFavorite'] = is_fav

                self._selected_item = new_item
                self.selectedItemChanged.emit()

            if self._display_mode == 'pack':
                if self._pack_manager.update_chart_favorite_inplace(arcaea_id, diff_int, is_fav):
                    self.packItemsChanged.emit()
                    self.currentPackChanged.emit()
        finally:
            self._is_favorite_toggling = False
            self.isFavoriteTogglingChanged.emit(False)

    @pyqtSlot(str)
    def setDisplayMode(self, mode):
        if mode in ["song", "chart", "pack"] and mode != self._display_mode:
            old_mode = self._display_mode
            self._display_mode = mode

            if mode == "pack":
                self._pack_manager.handle_set_display_mode_pack(old_mode)
            else:
                if old_mode == "pack" and not self._pack_manager.expanded_pack_ids:
                    self._selected_song_db_id = None
                    self._last_selected_song_db_id = None
                else:
                    if self._selected_song_db_id is None and self._last_selected_song_db_id is not None:
                        self._selected_song_db_id = self._last_selected_song_db_id
                self.displayModeChanged.emit()
                self._on_display_mode_changed()
                self.isPackDetailViewChanged.emit()

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
        self._filter_manager.set_filter(filter_type, value)
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
        self._selected_song_db_id = self._selected_item.get('songDbId')

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
        if diff not in [0, 1, 2, 3, 4]:
            return

        self._selected_difficulty = diff

        if self._display_mode == "chart" and self._selected_song_db_id is not None:
            for i, item in enumerate(self._list_model.get_items()):
                if (
                    item.get('songDbId') == self._selected_song_db_id
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
        self._thumbnail_service = ThumbnailService.get_instance()
        self._service.load_data(
            get_cache_dir(),
            config['general']['song_title_language'],
        )
        self._on_data_refreshed()

    # === Pack Mode Slots ===
    @pyqtSlot(str)
    def togglePackExpansion(self, pack_id: str):
        self._pack_manager.toggle_pack_expansion(pack_id)

    @pyqtSlot()
    def clearPackSelection(self):
        self._pack_manager.clear_pack_selection()

    @pyqtSlot(str, int)
    @pyqtSlot(str, int, int)
    @pyqtSlot(str, 'QVariant')
    @pyqtSlot(str, 'QVariant', int)
    def selectPackSong(self, pack_id: str, song_db_id, target_difficulty: int = -1):
        self._pack_manager.select_pack_song(pack_id, song_db_id, target_difficulty)

    @pyqtSlot()
    def returnToPackDashboard(self):
        self._pack_manager.return_to_pack_dashboard()

    @pyqtSlot(str, result=bool)
    def selectPackByName(self, pack_name: str) -> bool:
        return self._pack_manager.select_pack_by_name(pack_name)

    @pyqtSlot(str, int, result=str)
    def getThumbnailPathForDifficulty(self, arcaea_id: str, difficulty: int) -> str:
        return self._thumbnail_service.get_path_for_difficulty(arcaea_id, difficulty)

    @pyqtSlot(str, int, result=bool)
    def isThumbnailPending(self, arcaea_id: str, difficulty: int) -> bool:
        return self._thumbnail_service.is_thumbnail_pending(arcaea_id, difficulty)

    def set_settings_handler(self, settings_handler):
        """Connect to SettingsHandler for pack classification mode and excluded packs changes."""
        if self._settings_handler:
            try:
                self._settings_handler.packClassificationModeChanged.disconnect(
                    self._on_settings_classification_or_exclusion_changed
                )
            except Exception:
                pass
            try:
                self._settings_handler.excludedPacksChanged.disconnect(
                    self._on_settings_classification_or_exclusion_changed
                )
            except Exception:
                pass
        self._settings_handler = settings_handler
        if settings_handler:
            settings_handler.packClassificationModeChanged.connect(
                self._on_settings_classification_or_exclusion_changed
            )
            settings_handler.excludedPacksChanged.connect(
                self._on_settings_classification_or_exclusion_changed
            )

    @pyqtSlot()
    @pyqtSlot(str)
    @pyqtSlot(list)
    def _on_settings_classification_or_exclusion_changed(self, *args):
        """설정에서 팩 분류 체계(Strict vs Conceptual) 또는 제외 팩 변경 시 캐시 무효화 및 재빌드."""
        self._pack_manager.pack_items_dirty = True
        self._service.invalidate_caches()
        if self._display_mode == "pack":
            self._pack_manager.rebuild_pack_items()
            self.dataChanged.emit()
        else:
            self._full_rebuild(selection_mode='adjacent_fallback')
