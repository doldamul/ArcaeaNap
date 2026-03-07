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
    DifficultyColorRole = Qt.ItemDataRole.UserRole + 12
    LevelRole = Qt.ItemDataRole.UserRole + 13
    IgnoreChartRole = Qt.ItemDataRole.UserRole + 14
    SkillIssuesRole = Qt.ItemDataRole.UserRole + 15
    ThumbnailDifficultyRole = Qt.ItemDataRole.UserRole + 16

    # Song 모드 role
    FilteredDifficultiesRole = Qt.ItemDataRole.UserRole + 20
    BestDiffForScoreRole = Qt.ItemDataRole.UserRole + 21
    BestDiffForMaxRole = Qt.ItemDataRole.UserRole + 22
    BestDiffForRecentRole = Qt.ItemDataRole.UserRole + 23
    BestDiffForLevelRole = Qt.ItemDataRole.UserRole + 24
    BestDiffForSBpRole = Qt.ItemDataRole.UserRole + 25
    BestDiffForPerceivedBpRole = Qt.ItemDataRole.UserRole + 26

    _ROLE_KEY_MAP = {
        ArcaeaIdRole: "arcaeaId",
        TitleRole: "title",
        ArtistRole: "artist",
        DisplayValueRole: "displayValue",
        HasScoreRole: "hasScore",
        BpRole: "bp",
        DifficultyRole: "difficulty",
        DifficultyNameRole: "difficultyName",
        DifficultyColorRole: "difficultyColor",
        LevelRole: "level",
        IgnoreChartRole: "ignoreChart",
        SkillIssuesRole: "skillIssues",
        ThumbnailDifficultyRole: "thumbnailDifficulty",
        FilteredDifficultiesRole: "filteredDifficulties",
        BestDiffForScoreRole: "bestDiffForScore",
        BestDiffForMaxRole: "bestDiffForMax",
        BestDiffForRecentRole: "bestDiffForRecent",
        BestDiffForLevelRole: "bestDiffForLevel",
        BestDiffForSBpRole: "bestDiffForSBp",
        BestDiffForPerceivedBpRole: "bestDiffForPerceivedBp",
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
