"""Statistics 탭용 QAbstractListModel 구현."""

from PyQt6.QtCore import Qt, QAbstractListModel, QModelIndex, QByteArray


class StatisticsListModel(QAbstractListModel):
    """Statistics 리스트를 QML role 기반으로 노출하는 모델."""

    # 공통 role
    ArcaeaIdRole = Qt.ItemDataRole.UserRole + 1
    TitleRole = Qt.ItemDataRole.UserRole + 2
    ArtistRole = Qt.ItemDataRole.UserRole + 3
    DisplayValueRole = Qt.ItemDataRole.UserRole + 4
    HasScoreRole = Qt.ItemDataRole.UserRole + 5
    BpRole = Qt.ItemDataRole.UserRole + 6

    # Chart 모드 role
    DifficultyRole = Qt.ItemDataRole.UserRole + 10
    DifficultyNameRole = Qt.ItemDataRole.UserRole + 11
    LevelRole = Qt.ItemDataRole.UserRole + 13
    IgnoreChartRole = Qt.ItemDataRole.UserRole + 14
    SkillIssuesRole = Qt.ItemDataRole.UserRole + 15
    ThumbnailDifficultyRole = Qt.ItemDataRole.UserRole + 16
    BestScoreRole = Qt.ItemDataRole.UserRole + 17

    # Song 모드 role
    FilteredDifficultiesRole = Qt.ItemDataRole.UserRole + 20
    BestDiffForScoreRole = Qt.ItemDataRole.UserRole + 21
    BestDiffForMaxRole = Qt.ItemDataRole.UserRole + 22
    BestDiffForRecentRole = Qt.ItemDataRole.UserRole + 23
    BestDiffForLevelRole = Qt.ItemDataRole.UserRole + 24
    BestDiffForSBpRole = Qt.ItemDataRole.UserRole + 25
    BestDiffForPerceivedBpRole = Qt.ItemDataRole.UserRole + 26
    SongDbIdRole = Qt.ItemDataRole.UserRole + 27
    BestDiffForPotentialRole = Qt.ItemDataRole.UserRole + 28
    DiffColorTagRole = Qt.ItemDataRole.UserRole + 29
    IsInscribedRole = Qt.ItemDataRole.UserRole + 30
    IsBest10Role = Qt.ItemDataRole.UserRole + 31
    BestDiffForNoteCountRole = Qt.ItemDataRole.UserRole + 32
    IsSongFavoriteRole = Qt.ItemDataRole.UserRole + 33
    ChartFavoritesRole = Qt.ItemDataRole.UserRole + 34
    IsChartFavoriteRole = Qt.ItemDataRole.UserRole + 35
    IsPackFavoriteRole = Qt.ItemDataRole.UserRole + 36

    _ROLE_KEY_MAP = {
        ArcaeaIdRole: "arcaeaId",
        TitleRole: "title",
        ArtistRole: "artist",
        DisplayValueRole: "displayValue",
        HasScoreRole: "hasScore",
        BpRole: "bp",
        DifficultyRole: "difficulty",
        DifficultyNameRole: "difficultyName",
        LevelRole: "level",
        IgnoreChartRole: "ignoreChart",
        SkillIssuesRole: "skillIssues",
        ThumbnailDifficultyRole: "thumbnailDifficulty",
        BestScoreRole: "bestScore",
        FilteredDifficultiesRole: "filteredDifficulties",
        BestDiffForScoreRole: "bestDiffForScore",
        BestDiffForMaxRole: "bestDiffForMax",
        BestDiffForRecentRole: "bestDiffForRecent",
        BestDiffForLevelRole: "bestDiffForLevel",
        BestDiffForSBpRole: "bestDiffForSBp",
        BestDiffForPerceivedBpRole: "bestDiffForPerceivedBp",
        SongDbIdRole: "songDbId",
        BestDiffForPotentialRole: "bestDiffForPotential",
        DiffColorTagRole: "diffColorTag",
        IsInscribedRole: "isInscribed",
        IsBest10Role: "isBest10",
        BestDiffForNoteCountRole: "bestDiffForNoteCount",
        IsSongFavoriteRole: "isSongFavorite",
        ChartFavoritesRole: "chartFavorites",
        IsChartFavoriteRole: "isChartFavorite",
        IsPackFavoriteRole: "isPackFavorite",
    }

    def __init__(self, parent=None):
        super().__init__(parent)
        self._items: list[dict] = []

    def rowCount(self, parent=QModelIndex()):
        if parent.isValid():
            return 0
        return len(self._items)

    def data(self, index, role=Qt.ItemDataRole.DisplayRole):
        if not index.isValid() or index.row() >= len(self._items):
            return None
        key = self._ROLE_KEY_MAP.get(role)
        if key is None:
            return None
        return self._items[index.row()].get(key)

    def roleNames(self):
        return {
            role: QByteArray(key.encode("utf-8"))
            for role, key in self._ROLE_KEY_MAP.items()
        }

    def reset_items(self, new_items: list[dict]):
        """필터/모드 전환 등 목록 전체 교체 시 사용."""
        self.beginResetModel()
        self._items = new_items
        self.endResetModel()

    def get_item(self, row: int):
        if 0 <= row < len(self._items):
            return self._items[row]
        return None

    def get_items(self) -> list[dict]:
        return self._items

    def update_favorite_status(self, target_type: str, arcaea_id: str, difficulty: int, is_fav: bool):
        """특정 대상의 즐겨찾기 상태를 인플레이스로 갱신하고 부분 dataChanged 시그널을 방출한다."""
        diff_int = int(difficulty) if difficulty is not None else -1
        for row, item in enumerate(self._items):
            if item.get('arcaeaId') != arcaea_id:
                continue
            changed_roles = []
            idx = self.index(row, 0)
            if target_type == 'song':
                item['isSongFavorite'] = is_fav
                changed_roles.append(self.IsSongFavoriteRole)
            elif target_type == 'chart':
                if 'difficulty' in item:
                    # Chart 모드 아이템: 일치하는 난이도만 갱신
                    if item.get('difficulty') == diff_int:
                        item['isChartFavorite'] = is_fav
                        item['isFavorite'] = is_fav
                        changed_roles.append(self.IsChartFavoriteRole)
                else:
                    # Song 모드 아이템: chartFavorites 및 filteredDifficulties 갱신
                    chart_favs = set(item.get('chartFavorites', []))
                    if is_fav:
                        chart_favs.add(diff_int)
                    else:
                        chart_favs.discard(diff_int)
                    item['chartFavorites'] = list(sorted(chart_favs))
                    changed_roles.append(self.ChartFavoritesRole)

                    new_diffs = [dict(d) for d in item.get('filteredDifficulties', [])]
                    for d in new_diffs:
                        if d.get('difficulty') == diff_int:
                            d['isFavorite'] = is_fav
                    item['filteredDifficulties'] = new_diffs
                    changed_roles.append(self.FilteredDifficultiesRole)

            if changed_roles:
                self.dataChanged.emit(idx, idx, changed_roles)
