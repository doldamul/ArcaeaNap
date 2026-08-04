"""Home 탭 통계 핸들러: 플레이 통계, Most Played, 썸네일."""
import os

from PyQt6.QtCore import QObject, pyqtSlot, pyqtSignal, QVariant

from utils.configuration import config, get_cache_dir
from models.constants import DIFFICULTY_ORDER, DIFFICULTY_NAMES
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
        return os.path.join(get_cache_dir(), 'thumbnails')

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
        cache_path = get_cache_dir()
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
    def getExactThumbnailPathForDifficulty(self, arcaea_id: str, difficulty: int) -> str:
        self._thumbnail_service.thumbnails_dir = self._thumbnails_dir
        return self._thumbnail_service.get_exact_path_for_difficulty(arcaea_id, difficulty)

    @pyqtSlot(str, int, result=str)
    def getThumbnailColor(self, arcaea_id: str, difficulty: int) -> str:
        self._thumbnail_service.thumbnails_dir = self._thumbnails_dir
        return self._thumbnail_service.get_representative_color(arcaea_id, difficulty)

    @pyqtSlot()
    def refreshStats(self):
        cache_path = get_cache_dir()
        
        diff_info = [
            (code, DIFFICULTY_NAMES[code])
            for code in DIFFICULTY_ORDER
        ]

        stats = []
        total_count = 0
        total_seconds = 0

        # get filter
        diff_filter_str = config['profile']['play_stats_diff_filter']
        if diff_filter_str == 'all':
            filter_set = set(DIFFICULTY_ORDER)
            is_off = False
        elif diff_filter_str == 'off':
            filter_set = set(DIFFICULTY_ORDER)
            is_off = True
        else:
            from models.constants import DIFFICULTY_CODE_TO_INT
            filter_set = set(DIFFICULTY_CODE_TO_INT.get(d) for d in diff_filter_str.split(',') if d in DIFFICULTY_CODE_TO_INT)
            is_off = False

        for code, name in diff_info:
            diff_count, diff_seconds = play_stats_difficulty(cache_path, code)
            
            # If off, we compute total but don't append to stats list
            if is_off:
                total_count += diff_count
                total_seconds += diff_seconds
            else:
                if code in filter_set:
                    total_count += diff_count
                    total_seconds += diff_seconds
                    diff_hours = diff_seconds // 3600
                    diff_minutes = (diff_seconds % 3600) // 60
                    stats.append({
                        'name': name,
                        'difficulty': code,
                        'count': diff_count,
                        'time': f"{diff_hours}.{diff_minutes:02d}"
                    })

        self._total_count = total_count
        hours = total_seconds // 3600
        minutes = (total_seconds % 3600) // 60
        self._total_time_str = f"{hours}h {minutes}m"
        self._difficulty_stats = stats
        self.statsChanged.emit()
