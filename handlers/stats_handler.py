"""Home 탭 통계 핸들러: 플레이 통계, Most Played, 썸네일."""
import os

from PyQt6.QtCore import QObject, pyqtSlot, pyqtSignal, QVariant

from configuration import config
from models.constants import DIFFICULTY_ORDER, DIFFICULTY_NAMES, DIFFICULTY_COLORS
from services.score_query_service import play_stats_total, play_stats_difficulty, get_top_10_most_played
from services.thumbnail_service import ThumbnailService


class StatsHandler(QObject):
    statsChanged = pyqtSignal()

    def __init__(self):
        super().__init__()
        self._total_count = 0
        self._total_time_str = "0h 0m"
        self._difficulty_stats = []
        self._thumbnail_service = ThumbnailService(self._thumbnails_dir)
        self.refreshStats()

    @property
    def _thumbnails_dir(self):
        """동적으로 현재 cache_path 기반 thumbnails 디렉토리 반환."""
        return os.path.join(config['general']['cache_path'], 'thumbnails')

    @pyqtSlot(result=int)
    def getTotalPlayCount(self):
        return self._total_count

    @pyqtSlot(result=str)
    def getTotalPlayTime(self):
        return self._total_time_str

    @pyqtSlot(result='QVariant')
    def getDifficultyStats(self):
        return self._difficulty_stats

    @pyqtSlot(result=list)
    def getMostPlayed(self):
        cache_path = config['general']['cache_path']
        return get_top_10_most_played(
            cache_path=cache_path,
            difficulty_filter=config['profile']['difficulty_filter'],
            grouping_criteria=config['profile']['grouping_criteria'],
            most_played_scope=config['profile']['most_played_scope'],
            song_title_language=config['general']['song_title_language'],
        )

    @pyqtSlot(str, result=str)
    def getThumbnailPath(self, arcaea_id: str) -> str:
        self._thumbnail_service.thumbnails_dir = self._thumbnails_dir
        return self._thumbnail_service.get_path(arcaea_id)

    @pyqtSlot(str, result=str)
    def getSongTitle(self, arcaea_id: str) -> str:
        from repositories.song_repository import get_song_title
        title = get_song_title(
            arcaea_id,
            song_title_language=config['general']['song_title_language'],
        )
        return title if title else ""

    @pyqtSlot(str, int, result=str)
    def getSongTitleForDifficulty(self, arcaea_id: str, difficulty: int) -> str:
        from repositories.song_repository import get_song_title
        title = get_song_title(
            arcaea_id,
            difficulty,
            song_title_language=config['general']['song_title_language'],
        )
        if title:
            return title
        # Fallback keeps legacy behavior when chart metadata is missing.
        legacy_title = get_song_title(
            arcaea_id,
            song_title_language=config['general']['song_title_language'],
        )
        return legacy_title if legacy_title else ""

    @pyqtSlot(str, int, result=str)
    def getThumbnailPathForDifficulty(self, arcaea_id: str, difficulty: int) -> str:
        self._thumbnail_service.thumbnails_dir = self._thumbnails_dir
        return self._thumbnail_service.get_path_for_difficulty(arcaea_id, difficulty)

    @pyqtSlot(str, int, result=str)
    def getThumbnailColor(self, arcaea_id: str, difficulty: int) -> str:
        self._thumbnail_service.thumbnails_dir = self._thumbnails_dir
        return self._thumbnail_service.get_representative_color(arcaea_id, difficulty)

    @pyqtSlot()
    def refreshStats(self):
        cache_path = config['general']['cache_path']
        count, seconds = play_stats_total(cache_path)
        self._total_count = count

        hours = seconds // 3600
        minutes = (seconds % 3600) // 60
        self._total_time_str = f"{hours}h {minutes}m"

        diff_info = [
            (code, DIFFICULTY_NAMES[code], DIFFICULTY_COLORS[code])
            for code in DIFFICULTY_ORDER
        ]

        stats = []
        for code, name, color in diff_info:
            diff_count, diff_seconds = play_stats_difficulty(cache_path, code)
            diff_hours = diff_seconds // 3600
            diff_minutes = (diff_seconds % 3600) // 60
            stats.append({
                'name': name,
                'color': color,
                'count': diff_count,
                'time': f"{diff_hours}.{diff_minutes:02d}"
            })

        self._difficulty_stats = stats
        self.statsChanged.emit()
