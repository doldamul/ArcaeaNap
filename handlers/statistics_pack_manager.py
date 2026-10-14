from typing import Any


class StatisticsPackManager:
    """Manages pack mode state, rebuilding, and navigation."""

    def __init__(self, handler: Any, service: Any):
        self._handler = handler
        self._service = service

        self.expanded_pack_ids: set[str] = set()
        self.current_pack: dict[str, Any] | None = None
        self.is_pack_detail_view: bool = True
        self.pack_items: list[dict[str, Any]] = []
        self.pack_items_dirty: bool = True

    def get_current_pack(self) -> dict:
        return self.current_pack or {}

    def get_pack_items_for_qml(self) -> list:
        items = []
        for pack in self.pack_items:
            p = dict(pack)
            p['expanded'] = bool(pack.get('id') in self.expanded_pack_ids)
            items.append(p)
        return items

    def rebuild_pack_items(self):
        """Pack 모드 팩 아이템 목록 재빌드 및 current_pack 동기화."""
        filters = self._handler._get_filter_params()
        self.pack_items = self._service.get_pack_items(
            filters=filters,
            sort_mode=self._handler._sort_mode,
            sort_ascending=self._handler._sort_ascending,
            search_text=self._handler._search_text,
            classification_mode=self._handler.packClassificationMode,
        )
        self.pack_items_dirty = False

        old_expanded_ids = set(self.expanded_pack_ids)
        old_is_pack_detail_view = self.is_pack_detail_view
        old_selected_item = self._handler._selected_item
        item_metadata_updated = False

        # 악곡 식별자 추출 (곡 상세 뷰에서 곡이 선택되어 있었던 경우)
        selected_db_id = (
            self._handler._selected_item.get('songDbId')
            if self._handler._selected_item
            else self._handler._selected_song_db_id
        )
        selected_arcaea_id = (
            (self._handler._selected_item.get('arcaeaId') or self._handler._selected_item.get('id'))
            if self._handler._selected_item
            else None
        )
        has_selected_song = (not self.is_pack_detail_view) and (
            (selected_db_id is not None) or (selected_arcaea_id is not None)
        )

        # 1. 선택된 악곡을 포함하는 팩 탐색 (최우선)
        target_pack_by_song = None
        if has_selected_song:
            for pack in self.pack_items:
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
        current_id = self.current_pack.get('id') if self.current_pack else None

        if has_selected_song and target_pack_by_song:
            # [요구사항 1] 선택된 악곡이 새 모드/필터의 팩에 존재함 -> 해당 팩으로 전환/유지
            new_current = target_pack_by_song
            self.expanded_pack_ids = {target_pack_by_song['id']}

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
                self._handler._selected_item = self._service.build_song_item(song_data, filters=filters)
                self._handler._selected_song_db_id = self._handler._selected_item.get('songDbId') if self._handler._selected_item else None
                # 현재 팩 모드의 팩 정보(이름, 약어, 색상)로 동기화
                if self._handler._selected_item and target_pack_by_song:
                    self._handler._selected_item['pack'] = target_pack_by_song.get('name', self._handler._selected_item.get('pack'))
                    self._handler._selected_item['packAbbr'] = target_pack_by_song.get('abbr', self._handler._selected_item.get('packAbbr'))
                    self._handler._selected_item['packColor'] = target_pack_by_song.get('color', self._handler._selected_item.get('packColor'))
                self._handler._attach_details_to_selected()
                item_metadata_updated = True

        elif has_selected_song and not target_pack_by_song:
            # [요구사항 2] 선택된 악곡이 필터 등에 의해 제외됨
            target_pack = next((p for p in self.pack_items if p.get('id') == current_id), None)
            if target_pack and len(target_pack.get('songs', [])) > 0:
                # Case A: 팩 내 다른 유효 악곡이 남아있는 경우 -> 악곡 선택 해제 및 팩 대시보드로 복귀
                new_current = target_pack
                self.expanded_pack_ids = {target_pack['id']}
                self._handler._selected_item = None
                self._handler._selected_song_db_id = None
                self.is_pack_detail_view = True
            else:
                # Case B: 팩 내 잔여 곡이 0개가 된 경우 -> 팩 선택 해제 및 전체 팩 목록 복귀 (Task 45/Task 82 연동)
                self.expanded_pack_ids.clear()
                self.is_pack_detail_view = True
                self._handler._selected_item = None
                self._handler._selected_song_db_id = None
                new_current = self.pack_items[0] if self.pack_items else None

        else:
            # 악곡이 선택되지 않은 상태 (팩 대시보드 또는 팩 목록)
            if self.expanded_pack_ids:
                target_pack = next((p for p in self.pack_items if p.get('id') == current_id), None)
                if target_pack and len(target_pack.get('songs', [])) > 0:
                    new_current = target_pack
                    self.expanded_pack_ids = {target_pack['id']}
                else:
                    # [요구사항 1 Fallback] 이전 팩이 사라진 경우(Strict -> Conceptual), 이전 팩의 곡들을 흡수한 부모 팩 검색
                    fallback_parent_pack = None
                    prev_songs = self.current_pack.get('songs', []) if self.current_pack else []
                    for prev_s in prev_songs:
                        prev_sid = prev_s.get('songDbId')
                        prev_aid = prev_s.get('arcaeaId') or prev_s.get('id')
                        for pack in self.pack_items:
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
                        self.expanded_pack_ids = {fallback_parent_pack['id']}
                    else:
                        self.expanded_pack_ids.clear()
                        self.is_pack_detail_view = True
                        new_current = self.pack_items[0] if self.pack_items else None
            else:
                new_current = self.pack_items[0] if self.pack_items else None

        pack_changed = (self.current_pack is not new_current)
        self.current_pack = new_current
        self._handler.packItemsChanged.emit()

        # [Task 82] QML 트랜지션 머신이 먼저 deselect 상태를 인지해 cachedLastPack을 보존하도록 선행 방출
        if self.expanded_pack_ids != old_expanded_ids:
            self._handler.expandedPackIdsChanged.emit()
        if self.is_pack_detail_view != old_is_pack_detail_view:
            self._handler.isPackDetailViewChanged.emit()
        if item_metadata_updated or (self._handler._selected_item is not old_selected_item):
            self._handler.selectedItemChanged.emit()

        if pack_changed:
            self._handler.currentPackChanged.emit()

    def handle_set_display_mode_pack(self, old_mode: str):
        """setDisplayMode('pack') 진입 시 팩 캐시 검사 및 초기 팩 선정 처리."""
        self.is_pack_detail_view = True

        # 1. 팩 아이템 목록 캐시 유효성 검사 후 최신화
        if self.pack_items_dirty or not self.pack_items:
            filters = self._handler._get_filter_params()
            self.pack_items = self._service.get_pack_items(
                filters=filters,
                sort_mode=self._handler._sort_mode,
                sort_ascending=self._handler._sort_ascending,
                search_text=self._handler._search_text,
                classification_mode=self._handler.packClassificationMode,
            )
            self.pack_items_dirty = False

        # 2. 직전 선택 곡이 속한 팩 사전 계산 및 expanded_pack_ids 확정
        target_pack = None
        if old_mode in ["song", "chart"] and self._handler._selected_item:
            selected_song_id = self._handler._selected_item.get('arcaeaId') or self._handler._selected_item.get('id')
            selected_db_id = self._handler._selected_item.get('songDbId') or self._handler._selected_song_db_id
            if selected_db_id is not None:
                self._handler._last_selected_song_db_id = selected_db_id
            for pack in self.pack_items:
                if any(
                    (selected_db_id is not None and s.get('songDbId') == selected_db_id)
                    or (selected_song_id and (s.get('arcaeaId') == selected_song_id or s.get('id') == selected_song_id))
                    for s in pack.get('songs', [])
                ):
                    target_pack = pack
                    break

        if target_pack:
            self.current_pack = target_pack
            self.expanded_pack_ids = {target_pack['id']}
        else:
            self.expanded_pack_ids.clear()
            self.current_pack = self.pack_items[0] if self.pack_items else None

        # [Task 84 / Detailed View Transition]
        self._handler.displayModeChanged.emit()
        self._handler.isPackDetailViewChanged.emit()

        # 팩 대시보드로 진입하므로 선택 곡 비움 (직전 곡은 _last_selected_song_db_id에 보존)
        self._handler._selected_item = None
        self._handler._selected_song_db_id = None

        # 3. 모든 상태가 완전히 세팅된 후 원자적으로 잔여 시그널 일괄 방출
        self._handler.expandedPackIdsChanged.emit()
        self._handler.currentPackChanged.emit()
        self._handler.packItemsChanged.emit()
        self._handler.dataChanged.emit()
        self._handler.selectedItemChanged.emit()

    def toggle_pack_expansion(self, pack_id: str):
        """팩 선택/해제 토글, 대상 팩 드릴다운 및 대시보드 뷰 활성화."""
        if not pack_id:
            return

        target_pack = next((p for p in self.pack_items if p.get('id') == pack_id), None)
        if not target_pack:
            return

        if pack_id in self.expanded_pack_ids:
            self.expanded_pack_ids.clear()
            self.is_pack_detail_view = True
            self._handler._selected_item = None
            self._handler._selected_song_db_id = None
            self._handler._last_selected_song_db_id = None
            self._handler.selectedItemChanged.emit()
            self._handler.isPackDetailViewChanged.emit()
            self._handler.expandedPackIdsChanged.emit()
            return

        self.expanded_pack_ids = {pack_id}
        self.current_pack = target_pack
        self.is_pack_detail_view = True
        self._handler._selected_item = None
        self._handler._selected_song_db_id = None

        self._handler.expandedPackIdsChanged.emit()
        self._handler.currentPackChanged.emit()
        self._handler.isPackDetailViewChanged.emit()
        self._handler.selectedItemChanged.emit()
        self._handler.packItemsChanged.emit()

    def clear_pack_selection(self):
        """팩 선택 해제 -> 전체 팩 목록으로 복귀."""
        self.expanded_pack_ids.clear()
        self.is_pack_detail_view = True
        self._handler._selected_item = None
        self._handler._selected_song_db_id = None
        self._handler._last_selected_song_db_id = None
        self._handler.isPackDetailViewChanged.emit()
        self._handler.selectedItemChanged.emit()
        self._handler.expandedPackIdsChanged.emit()

    def select_pack_song(self, pack_id: str, song_db_id: Any, target_difficulty: int = -1):
        """팩 내 수록곡 선택 -> 곡 상세 뷰 전환 및 해당 곡 정보 바인딩."""
        self.is_pack_detail_view = False

        if pack_id and (not self.current_pack or self.current_pack.get('id') != pack_id):
            target_pack = next((p for p in self.pack_items if p.get('id') == pack_id), None)
            if target_pack:
                self.current_pack = target_pack
                self.expanded_pack_ids = {pack_id}
                self._handler.expandedPackIdsChanged.emit()
                self._handler.currentPackChanged.emit()

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
            for pack in self.pack_items:
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
            filters = self._handler._get_filter_params()
            song_item = self._service.build_song_item(song_data, filters=filters)
            self._handler._selected_item = song_item
            self._handler._selected_song_db_id = song_item.get('songDbId') if song_item else None

            if target_difficulty is not None and 0 <= target_difficulty <= 4:
                self._handler._selected_difficulty = target_difficulty
            else:
                best_diff = self._service.get_best_diff_for_sort(
                    self._handler._selected_item, self._handler._sort_mode
                )
                if best_diff >= 0:
                    self._handler._selected_difficulty = best_diff
                else:
                    all_diffs = self._handler._get_item_detail_difficulties(self._handler._selected_item)
                    for diff_num in [3, 4, 2, 1, 0]:
                        if any(d.get('difficulty') == diff_num and not d.get('isFiltered', False) for d in all_diffs):
                            self._handler._selected_difficulty = diff_num
                            break

            self._handler._attach_details_to_selected()
            if self._handler._selected_song_db_id is not None:
                self._handler._last_selected_song_db_id = self._handler._selected_song_db_id

        self._handler.selectedItemChanged.emit()
        self._handler.isPackDetailViewChanged.emit()

    def return_to_pack_dashboard(self):
        """곡 상세 뷰에서 팩 종합 대시보드로 복귀."""
        self.is_pack_detail_view = True
        if self._handler._selected_song_db_id is not None:
            self._handler._last_selected_song_db_id = self._handler._selected_song_db_id
        self._handler._selected_item = None
        self._handler._selected_song_db_id = None
        self._handler.isPackDetailViewChanged.emit()
        self._handler.selectedItemChanged.emit()

    def select_pack_by_name(self, pack_name: str) -> bool:
        """곡 상세 뷰 헤더의 팩 알약 클릭 시 해당 팩의 대시보드로 이동."""
        if not pack_name:
            return False

        # 1. 팩 모드로 전환
        if self._handler._display_mode != "pack":
            self._handler.setDisplayMode("pack")

        # 2. 팩 목록에서 대상 팩 탐색 (Full Name 또는 Abbr 매칭)
        target_pack = None
        for p in self.pack_items:
            if (
                p.get('name') == pack_name
                or p.get('abbr') == pack_name
                or p.get('id') == pack_name
                or str(p.get('name', '')).lower() == pack_name.lower()
                or str(p.get('abbr', '')).lower() == pack_name.lower()
            ):
                target_pack = p
                break

        # 3. 직접 매칭 실패 시 수록곡 기반 Fallback
        if not target_pack:
            pack_name_lower = pack_name.lower()
            for p in self.pack_items:
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
            # [Smart Route] If already in pack mode and the same pack is open, delegate to return_to_pack_dashboard
            # to prevent unnecessary list view refresh (dataChanged / expandedPackIdsChanged emissions)
            if (
                self._handler._display_mode == "pack"
                and self.current_pack
                and self.current_pack.get('id') == target_pack.get('id')
                and target_pack.get('id') in self.expanded_pack_ids
            ):
                self.return_to_pack_dashboard()
                return True

            self.current_pack = target_pack
            self.expanded_pack_ids = {target_pack['id']}
            self.is_pack_detail_view = True
            self._handler.displayModeChanged.emit()
            self._handler.isPackDetailViewChanged.emit()
            self._handler._selected_item = None
            self._handler._selected_song_db_id = None
            self._handler.expandedPackIdsChanged.emit()
            self._handler.currentPackChanged.emit()
            self._handler.packItemsChanged.emit()
            self._handler.dataChanged.emit()
            self._handler.selectedItemChanged.emit()
            return True

        return False
