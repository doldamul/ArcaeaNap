import os
from typing import Any
from PyQt6.QtCore import QObject, pyqtSlot, pyqtSignal, pyqtProperty, QVariant

from utils.configuration import config, get_cache_dir
from models.constants import SCORE_RANKS
from services.statistics_service import StatisticsService, FilterParams
from handlers.statistics_list_model import StatisticsListModel
from services.thumbnail_service import ThumbnailService


class StatisticsHandler(QObject):
    dataChanged = pyqtSignal()
    selectedItemChanged = pyqtSignal()
    currentPackChanged = pyqtSignal()
    isPackDetailViewChanged = pyqtSignal()
    packItemsChanged = pyqtSignal()
    expandedPackIdsChanged = pyqtSignal()
    isSongsDbAvailableChanged = pyqtSignal()
    thumbnailVersionChanged = pyqtSignal()

    def __init__(self, service: StatisticsService | None = None, settings_handler: Any = None):
        super().__init__()
        self._service = service if service is not None else StatisticsService()

        # UI 상태
        self._display_mode = "song"  # "song", "chart", or "pack"
        self._sort_mode = "title"
        self._sort_ascending = False
        self._search_text = ""
        self._selected_index = -1

        # Pack Mode UI 상태
        self._expanded_pack_ids = set()
        self._current_pack = None
        self._is_pack_detail_view = True
        self._pack_items = []
        self._pack_items_dirty = True
        self._settings_handler = None
        self._thumbnail_service = ThumbnailService.get_instance()
        self._thumbnail_service.thumbnailVersionChanged.connect(self.thumbnailVersionChanged)

        # Filters
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

        # Processed list
        self._list_model = StatisticsListModel(self)
        self._selected_item = None

        # Selection state for mode sync
        self._selected_song_db_id = None  # songs.id of selected song
        self._selected_difficulty = 2  # Default to FTR (0=PST,1=PRS,2=FTR,3=BYD,4=ETR)

        self._service.load_data(
            get_cache_dir(),
            config['general']['song_title_language'],
        )
        self._full_rebuild('first')

        if settings_handler is not None:
            self.set_settings_handler(settings_handler)

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
            hard_bpm=self._filter_hard_bpm,
            score_min_rank=self._filter_score_min_rank,
            score_max_rank=self._filter_score_max_rank,
            clear_types=self._filter_clear_types,
            include_inscribed=self._filter_include_inscribed,
        )

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
                self._selected_song_db_id = self._selected_item.get('songDbId')

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
            if self._selected_song_db_id is not None:
                found = False
                fallback_item = None
                fallback_index = -1

                for i, item in enumerate(list_items):
                    if item.get('songDbId') != self._selected_song_db_id:
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
            if self._selected_song_db_id is not None:
                for i, item in enumerate(list_items):
                    if item.get('songDbId') != self._selected_song_db_id:
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

    def _rebuild_pack_items(self):
        """Pack 모드 팩 아이템 목록 재빌드 및 _current_pack 동기화."""
        filters = self._get_filter_params()
        self._pack_items = self._service.get_pack_items(
            filters=filters,
            sort_mode=self._sort_mode,
            sort_ascending=self._sort_ascending,
            search_text=self._search_text,
            classification_mode=self.packClassificationMode,
        )
        self._pack_items_dirty = False

        old_expanded_ids = set(self._expanded_pack_ids)
        old_is_pack_detail_view = self._is_pack_detail_view
        old_selected_item = self._selected_item
        item_metadata_updated = False

        # 악곡 식별자 추출 (곡 상세 뷰에서 곡이 선택되어 있었던 경우)
        selected_db_id = (
            self._selected_item.get('songDbId')
            if self._selected_item
            else self._selected_song_db_id
        )
        selected_arcaea_id = (
            (self._selected_item.get('arcaeaId') or self._selected_item.get('id'))
            if self._selected_item
            else None
        )
        has_selected_song = (not self._is_pack_detail_view) and (
            (selected_db_id is not None) or (selected_arcaea_id is not None)
        )

        # 1. 선택된 악곡을 포함하는 팩 탐색 (최우선)
        target_pack_by_song = None
        if has_selected_song:
            for pack in self._pack_items:
                songs = pack.get('songs', [])
                if selected_db_id is not None:
                    # songDbId가 고유 식별자이므로 최우선 매칭 (리믹스 곡 등의 arcaeaId 중복 방지)
                    if any(s.get('songDbId') == selected_db_id for s in songs):
                        target_pack_by_song = pack
                        break
                elif selected_arcaea_id:
                    if any(s.get('arcaeaId') == selected_arcaea_id or s.get('id') == selected_arcaea_id for s in songs):
                        target_pack_by_song = pack
                        break

        new_current = None
        current_id = self._current_pack.get('id') if self._current_pack else None

        if has_selected_song and target_pack_by_song:
            # [요구사항 1] 선택된 악곡이 새 모드/필터의 팩에 존재함 -> 해당 팩으로 전환/유지
            new_current = target_pack_by_song
            self._expanded_pack_ids = {target_pack_by_song['id']}

            # 곡 상세 정보 메타데이터를 새 분류 체계/필터 기준으로 갱신
            song_data = None
            if selected_db_id is not None:
                song_data = self._service.songs_data.get(selected_db_id) or self._service.songs_by_db_id.get(selected_db_id)
            if not song_data and selected_arcaea_id:
                for sdata in self._service.songs_data.values():
                    if sdata.get('arcaea_id') == selected_arcaea_id:
                        song_data = sdata
                        break

            if song_data:
                self._selected_item = self._service.build_song_item(song_data, filters=filters)
                self._selected_song_db_id = self._selected_item.get('songDbId') if self._selected_item else None
                # 현재 팩 모드의 팩 정보(이름, 약어, 색상)로 동기화
                if self._selected_item and target_pack_by_song:
                    self._selected_item['pack'] = target_pack_by_song.get('name', self._selected_item.get('pack'))
                    self._selected_item['packAbbr'] = target_pack_by_song.get('abbr', self._selected_item.get('packAbbr'))
                    self._selected_item['packColor'] = target_pack_by_song.get('color', self._selected_item.get('packColor'))
                self._attach_details_to_selected()
                item_metadata_updated = True

        elif has_selected_song and not target_pack_by_song:
            # [요구사항 2] 선택된 악곡이 필터 등에 의해 제외됨
            target_pack = next((p for p in self._pack_items if p.get('id') == current_id), None)
            if target_pack and len(target_pack.get('songs', [])) > 0:
                # Case A: 팩 내 다른 유효 악곡이 남아있는 경우 -> 악곡 선택 해제 및 팩 대시보드로 복귀
                new_current = target_pack
                self._expanded_pack_ids = {target_pack['id']}
                self._selected_item = None
                self._selected_song_db_id = None
                self._is_pack_detail_view = True
            else:
                # Case B: 팩 내 잔여 곡이 0개가 된 경우 -> 팩 선택 해제 및 전체 팩 목록 복귀 (Task 45 연동)
                self._expanded_pack_ids.clear()
                self._is_pack_detail_view = True
                self._selected_item = None
                self._selected_song_db_id = None
                new_current = self._pack_items[0] if self._pack_items else None

        else:
            # 악곡이 선택되지 않은 상태 (팩 대시보드 또는 팩 목록)
            if self._expanded_pack_ids:
                target_pack = next((p for p in self._pack_items if p.get('id') == current_id), None)
                if target_pack and len(target_pack.get('songs', [])) > 0:
                    new_current = target_pack
                    self._expanded_pack_ids = {target_pack['id']}
                else:
                    # [요구사항 1 Fallback] 이전 팩이 사라진 경우(Strict -> Conceptual), 이전 팩의 곡들을 흡수한 부모 팩 검색
                    fallback_parent_pack = None
                    prev_songs = self._current_pack.get('songs', []) if self._current_pack else []
                    for prev_s in prev_songs:
                        prev_sid = prev_s.get('songDbId')
                        prev_aid = prev_s.get('arcaeaId') or prev_s.get('id')
                        for pack in self._pack_items:
                            if any(
                                (prev_sid is not None and s.get('songDbId') == prev_sid)
                                or (prev_aid and (s.get('arcaeaId') == prev_aid or s.get('id') == prev_aid))
                                for s in pack.get('songs', [])
                            ):
                                fallback_parent_pack = pack
                                break
                        if fallback_parent_pack:
                            break

                    if fallback_parent_pack and len(fallback_parent_pack.get('songs', [])) > 0:
                        new_current = fallback_parent_pack
                        self._expanded_pack_ids = {fallback_parent_pack['id']}
                    else:
                        self._expanded_pack_ids.clear()
                        self._is_pack_detail_view = True
                        new_current = self._pack_items[0] if self._pack_items else None
            else:
                new_current = self._pack_items[0] if self._pack_items else None

        self._current_pack = new_current
        self.packItemsChanged.emit()
        self.currentPackChanged.emit()

        if self._expanded_pack_ids != old_expanded_ids:
            self.expandedPackIdsChanged.emit()
        if self._is_pack_detail_view != old_is_pack_detail_view:
            self.isPackDetailViewChanged.emit()
        if item_metadata_updated or (self._selected_item is not old_selected_item):
            self.selectedItemChanged.emit()


    def _full_rebuild(self, selection_mode: str = 'restore'):
        """전체 재빌드 (모드 전환/데이터 갱신 등)."""
        if self._display_mode == "pack":
            self._rebuild_pack_items()
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
        """정렬 모드 변경: 재정렬 + displayValue 갱신만 수행."""
        self._pack_items_dirty = True
        if self._display_mode == "pack":
            self._rebuild_pack_items()
            self.dataChanged.emit()
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

    _DIRECTION_DEPENDENT_SORT_MODES = {
        "bpm", "score", "max", "recent_played",
        "level", "s_bp", "perceived_bp", "potential", "length", "note_count",
        "version",
    }

    def _on_sort_order_changed(self):
        """정렬 방향 변경: 방향 의존 키 모드는 전체 재정렬, 그 외는 reverse."""
        self._pack_items_dirty = True
        if self._display_mode == "pack":
            self._rebuild_pack_items()
            self.dataChanged.emit()
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

    def _on_filter_changed(self, selection_mode: str = 'adjacent_fallback'):
        """필터 변경: 빌드(Song 모드 시) → 필터링 → 정렬 → 리스트 갱신."""
        self._pack_items_dirty = True
        if self._display_mode == "pack":
            self._rebuild_pack_items()
            if not self._is_pack_detail_view and self._selected_item:
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

    def _on_search_changed(self):
        """검색어 변경: 빌드 캐시 히트 → 필터링 → 정렬 → 리스트 갱신."""
        self._pack_items_dirty = True
        if self._display_mode == "pack":
            self._rebuild_pack_items()
            self.dataChanged.emit()
            return
        self._on_filter_changed(selection_mode='first')

    def _on_display_mode_changed(self):
        """표시 모드 변경: 전체 재빌드."""
        self._full_rebuild(selection_mode='restore_always_emit')

    def _on_data_refreshed(self):
        """데이터 갱신: 캐시 무효화 → 전체 재빌드."""
        self._pack_items_dirty = True
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

    @pyqtProperty(str, notify=dataChanged)
    def displayMode(self):
        return self._display_mode

    @pyqtProperty('QVariantMap', notify=currentPackChanged)
    def currentPack(self):
        return self._current_pack or {}

    @pyqtProperty(bool, notify=isPackDetailViewChanged)
    def isPackDetailView(self):
        return self._is_pack_detail_view

    @pyqtProperty(str, notify=dataChanged)
    def packClassificationMode(self):
        try:
            return config['general']['pack_classification_mode']
        except Exception:
            return "strict"

    @pyqtProperty('QVariantList', notify=packItemsChanged)
    def packItems(self):
        items = []
        for pack in self._pack_items:
            p = dict(pack)
            p['expanded'] = bool(pack.get('id') in self._expanded_pack_ids)
            items.append(p)
        return items

    @pyqtProperty('QVariantList', notify=expandedPackIdsChanged)
    def expandedPackIds(self):
        return list(self._expanded_pack_ids)

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
        # QML에서는 썸네일/색상 조회 키로 arcaeaId를 사용한다.
        if self._selected_item:
            return self._selected_item.get('arcaeaId', '')
        return ""

    @pyqtProperty(int, notify=selectedItemChanged)
    def selectedIndex(self):
        return self._selected_index

    @pyqtProperty(bool, notify=dataChanged)
    def hasInscribedScore(self) -> bool:
        """INS 플레이 기록 존재 여부 (하나라도 기록이 있으면 True)."""
        return self._service.has_any_inscribed_played()

    @pyqtProperty(bool, notify=dataChanged)
    def isInscribedUnlocked(self) -> bool:
        """DEINOS PHAINEIN INS 해금 여부."""
        return self._service.is_inscribed_unlocked()

    @pyqtProperty('QVariantList', notify=dataChanged)
    def activeFiltersModel(self):
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

    # === QML Slots ===
    @pyqtSlot(str)
    def setDisplayMode(self, mode):
        if mode in ["song", "chart", "pack"] and mode != self._display_mode:
            old_mode = self._display_mode
            self._display_mode = mode

            if mode == "pack":
                self._is_pack_detail_view = True

                # 1. 팩 아이템 목록 캐시 유효성 검사 후 최신화
                if self._pack_items_dirty or not self._pack_items:
                    filters = self._get_filter_params()
                    self._pack_items = self._service.get_pack_items(
                        filters=filters,
                        sort_mode=self._sort_mode,
                        sort_ascending=self._sort_ascending,
                        search_text=self._search_text,
                        classification_mode=self.packClassificationMode,
                    )
                    self._pack_items_dirty = False

                # 2. 직전 선택 곡이 속한 팩 사전 계산 및 expandedPackIds 확정
                target_pack = None
                if old_mode in ["song", "chart"] and self._selected_item:
                    selected_song_id = self._selected_item.get('arcaeaId') or self._selected_item.get('id')
                    selected_db_id = self._selected_item.get('songDbId') or self._selected_song_db_id
                    for pack in self._pack_items:
                        if any(
                            (selected_db_id is not None and s.get('songDbId') == selected_db_id)
                            or (selected_song_id and (s.get('arcaeaId') == selected_song_id or s.get('id') == selected_song_id))
                            for s in pack.get('songs', [])
                        ):
                            target_pack = pack
                            break

                if target_pack:
                    self._current_pack = target_pack
                    self._expanded_pack_ids = {target_pack['id']}
                else:
                    self._expanded_pack_ids.clear()
                    self._current_pack = self._pack_items[0] if self._pack_items else None

                # 3. 모든 상태가 완전히 세팅된 후 원자적으로 시그널 일괄 방출 (중간 불일치 상태 0%)
                self.currentPackChanged.emit()
                self.expandedPackIdsChanged.emit()
                self.packItemsChanged.emit()
                self.isPackDetailViewChanged.emit()
                self.dataChanged.emit()
            else:
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
        """Set the selected difficulty (called when clicking DiffCard).

        In Chart mode, this also updates the list selection to the matching chart.
        """
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

    # === Pack Mode Slots & Methods ===
    @pyqtSlot(str)
    def togglePackExpansion(self, pack_id: str):
        """팩 선택/해제 토글, 대상 팩 드릴다운 및 대시보드 뷰 활성화."""
        if not pack_id:
            return

        target_pack = next((p for p in self._pack_items if p.get('id') == pack_id), None)
        if not target_pack:
            return

        if pack_id in self._expanded_pack_ids:
            self._expanded_pack_ids.clear()
            self._is_pack_detail_view = True
            self._selected_item = None
            self._selected_song_db_id = None
            self.selectedItemChanged.emit()
            self.isPackDetailViewChanged.emit()
            self.expandedPackIdsChanged.emit()
            return

        self._expanded_pack_ids = {pack_id}
        self._current_pack = target_pack
        self._is_pack_detail_view = True
        self._selected_item = None
        self._selected_song_db_id = None

        self.currentPackChanged.emit()
        self.isPackDetailViewChanged.emit()
        self.expandedPackIdsChanged.emit()
        self.selectedItemChanged.emit()
        self.packItemsChanged.emit()

    @pyqtSlot()
    def clearPackSelection(self):
        """팩 선택 해제 -> 전체 팩 목록으로 복귀."""
        self._expanded_pack_ids.clear()
        self._is_pack_detail_view = True
        self._selected_item = None
        self._selected_song_db_id = None
        self.selectedItemChanged.emit()
        self.isPackDetailViewChanged.emit()
        self.expandedPackIdsChanged.emit()

    @pyqtSlot(str, int)
    @pyqtSlot(str, 'QVariant')
    def selectPackSong(self, pack_id: str, song_db_id):
        """팩 내 수록곡 선택 -> 곡 상세 뷰 전환 및 해당 곡 정보 바인딩."""
        self._is_pack_detail_view = False

        if pack_id and (not self._current_pack or self._current_pack.get('id') != pack_id):
            target_pack = next((p for p in self._pack_items if p.get('id') == pack_id), None)
            if target_pack:
                self._current_pack = target_pack
                self._expanded_pack_ids = {pack_id}
                self.currentPackChanged.emit()
                self.expandedPackIdsChanged.emit()

        if hasattr(song_db_id, 'toVariant'):
            song_db_id = song_db_id.toVariant()

        try:
            sid_int = int(song_db_id)
        except (ValueError, TypeError):
            sid_int = None

        song_data = None
        if sid_int is not None and sid_int in self._service.songs_data:
            song_data = self._service.songs_data[sid_int]
        elif sid_int is not None and sid_int in self._service.songs_by_db_id:
            song_data = self._service.songs_by_db_id[sid_int]
        elif song_db_id in self._service.songs_data:
            song_data = self._service.songs_data[song_db_id]
        elif song_db_id in self._service.songs_by_db_id:
            song_data = self._service.songs_by_db_id[song_db_id]

        if not song_data and isinstance(song_db_id, str):
            for sdata in self._service.songs_data.values():
                if sdata.get('arcaea_id') == song_db_id:
                    song_data = sdata
                    break

        if not song_data:
            for pack in self._pack_items:
                if pack_id and pack.get('id') != pack_id:
                    continue
                for s in pack.get('songs', []):
                    raw = s.get('raw_data', {})
                    if (
                        raw.get('song_db_id') == song_db_id
                        or raw.get('id') == song_db_id
                        or s.get('id') == str(song_db_id)
                        or s.get('song_id') == str(song_db_id)
                        or raw.get('arcaea_id') == str(song_db_id)
                    ):
                        song_data = raw
                        break
                if song_data:
                    break

        if song_data:
            filters = self._get_filter_params()
            song_item = self._service.build_song_item(song_data, filters=filters)
            self._selected_item = song_item
            self._selected_song_db_id = song_item.get('songDbId') if song_item else None

            best_diff = self._service.get_best_diff_for_sort(
                self._selected_item, self._sort_mode
            )
            if best_diff >= 0:
                self._selected_difficulty = best_diff
            else:
                all_diffs = self._get_item_detail_difficulties(self._selected_item)
                for diff_num in [3, 4, 2, 1, 0]:
                    if any(d.get('difficulty') == diff_num and not d.get('isFiltered', False) for d in all_diffs):
                        self._selected_difficulty = diff_num
                        break

            self._attach_details_to_selected()

        self.isPackDetailViewChanged.emit()
        self.selectedItemChanged.emit()

    @pyqtSlot()
    def returnToPackDashboard(self):
        """곡 상세 뷰에서 팩 종합 대시보드로 복귀."""
        self._is_pack_detail_view = True
        self._selected_item = None
        self._selected_song_db_id = None
        self.selectedItemChanged.emit()
        self.isPackDetailViewChanged.emit()

    @pyqtSlot(str, result=bool)
    def selectPackByName(self, pack_name: str) -> bool:
        """곡 상세 뷰 헤더의 팩 알약 클릭 시 해당 팩의 대시보드로 이동."""
        if not pack_name:
            return False

        # 1. 팩 모드로 전환
        if self._display_mode != "pack":
            self.setDisplayMode("pack")

        # 2. 팩 목록에서 대상 팩 탐색 (Full Name 또는 Abbr 매칭)
        target_pack = None
        for p in self._pack_items:
            if (
                p.get('name') == pack_name
                or p.get('abbr') == pack_name
                or p.get('id') == pack_name
                or str(p.get('name', '')).lower() == pack_name.lower()
                or str(p.get('abbr', '')).lower() == pack_name.lower()
            ):
                target_pack = p
                break

        # 3. 직접 매칭 실패 시 수록곡 기반 Fallback (Conceptual 모드에서 어펜드 팩명/약어로 검색된 경우)
        if not target_pack:
            pack_name_lower = pack_name.lower()
            for p in self._pack_items:
                songs = p.get('songs', [])
                if any(
                    str(s.get('strictPack', '')).lower() == pack_name_lower
                    or str(s.get('strictPackAbbr', '')).lower() == pack_name_lower
                    or str(s.get('pack', '')).lower() == pack_name_lower
                    or str(s.get('packAbbr', '')).lower() == pack_name_lower
                    for s in songs
                ):
                    target_pack = p
                    break

        if target_pack:
            self._current_pack = target_pack
            self._expanded_pack_ids = {target_pack['id']}
            self._is_pack_detail_view = True
            self.currentPackChanged.emit()
            self.expandedPackIdsChanged.emit()
            self.packItemsChanged.emit()
            self.isPackDetailViewChanged.emit()
            self.dataChanged.emit()
            return True

        return False

    @pyqtProperty(int, notify=thumbnailVersionChanged)
    def thumbnailVersion(self) -> int:
        return self._thumbnail_service.thumbnail_version

    @pyqtSlot(str, int, result=str)
    def getThumbnailPathForDifficulty(self, arcaea_id: str, difficulty: int) -> str:
        """ThumbnailService를 통한 난이도별 자켓 썸네일 경로 조회 (QML 바인딩 호환용)."""
        return self._thumbnail_service.get_path_for_difficulty(arcaea_id, difficulty)



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
        self._pack_items_dirty = True
        self._service.invalidate_caches()
        if self._display_mode == "pack":
            self._rebuild_pack_items()
            self.dataChanged.emit()
        else:
            self._full_rebuild(selection_mode='adjacent_fallback')
