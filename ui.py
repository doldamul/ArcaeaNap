from configuration import config
import sys
import os
import threading
import time
import random
import json
import keyring
from datetime import datetime
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQml import QQmlApplicationEngine
from PyQt6.QtCore import QUrl, QObject, pyqtSlot, pyqtSignal, pyqtProperty, QVariant
from PyQt6.QtGui import QImage, QColor, QSurfaceFormat
from web_arcaeaonline import ArcaeaOnline
from web_consultantsheet import open_sheet, get_sheet_version_info
from web_wiki import open_wiki
from db_utils import (
    get_db_path, play_stats_total, play_stats_difficulty, get_top_10_most_played,
    get_all_songs_with_charts, get_best_scores_per_chart, get_play_counts, 
    get_this_year_play_counts, calculate_rank
)

def rebuild_songs_db():
    """Delete existing songs.db and rebuild from online sources (ConsultantSheet + Wiki)."""
    db_path = get_db_path()
    if os.path.exists(db_path):
        os.remove(db_path)
        print(f"[rebuild_songs_db] Deleted existing {db_path}")

    print("[rebuild_songs_db] Loading data from Consultant Sheet...")
    open_sheet()
    print("[rebuild_songs_db] Consultant Sheet load successful.")

    print("[rebuild_songs_db] Loading data from Wiki...")
    open_wiki()
    print("[rebuild_songs_db] Wiki load successful.")


class StartupHandler(QObject):
    loadingStarted = pyqtSignal()
    loadingFinished = pyqtSignal()
    errorOccurred = pyqtSignal(str)
    logAdded = pyqtSignal(str) 

    def __init__(self):
        super().__init__()
        self.thread = None

    @pyqtSlot()
    def checkAndLoad(self):
        db_path = get_db_path()
        if os.path.exists(db_path):
            print("songs.db exists. Skipping initial data load.")
            self.loadingFinished.emit()
            return

        print("songs.db missing. Starting initial data load...")
        self.loadingStarted.emit()
        
        self.thread = threading.Thread(target=self._load_data, daemon=True)
        self.thread.start()

    def _load_data(self):
        try:
            rebuild_songs_db()
            self.loadingFinished.emit()
        except Exception as e:
            print(f"Data loading failed: {e}")
            self.errorOccurred.emit(str(e))
            self.loadingFinished.emit()

class AnalysisHandler(QObject):
    logAdded = pyqtSignal(str, arguments=['message'])
    dataUpdated = pyqtSignal()  # Emitted when user_scores.db or thumbnails are updated
    pinUpdated = pyqtSignal()   # Emitted when pin data is updated
    statusChanged = pyqtSignal(str, arguments=['status'])  # Emitted when analysis status changes
    progressChanged = pyqtSignal() # Emitted when progress data (checked_page/total_page) changes
    sessionReset = pyqtSignal(str, arguments=['message'])  # Emitted when session is auto-reset

    def __init__(self):
        super().__init__()
        self.analyzer = ArcaeaOnline()  # Create on init to load pin_updates from DB
        self.thread = None
        self._settings_handler = None  # Reference to SettingsHandler
    
    def set_settings_handler(self, settings_handler):
        """Set reference to SettingsHandler for connection status updates."""
        self._settings_handler = settings_handler

    @pyqtSlot()
    def startAnalysis(self):
        if self.thread and self.thread.is_alive():
            print("Analysis already running.")
            return

        print("Starting analysis thread...")
        # Reuse existing analyzer or create new one
        if not self.analyzer:
            self.analyzer = ArcaeaOnline()
        self.analyzer.set_log_callback(self.emit_log)
        self.analyzer.set_data_changed_callback(self.emit_data_updated)
        self.analyzer.set_pin_changed_callback(self.emit_pin_updated)
        self.analyzer.set_status_changed_callback(self.emit_status_changed)
        self.analyzer.set_progress_changed_callback(self.emit_progress_changed)
        self.analyzer.set_session_reset_callback(self.emit_session_reset)
        self.analyzer.set_login_completed_callback(self.emit_login_completed)
        
        self.thread = threading.Thread(target=self.analyzer.start, daemon=True)
        self.thread.start()

    @pyqtSlot()
    def stopAnalysis(self):
        if self.analyzer:
            print("Stopping analysis...")
            self.analyzer.stop()
            # Thread will join naturally as start() returns

    def emit_log(self, message):
        self.logAdded.emit(message)
    
    def emit_data_updated(self):
        self.dataUpdated.emit()
    
    def emit_pin_updated(self):
        self.pinUpdated.emit()
    
    def emit_status_changed(self):
        if self.analyzer:
            self.statusChanged.emit(self.analyzer.status.status)

    def emit_progress_changed(self):
        self.progressChanged.emit()

    def emit_session_reset(self, message):
        self.sessionReset.emit(message)
    
    def emit_login_completed(self):
        """Called when login is completed - notify SettingsHandler to update UI."""
        if self._settings_handler:
            self._settings_handler.arcaeaOnlineConnectionChanged.emit()

    @pyqtSlot(result=str)
    def getStatus(self):
        """Returns current analysis status: 'closed', 'login', 'ready', 'analyzing'"""
        if self.analyzer:
            return self.analyzer.status.status
        return 'closed'

    @pyqtSlot(result='QVariant')
    def getPinDates(self):
        """
        Returns extended pin data for each difficulty.
        Returns: 
            dict: { 
                difficulty_code(str): {
                    'updated_at': int,     # pin updated timestamp (ms)
                    'time_played': int,    # score time_played (ms)
                    'arcaea_id': str       # song ID for thumbnail lookup
                }
            }
        """
        import sqlite3
        result = {}
        
        try:
            db_path = os.path.join(config['general']['cache_path'], 'user_scores.db')
            if not os.path.exists(db_path):
                return {}
            
            with sqlite3.connect(db_path) as conn:
                cursor = conn.cursor()
                # Join pin with scores to get time_played and arcaea_id
                cursor.execute('''
                    SELECT p.difficulty, p.updated_at, s.time_played, s.arcaea_id
                    FROM pin p
                    LEFT JOIN scores s ON p.score_id = s.id
                    WHERE p.updated_at IS NOT NULL
                ''')
                
                for row in cursor.fetchall():
                    difficulty, updated_at, time_played, arcaea_id = row
                    result[str(difficulty)] = {
                        'updated_at': updated_at or 0,
                        'time_played': time_played or 0,
                        'arcaea_id': arcaea_id or ''
                    }
        except Exception as e:
            print(f"Error in getPinDates: {e}")
            # Fallback to simple pin_updates if DB query fails
            if self.analyzer and self.analyzer.status.pin_updates:
                for k, v in self.analyzer.status.pin_updates.items():
                    result[str(k)] = {'updated_at': v, 'time_played': 0, 'arcaea_id': ''}
        
        return result
    
    @pyqtSlot(result='QVariant')
    def getProgress(self):
        """Returns current scraping progress for each difficulty."""
        if not self.analyzer:
            return {}
        
        result = {}
        for diff in range(5):
            checked = len(self.analyzer.checked_page.get(diff, set()))
            total = self.analyzer.total_page.get(diff)
            result[str(diff)] = {"checked": checked, "total": total}
        return result

    @pyqtSlot(result=bool)
    def isPlayCountMode(self):
        """Returns whether Play Count Analyze Mode is active."""
        if not self.analyzer:
            return False
        return self.analyzer.play_count_mode

    @pyqtSlot(result='QVariant')
    def getCountModeProgress(self):
        """Returns Play Count Analyze Mode progress for each difficulty."""
        if not self.analyzer:
            return {}
        
        cm = self.analyzer.count_mode
        result = {}
        for diff in range(5):
            checked = len(cm.checked_pages.get(diff, set()))
            total = cm.total_pages.get(diff)
            completed = diff in cm.completed
            result[str(diff)] = {"checked": checked, "total": total, "completed": completed}
        return result

    @pyqtSlot(result='QVariant')
    def getRandomThumbnails(self):
        """Returns 5 random thumbnail paths if available, otherwise empty list."""
        try:
            thumbnails_dir = os.path.join(config['general']['cache_path'], 'thumbnails')
            if not os.path.exists(thumbnails_dir):
                return []
            
            files = [f for f in os.listdir(thumbnails_dir) if f.lower().endswith(('.jpg', '.png'))]
            if len(files) < 5:
                return []
                
            selected = random.sample(files, 5)
            return [QUrl.fromLocalFile(os.path.join(thumbnails_dir, f)).toString() for f in selected]
        except Exception as e:
            print(f"Error getting random thumbnails: {e}")
            return []

class StatsHandler(QObject):
    statsChanged = pyqtSignal()
    
    def __init__(self):
        super().__init__()
        self._total_count = 0
        self._total_time_str = "0h 0m"
        self._difficulty_stats = []  # Pre-calculated difficulty stats
        self.refreshStats()
    
    @property
    def _thumbnails_dir(self):
        """동적으로 현재 cache_path 기반 thumbnails 디렉토리 반환"""
        return os.path.join(config['general']['cache_path'], 'thumbnails')

    @pyqtSlot(result=int)
    def getTotalPlayCount(self):
        return self._total_count

    @pyqtSlot(result=str)
    def getTotalPlayTime(self):
        return self._total_time_str
    
    @pyqtSlot(result='QVariant')
    def getDifficultyStats(self):
        """Returns pre-calculated difficulty stats list."""
        return self._difficulty_stats

    @pyqtSlot(result=list)
    def getMostPlayed(self):
        return get_top_10_most_played()

    def _find_thumbnail_by_priority(self, arcaea_id: str) -> str:
        """우선순위에 따라 썸네일 검색: FTR > BYD > ETR > PRS > PST"""
        difficulty_priority = ['ftr', 'byd', 'etr', 'prs', 'pst']
        
        for diff in difficulty_priority:
            filename = f"{arcaea_id}_{diff}.jpg"
            filepath = os.path.join(self._thumbnails_dir, filename)
            if os.path.exists(filepath):
                return QUrl.fromLocalFile(filepath).toString()
        
        return ""
    
    @pyqtSlot(str, result=str)
    def getThumbnailPath(self, arcaea_id: str) -> str:
        """arcaea_id만으로 썸네일 경로 반환 (우선순위 검색)"""
        if not arcaea_id:
            return ""
        return self._find_thumbnail_by_priority(arcaea_id)

    @pyqtSlot(str, result=str)
    def getSongTitle(self, arcaea_id: str) -> str:
        from db_utils import get_song_title
        title = get_song_title(arcaea_id)
        return title if title else ""
    
    @pyqtSlot(str, int, result=str)
    def getThumbnailPathForDifficulty(self, arcaea_id: str, difficulty: int) -> str:
        """
        주어진 arcaea_id와 difficulty에 해당하는 썸네일 경로를 반환
        해당 난이도 썸네일이 없으면 우선순위로 fallback
        """
        if not arcaea_id:
            return ""
        
        # 난이도 번호 -> 파일명 난이도 코드 매핑
        diff_code_map = {0: 'pst', 1: 'prs', 2: 'ftr', 3: 'byd', 4: 'etr'}
        
        if difficulty >= 0 and difficulty in diff_code_map:
            # 특정 난이도의 썸네일 검색
            diff_code = diff_code_map[difficulty]
            filename = f"{arcaea_id}_{diff_code}.jpg"
            filepath = os.path.join(self._thumbnails_dir, filename)
            if os.path.exists(filepath):
                return QUrl.fromLocalFile(filepath).toString()
            # 해당 난이도 썸네일이 없으면 우선순위로 fallback
        
        return self._find_thumbnail_by_priority(arcaea_id)

    @pyqtSlot(str, int, result=str)
    def getThumbnailColor(self, arcaea_id: str, difficulty: int) -> str:
        """
        Calculates the representative color of the thumbnail for the given song and difficulty.
        Returns a hex color string (e.g. "#FF0000").
        The color is boosted in brightness and saturation to ensure it glows against dark backgrounds.
        """
        path_url = self.getThumbnailPathForDifficulty(arcaea_id, difficulty)
        if not path_url:
            return "#FFFFFF" # Default white glow if no thumbnail

        # path_url is like "file:///C:/..." or just path string depending on how it's constructed
        # QImage needs a local file path
        local_path = QUrl(path_url).toLocalFile()
        if not local_path:
            local_path = path_url # Try direct path if not a URL
            
        if not os.path.exists(local_path):
            return "#FFFFFF"
            
        try:
            image = QImage(local_path)
            if image.isNull():
                return "#FFFFFF"
                
            # Scale to 1x1 to get average color
            pixel = image.scaled(1, 1).pixel(0, 0)
            color = QColor(pixel)
            
            # Boost Color: Ensure high brightness and decent saturation
            # 1. Convert to HSV
            h, s, v, a = color.getHsv()
            
            # 2. Boost Value (Brightness) to ensure visibility on dark background
            # Target range: 200-255
            v = max(v, 220)
            
            # 3. Boost Saturation if it's not completely grayscale
            # If it's too desaturated, it might look washed out white, so give it some color if possible
            # But if the image is truly B&W, forcing saturation might look weird.
            # Let's just ensure it's not too dark.
            # If saturation is very low (< 20), treating it as grayscale -> make it white/bright gray
            if s > 20: 
                s = max(s, 180) # Boost saturation for colored images
            else:
                s = 0 # Keep it grayscale (but bright due to V boost)
            
            color.setHsv(h, s, v)
            
            return color.name()
            
        except Exception:
            return "#FFFFFF"

    @pyqtSlot()
    def refreshStats(self):
        # Calculate total stats
        count, seconds = play_stats_total()
        self._total_count = count
        
        hours = seconds // 3600
        minutes = (seconds % 3600) // 60
        self._total_time_str = f"{hours}h {minutes}m"
        
        # Calculate per-difficulty stats
        # Order: PST(0), PRS(1), FTR(2), ETR(4), BYD(3)
        diff_info = [
            (0, 'PST', '#00A0E9'),
            (1, 'PRS', '#50C050'),
            (2, 'FTR', '#A060FF'),
            (4, 'ETR', '#808080'),
            (3, 'BYD', '#E04040'),
        ]
        
        stats = []
        for code, name, color in diff_info:
            diff_count, diff_seconds = play_stats_difficulty(code)
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


# Difficulty display order: PST(0) -> PRS(1) -> FTR(2) -> ETR(4) -> BYD(3)
DIFFICULTY_ORDER = [0, 1, 2, 4, 3]
DIFFICULTY_NAMES = {0: 'PST', 1: 'PRS', 2: 'FTR', 3: 'BYD', 4: 'ETR'}
DIFFICULTY_COLORS = {0: '#00A0E9', 1: '#50C050', 2: '#A060FF', 3: '#E04040', 4: '#808080'}

# Score rank grades in order (for Score Range filter)
# '-' = no score, then grades up to PM
SCORE_RANKS = ['-', 'D', 'C', 'B', 'A', 'AA', 'EX', 'EX+', '99.5%', '99.8%', 'PM']


class StatisticsHandler(QObject):
    dataChanged = pyqtSignal()
    selectedItemChanged = pyqtSignal()
    
    def __init__(self):
        super().__init__()
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
        self._filter_contain_slowspeed = "contain"
        self._filter_score_min_rank = 0  # Index in SCORE_RANKS (0 = '-')
        self._filter_score_max_rank = len(SCORE_RANKS) - 1  # Index in SCORE_RANKS (last = 'PM')
        self._filter_clear_types = [0, 1, 2, 3, 4, 5]  # All clear types
        
        # Raw data caches
        self._songs_data = {}
        self._scores_data = {}
        self._play_counts = {}
        self._this_year_play_counts = {}
        
        # Processed list
        self._list_model = []
        self._selected_item = None
        
        # Selection state for mode sync
        self._selected_song_id = None  # arcaea_id of selected song
        self._selected_difficulty = 2  # Default to FTR (0=PST,1=PRS,2=FTR,3=BYD,4=ETR)
        
        # Level/BP boundary data (calculated from DB)
        self._available_levels = []  # Sorted list of unique level strings
        self._available_bps = []     # Sorted list of unique BP values
        self._level_boundaries = {}  # {"9": {"min": 9.0, "max": 9.6}, ...}
        
        # Ensure lists are never None
        self._available_levels = []
        self._available_bps = []
        
        self._load_data()
    
    def _load_data(self):
        """Load all data from databases and normalize keys."""
        # Load raw data
        raw_songs = get_all_songs_with_charts()
        raw_scores = get_best_scores_per_chart()
        raw_play_counts = get_play_counts()
        raw_this_year_play_counts = get_this_year_play_counts()
        
        # Normalize songs data (ensure diff keys are int)
        self._songs_data = {}
        for sid, sdata in raw_songs.items():
            normalized_charts = {}
            for diff, cdata in sdata.get('charts', {}).items():
                try:
                    normalized_charts[int(diff)] = cdata
                except:
                    normalized_charts[diff] = cdata
            sdata['charts'] = normalized_charts
            self._songs_data[sid] = sdata
            
        # Normalize scores data
        self._scores_data = {}
        for (aid, diff), scdata in raw_scores.items():
            try:
                self._scores_data[(aid, int(diff))] = scdata
            except:
                self._scores_data[(aid, diff)] = scdata
                
        # Normalize play counts
        self._play_counts = {}
        for (aid, diff), count in raw_play_counts.items():
            try:
                self._play_counts[(aid, int(diff))] = count
            except:
                self._play_counts[(aid, diff)] = count
        
        # Normalize this year play counts
        self._this_year_play_counts = {}
        for (aid, diff), count in raw_this_year_play_counts.items():
            try:
                self._this_year_play_counts[(aid, int(diff))] = count
            except:
                self._this_year_play_counts[(aid, diff)] = count
        
        # Calculate Level/BP boundaries
        self._calculate_level_bp_boundaries()
        
        # Select first item when data is loaded (app startup)
        self._pending_selection_mode = 'first'
        self._rebuild_list()
    
    def _calculate_level_bp_boundaries(self):
        """Calculate unique levels, BPs, and level->BP boundary mapping from DB data."""
        # Outliers to exclude from boundary calculation
        OUTLIER_CHARTS = [
            ('dropdead', 2),            # dropdead FTR
            ('internetyamero', 2),      # INTERNET YAMERO FTR (arcaea_id may differ)
        ]
        
        level_bp_map = {}  # level_str -> list of BP values
        all_bps = set()
        all_levels = set()
        
        for _, sdata in self._songs_data.items():
            title_lower = sdata.get('title', '').lower().replace(' ', '')
            for diff, cdata in sdata.get('charts', {}).items():
                # Check if this is an outlier
                is_outlier = False
                for (outlier_name, outlier_diff) in OUTLIER_CHARTS:
                    if outlier_name in title_lower and diff == outlier_diff:
                        is_outlier = True
                        break
                
                level_str = cdata.get('level', '')
                bp = cdata.get('bp', 0)
                
                if level_str:
                    all_levels.add(level_str)
                    
                # Only add BP to sets if NOT an outlier
                if bp and bp > 0 and not is_outlier:
                    all_bps.add(bp)
                    
                    if level_str:
                        if level_str not in level_bp_map:
                            level_bp_map[level_str] = []
                        level_bp_map[level_str].append(bp)
        
        # Sort levels: 1, 2, ... 9, 9+, 10, 10+, 11, 11+, 12
        def level_sort_key(lvl):
            try:
                base = int(lvl.replace('+', ''))
                is_plus = '+' in lvl
                return base + (0.5 if is_plus else 0)
            except ValueError:
                return 99
        
        self._available_levels = sorted(list(all_levels), key=level_sort_key)
        self._available_bps = sorted(list(all_bps))
        
        # Calculate min/max BP for each level
        self._level_boundaries = {}
        for level_str, bp_list in level_bp_map.items():
            if bp_list:
                self._level_boundaries[level_str] = {
                    'min': min(bp_list),
                    'max': max(bp_list)
                }
    
    
    def _matches_filter(self, chart_data, score_data, difficulty):
        """Check if a chart matches the current filters."""
        # Difficulty filter
        if difficulty not in self._filter_difficulties:
            return False
        
        # Level/BP range filter
        if self._filter_bp_mode:
            bp = chart_data.get('bp', 0)
            if bp < self._filter_bp_min or bp > self._filter_bp_max:
                return False
        else:
            level_str = chart_data.get('level', '0')
            # Use _available_levels for proper ordering comparison
            if level_str in self._available_levels:
                level_idx = self._available_levels.index(level_str)
                min_idx = self._available_levels.index(self._filter_level_min_str) if self._filter_level_min_str in self._available_levels else 0
                max_idx = self._available_levels.index(self._filter_level_max_str) if self._filter_level_max_str in self._available_levels else len(self._available_levels) - 1
                if level_idx < min_idx or level_idx > max_idx:
                    return False
        
        # Chart flags filter
        for flag_name, flag_value in [
            ('ignore_chart', self._filter_ignore_chart),
            ('skill_issues', self._filter_skill_issues),
            ('contain_slowspeed', self._filter_contain_slowspeed)
        ]:
            chart_flag = chart_data.get(flag_name, False)
            if flag_value == "only" and not chart_flag:
                return False
            elif flag_value == "contain":
                pass  # Include regardless
            elif flag_value == "off" and chart_flag:
                return False
        
        # Clear type filter
        if score_data:
            clear_type = score_data.get('best_clear_type', 0)
            if clear_type not in self._filter_clear_types:
                return False
        
        # Score rank filter
        score = score_data.get('score', 0) if score_data else 0
        time_played = score_data.get('time_played', 0) if score_data else 0
        has_score = time_played > 0
        rank_idx = self._get_score_rank_index(score, has_score)
        if rank_idx < self._filter_score_min_rank or rank_idx > self._filter_score_max_rank:
            return False
        
        return True
    
    def _get_score_rank_index(self, score, has_score=None):
        """Convert a score to its rank index in SCORE_RANKS.
        
        Args:
            score: The score value
            has_score: If True, score=0 means 'D' grade (Track Lost). If None, falls back to score > 0 check.
        """
        # Determine if this is an actual play record
        is_played = has_score if has_score is not None else (score > 0)
        
        if not is_played:
            return 0  # '-' (no score/never played)
        elif score < 8600000:
            return 1  # 'D'
        elif score < 8900000:
            return 2  # 'C'
        elif score < 9200000:
            return 3  # 'B'
        elif score < 9500000:
            return 4  # 'A'
        elif score < 9800000:
            return 5  # 'AA'
        elif score < 9900000:
            return 6  # 'EX'
        elif score < 9950000:
            return 7  # 'EX+'
        elif score < 9980000:
            return 8  # '99.5%'
        elif score < 10000000:
            return 9  # '99.8%'
        else:
            return 10  # 'PM'
    
    def _get_filtered_song_play_count(self, arcaea_id, song_data):
        """Calculate total play count for FILTERED difficulties of a song.
        
        This sums play counts only for difficulties that pass the current filter,
        providing song-mode-style aggregation while respecting filter settings.
        Used for display in the detailed view header.
        """
        total = 0
        for diff, chart_data in song_data.get('charts', {}).items():
            score_data = self._scores_data.get((arcaea_id, diff), {})
            if self._matches_filter(chart_data, score_data, diff):
                total += self._play_counts.get((arcaea_id, diff), 0)
        return total
    
    def _build_chart_item(self, arcaea_id, song_data, difficulty, chart_data):
        """Build a chart item for the list model."""
        score_data = self._scores_data.get((arcaea_id, difficulty), {})
        play_count = self._play_counts.get((arcaea_id, difficulty), 0)
        this_year_play_count = self._this_year_play_counts.get((arcaea_id, difficulty), 0)
        
        score = score_data.get('score', 0)
        time_played = score_data.get('time_played', 0)
        # hasScore: True if there's actual play data (time_played > 0 means a record exists)
        has_score = time_played > 0
        rank = calculate_rank(score) if has_score else ""
        
        return {
            'arcaeaId': arcaea_id,
            'title': song_data['title'],
            'artist': song_data['artist'],
            'length': song_data['length'],
            'bpm': song_data['bpm'],
            'difficulty': difficulty,
            'difficultyName': DIFFICULTY_NAMES.get(difficulty, ''),
            'difficultyColor': DIFFICULTY_COLORS.get(difficulty, '#888'),
            'level': chart_data.get('level', ''),
            'bp': chart_data.get('bp', 0),
            's_bp': chart_data.get('s_bp', 0),
            'perceived_bp': chart_data.get('perceived_bp', 0),
            'noteCount': chart_data.get('note_count', 0),
            'bestScore': score,
            'hasScore': has_score,
            'rank': rank,
            'pure': score_data.get('perfect', 0),
            'shinyPure': score_data.get('shiny_perfect', 0),
            'far': score_data.get('near', 0),
            'lost': score_data.get('miss', 0),
            'bestClearType': score_data.get('best_clear_type', 0),
            'timePlayed': time_played,
            'lastPlayedDate': self._format_full_datetime(time_played),
            'scoreBelowMax': score_data.get('score_below_max', 0),
            'totalPlayCount': play_count,
            'thisYearPlayCount': this_year_play_count,
            'songTotalPlayCount': self._get_filtered_song_play_count(arcaea_id, song_data),
            'displayValue': '',  # Will be set based on sort mode
        }
    
    def _format_full_datetime(self, timestamp):
        """Format timestamp to YYYY-MM-DD HH:MM."""
        if not timestamp or timestamp <= 0:
            return "-"
        
        try:
            timestamp = float(timestamp)
            # If timestamp is in milliseconds (13+ digits), convert to seconds
            if timestamp > 100000000000: 
                timestamp = timestamp / 1000.0
            
            dt = datetime.fromtimestamp(timestamp)
            return dt.strftime("%Y-%m-%d %H:%M")
        except (OSError, ValueError, OverflowError):
            return "-"
    
    def _build_all_difficulty_details(self, arcaea_id, song_data):
        """Build details for ALL difficulties of a song, with isFiltered flag.
        
        Used for detailed view to show all difficulties regardless of filter.
        """
        all_details = []
        
        for diff in DIFFICULTY_ORDER:
            chart_data = song_data.get('charts', {}).get(diff)
            if not chart_data:
                continue
            
            score_data = self._scores_data.get((arcaea_id, diff), {})
            
            # Check if this chart is filtered out
            is_filtered = not self._matches_filter(chart_data, score_data, diff)
            
            # Build the chart item
            chart_item = self._build_chart_item(arcaea_id, song_data, diff, chart_data)
            chart_item['isFiltered'] = is_filtered
            
            all_details.append(chart_item)
        
        return all_details
    

    def _build_song_item(self, arcaea_id, song_data, filtered_difficulties):
        """Build a song item aggregating filtered difficulties."""
        # Find best values among filtered difficulties
        best_level = ""
        best_bp = 0
        best_s_bp = 0
        best_perceived_bp = 0
        best_score = 0
        best_rank = ""
        total_play_count = 0
        recent_time_played = 0
        best_score_below_max = 0
        best_max_pure = 0
        best_max_shiny = 0
        best_max_far = 0
        best_max_lost = 0
        total_this_year_play_count = 0
        
        # Track which difficulty has the best value for each sort criteria
        best_diff_for_score = -1
        best_diff_for_max = -1
        best_diff_for_recent = -1
        best_diff_for_level = -1
        best_diff_for_s_bp = -1
        best_diff_for_perceived_bp = -1
        
        # Track highest difficulty for thumbnail (priority: BYD(3) > ETR(4) > FTR(2) > PRS(1) > PST(0))
        thumbnail_difficulty = -1
        THUMBNAIL_PRIORITY = {3: 0, 4: 1, 2: 2, 1: 3, 0: 4}  # Lower value = higher priority
        
        diff_details = []
        
        for diff in DIFFICULTY_ORDER:
            if diff not in filtered_difficulties:
                continue
            
            chart_data = song_data['charts'].get(diff, {})
            if not chart_data:
                continue
            
            chart_item = self._build_chart_item(arcaea_id, song_data, diff, chart_data)
            diff_details.append(chart_item)
            
            # Track highest difficulty for thumbnail
            if thumbnail_difficulty == -1 or THUMBNAIL_PRIORITY.get(diff, 99) < THUMBNAIL_PRIORITY.get(thumbnail_difficulty, 99):
                thumbnail_difficulty = diff
            
            # Aggregate values and track best difficulty
            if chart_data.get('bp', 0) > best_bp:
                best_bp = chart_data.get('bp', 0)
                best_level = chart_data.get('level', '')
                best_diff_for_level = diff
            if chart_data.get('s_bp', 0) > best_s_bp:
                best_s_bp = chart_data.get('s_bp', 0)
                best_diff_for_s_bp = diff
            if chart_data.get('perceived_bp', 0) > best_perceived_bp:
                best_perceived_bp = chart_data.get('perceived_bp', 0)
                best_diff_for_perceived_bp = diff
            
            if chart_item['bestScore'] > best_score:
                best_score = chart_item['bestScore']
                best_rank = chart_item['rank']
                best_diff_for_score = diff
            
            total_play_count += chart_item['totalPlayCount']
            total_this_year_play_count += chart_item['thisYearPlayCount']
            
            if chart_item['timePlayed'] > recent_time_played:
                recent_time_played = chart_item['timePlayed']
                best_diff_for_recent = diff
            
            # MAX sort: find chart with smallest (perfect + near + miss - shiny_perfect) value
            # Only consider charts that have been played (hasScore is True)
            if chart_item['hasScore']:
                chart_max_val = chart_item['pure'] + chart_item['far'] + chart_item['lost'] - chart_item['shinyPure']
                current_best_max_val = best_max_pure + best_max_far + best_max_lost - best_max_shiny
                # Use smallest value, or if first played chart
                if best_diff_for_max == -1 or chart_max_val < current_best_max_val or (chart_max_val == current_best_max_val and chart_item['scoreBelowMax'] < best_score_below_max):
                    best_score_below_max = chart_item['scoreBelowMax']
                    best_diff_for_max = diff
                    best_max_pure = chart_item['pure']
                    best_max_shiny = chart_item['shinyPure']
                    best_max_far = chart_item['far']
                    best_max_lost = chart_item['lost']
        
        # hasScore for song: True if any chart has been played
        has_score = recent_time_played > 0
        
        return {
            'arcaeaId': arcaea_id,
            'title': song_data['title'],
            'artist': song_data['artist'],
            'length': song_data['length'],
            'bpm': song_data['bpm'],
            'level': best_level,
            'bp': best_bp,
            's_bp': best_s_bp,
            'perceived_bp': best_perceived_bp,
            'bestScore': best_score,
            'hasScore': has_score,
            'rank': best_rank,
            'totalPlayCount': total_play_count,
            'thisYearPlayCount': total_this_year_play_count,
            'songTotalPlayCount': self._get_filtered_song_play_count(arcaea_id, song_data),
            'timePlayed': recent_time_played,
            'scoreBelowMax': best_score_below_max,
            'pure': best_max_pure,
            'shinyPure': best_max_shiny,
            'far': best_max_far,
            'lost': best_max_lost,
            'filteredDifficulties': diff_details,
            'allDifficulties': self._build_all_difficulty_details(arcaea_id, song_data),
            'displayValue': '',
            # Thumbnail: highest difficulty among filtered
            'thumbnailDifficulty': thumbnail_difficulty,
            # Best difficulty for each sort mode
            'bestDiffForScore': best_diff_for_score,
            'bestDiffForMax': best_diff_for_max,
            'bestDiffForRecent': best_diff_for_recent,
            'bestDiffForLevel': best_diff_for_level,
            'bestDiffForSBp': best_diff_for_s_bp,
            'bestDiffForPerceivedBp': best_diff_for_perceived_bp,
        }
    
    def _get_sort_key(self, item):
        """Get the sort key based on current sort mode."""
        mode = self._sort_mode
        if mode == "title":
            return item.get('title', '').lower()
        elif mode == "score":
            # Sort by (hasScore, bestScore) so played records (even score=0) > unplayed records
            has_score = item.get('hasScore', False)
            return (1 if has_score else 0, item.get('bestScore', 0))
        elif mode == "max":
            # Unplayed records: treat as highest MAX value (positive infinity)
            if not item.get('hasScore', False):
                return (float('inf'), float('inf'))
            # Primary: perfect + near + miss - shiny_perfect
            # For MAX records (primary=0), higher BP is better
            # For non-MAX records, lower scoreBelowMax is better
            pure = item.get('pure', 0)
            shiny = item.get('shinyPure', 0)
            far = item.get('far', 0)
            lost = item.get('lost', 0)
            primary_key = pure + far + lost - shiny
            if primary_key == 0:
                return (primary_key, -item.get('bp', 0))
            else:
                return (primary_key, item.get('scoreBelowMax', 0))
        elif mode == "total_play_count":
            return item.get('totalPlayCount', 0)
        elif mode == "this_year_play_count":
            return item.get('thisYearPlayCount', 0)
        elif mode == "recent_played":
            return item.get('timePlayed', 0)
        elif mode == "level":
            return item.get('bp', 0)
        elif mode == "s_bp":
            return item.get('s_bp', 0)
        elif mode == "perceived_bp":
            return item.get('perceived_bp', 0)
        elif mode == "length":
            return item.get('length', 0)
        return item.get('title', '').lower()
    
    def _format_display_value(self, item):
        """Format the display value based on sort mode and display mode."""
        mode = self._sort_mode
        is_chart_mode = self._display_mode == "chart"
        
        if mode == "title":
            if is_chart_mode:
                diff_name = item.get('difficultyName', '')
                level = item.get('level', '')
                return f"{diff_name} {level}"
            return ""
        elif mode == "score":
            score = item.get('bestScore', 0)
            rank = item.get('rank', '')
            has_score = item.get('hasScore', False)
            if has_score:
                return f"{score:,}"
            return "-"
        elif mode == "max":
            # Display value: perfect + near + miss - shiny_perfect
            # Show "-" for unplayed records
            if not item.get('hasScore', False):
                return "-"
            pure = item.get('pure', 0)
            shiny = item.get('shinyPure', 0)
            far = item.get('far', 0)
            lost = item.get('lost', 0)
            display_val = pure + far + lost - shiny
            return f"MAX-{display_val}" if display_val > 0 else "MAX"
        elif mode == "total_play_count":
            count = item.get('totalPlayCount', 0)
            if count <= 0:
                return "Never played"
            return f"{count} plays"
        elif mode == "this_year_play_count":
            count = item.get('thisYearPlayCount', 0)
            if count <= 0:
                return "Never played"
            return f"{count} plays"
        elif mode == "recent_played":
            ts = item.get('timePlayed', 0)
            if not ts or ts <= 0:
                return "Never played"
            return self._format_time(ts)
        elif mode == "level":
            if is_chart_mode:
                level = item.get('level', '')
                bp = item.get('bp', 0)
                return f"{level} ({bp:.1f})"
            return item.get('level', '')
        elif mode == "s_bp":
            s_bp = item.get('s_bp', 0)
            if s_bp <= 0:
                return "?"
            return f"{s_bp:.2f}"
        elif mode == "perceived_bp":
            perceived_bp = item.get('perceived_bp', 0)
            if perceived_bp <= 0:
                return "?"
            return f"{perceived_bp:.2f}"
        elif mode == "length":
            length = item.get('length', 0)
            if length <= 0:
                return "?"
            return f"{length // 60}:{length % 60:02d}"
        return ""
    
    def _format_time(self, timestamp):
        """Format timestamp to readable string."""
        if not timestamp or timestamp <= 0:
            return ""
        
        try:
            timestamp = float(timestamp)
            # If timestamp is in milliseconds (13+ digits), convert to seconds
            if timestamp > 100000000000: 
                timestamp = timestamp / 1000.0
            
            dt = datetime.fromtimestamp(timestamp)
        except (OSError, ValueError, OverflowError):
            return ""
        
        now = datetime.now()
        
        # Compare dates to allow correct Today/Yesterday logic regardless of time difference
        now_date = now.date()
        play_date = dt.date()
        days_diff = (now_date - play_date).days
        
        if days_diff == 0:
            return f"Today {dt.strftime('%H:%M')}"
        elif days_diff == 1:
            return "Yesterday"
        elif days_diff < 7:
            return f"{days_diff} days ago"
        else:
            if dt.year == now.year:
                return dt.strftime("%b %d")
            return dt.strftime("%Y-%m-%d")
    
    def _get_best_diff_for_sort(self, item):
        """Get the best difficulty for the current sort mode from a song item.
        
        Returns the difficulty number (0-4) if the sort mode highlights a specific difficulty,
        or -1 if the sort mode doesn't highlight any (e.g., title, total_play_count, length).
        """
        if self._sort_mode == "score":
            return item.get('bestDiffForScore', -1)
        elif self._sort_mode == "max":
            return item.get('bestDiffForMax', -1)
        elif self._sort_mode == "recent_played":
            return item.get('bestDiffForRecent', -1)
        elif self._sort_mode == "level":
            return item.get('bestDiffForLevel', -1)
        elif self._sort_mode == "s_bp":
            return item.get('bestDiffForSBp', -1)
        elif self._sort_mode == "perceived_bp":
            return item.get('bestDiffForPerceivedBp', -1)
        return -1
    
    def _rebuild_list(self):
        """Rebuild the list model based on current mode and filters."""
        items = []
        
        for song_id, song_data in self._songs_data.items():
            # Search filter
            if self._search_text:
                search_lower = self._search_text.lower()
                if (search_lower not in song_data['title'].lower() and 
                    search_lower not in song_data['artist'].lower()):
                    continue
            
            # Get arcaea_id for score lookup
            arcaea_id = song_data.get('arcaea_id')
            
            # Get filtered difficulties for this song
            filtered_diffs = []
            for diff, chart_data in song_data.get('charts', {}).items():
                score_data = self._scores_data.get((arcaea_id, diff), {})
                if self._matches_filter(chart_data, score_data, diff):
                    filtered_diffs.append(diff)
            
            if not filtered_diffs:
                continue
            
            if self._display_mode == "chart":
                # Add each chart as separate item
                for diff in DIFFICULTY_ORDER:
                    if diff not in filtered_diffs:
                        continue
                    chart_data = song_data['charts'].get(diff, {})
                    if chart_data:
                        item = self._build_chart_item(arcaea_id, song_data, diff, chart_data)
                        # Add allDifficulties for detailed view (shows all song difficulties regardless of mode)
                        item['allDifficulties'] = self._build_all_difficulty_details(arcaea_id, song_data)
                        items.append(item)
            else:
                # Add song with aggregated data
                item = self._build_song_item(arcaea_id, song_data, filtered_diffs)
                items.append(item)
        
        # Sort
        reverse = not self._sort_ascending
        if self._sort_mode == "title":
            reverse = not self._sort_ascending  # Title: ascending = A->Z
        else:
            reverse = not self._sort_ascending
        
        items.sort(key=self._get_sort_key, reverse=reverse)
        
        # Set display values
        for item in items:
            item['displayValue'] = self._format_display_value(item)
        
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
                    best_diff = self._get_best_diff_for_sort(self._selected_item)
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
        return self._available_levels
    
    @pyqtProperty('QVariantList', notify=dataChanged)
    def availableBPs(self):
        return self._available_bps
    
    @pyqtProperty('QVariant', notify=dataChanged)
    def levelBoundaries(self):
        return self._level_boundaries
    
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
        elif filter_type == 'contain_slowspeed':
            self._filter_contain_slowspeed = str(value) if value else 'off'
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
                best_diff = self._get_best_diff_for_sort(self._selected_item)
                
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
        self._load_data()



class ProfileHandler(QObject):
    """프로필 데이터를 account_connections.json에서 읽어 QML에 제공하는 핸들러."""
    profileChanged = pyqtSignal()

    def __init__(self):
        super().__init__()
        self._connections_file = os.path.join(config['general']['cache_path'], 'account_connections.json')

    def _load_connections(self):
        if not os.path.exists(self._connections_file):
            return {}
        try:
            with open(self._connections_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception:
            return {}

    @pyqtSlot(result='QVariant')
    def getProfile(self):
        """프로필 데이터를 dict로 반환. 미연결 시 connected=False."""
        connections = self._load_connections()
        ao_info = connections.get('arcaea_online', {})
        if not ao_info.get('connected', False):
            return {'connected': False}
        return {
            'connected': True,
            'name': ao_info.get('name', ''),
            'user_code': ao_info.get('user_code', ''),
            'rating': ao_info.get('rating'),
            'join_date': ao_info.get('join_date'),
        }

    @pyqtSlot()
    def refreshProfile(self):
        """프로필 데이터를 다시 읽고 QML에 알림."""
        self.profileChanged.emit()


class SettingsHandler(QObject):
    settingsChanged = pyqtSignal()
    cachePathChanged = pyqtSignal()
    analyzeModeChanged = pyqtSignal(bool, arguments=['enabled'])
    # Migration signals
    cacheMigrationStarting = pyqtSignal()  # Emitted before migration - QML should release file handles
    cacheMigrationFinished = pyqtSignal(str, arguments=['error'])  # Emitted after migration with error message (empty if success)
    # Account connection signals
    arcaeaOnlineConnectionChanged = pyqtSignal()
    googleSheetConnectionChanged = pyqtSignal()
    # Sheet binding signals
    sheetBindingChanged = pyqtSignal()
    sendDataStatusChanged = pyqtSignal()
    sheetVersionsChanged = pyqtSignal()
    # Song database update signals
    songDatabaseUpdateStarting = pyqtSignal()
    songDatabaseUpdateFinished = pyqtSignal(bool, str, arguments=['success', 'message'])

    def __init__(self):
        super().__init__()
        self._pending_migration_path = None  # Stores the new path during migration
        self._analyzer = None
        self._connections_file = os.path.join(config['general']['cache_path'], 'account_connections.json')
        self._is_arcaea_connecting = False
        self._is_binding_sheet = False
        self._is_sending_data = False
        self._is_updating_song_db = False
        self._google_cancellation_context = None
        self._bind_cancellation_context = None
        self._send_cancellation_context = None
        self._arcaea_login_instance = None
        self._sheet_versions = {'sheet_ver': '?', 'arcaea_ver': '?'}

    def set_analyzer(self, analyzer):
        """Connect to ArcaeaOnline instance for play count mode control."""
        self._analyzer = analyzer

    # --- General Settings ---
    @pyqtSlot(result=str)
    def getCachePath(self):
        return config['general']['cache_path']

    def _get_absolute_cache_path(self, path: str) -> str:
        """Convert cache path to absolute path, resolving relative paths from script directory."""
        if path.startswith('./') or path.startswith('.\\'):
            base_dir = os.path.dirname(os.path.abspath(__file__))
            return os.path.normpath(os.path.join(base_dir, path))
        return os.path.abspath(path)

    @pyqtSlot(str)
    def prepareCacheMigration(self, new_path):
        """
        Step 1 of cache migration: Store target path and signal QML to release file handles.
        After this, QML should show loading modal and release all file handles,
        then call executeCacheMigration().
        """
        # Allow use of file:// prefix for drag-and-drop support or dialog returns
        if new_path.startswith("file:///"):
            new_path = new_path[8:]
        
        old_path = config['general']['cache_path']
        old_abs = self._get_absolute_cache_path(old_path)
        new_abs = os.path.abspath(new_path)
        
        # Same path check
        if os.path.normpath(old_abs) == os.path.normpath(new_abs):
            return
        
        self._pending_migration_path = new_path
        print(f"[SettingsHandler] Preparing cache migration to '{new_path}'...")
        self.cacheMigrationStarting.emit()

    @pyqtSlot()
    def executeCacheMigration(self):
        """
        Step 2 of cache migration: Actually copy files and update config.
        Should be called by QML after it has released all file handles.
        """
        import shutil
        
        if not self._pending_migration_path:
            self.cacheMigrationFinished.emit("No pending migration")
            return
        
        new_path = self._pending_migration_path
        self._pending_migration_path = None
        
        old_path = config['general']['cache_path']
        old_abs = self._get_absolute_cache_path(old_path)
        new_abs = os.path.abspath(new_path)
        
        # Data files/folders to migrate
        data_items = ['ui', 'thumbnails', 'user_scores.db', 'login.dat', 'songs.db', 'token.json', 'client_secret.json']
        
        copied_items = []
        try:
            # Ensure new directory exists
            os.makedirs(new_abs, exist_ok=True)
            
            # Phase 1: Copy all items to new location
            for item in data_items:
                src = os.path.join(old_abs, item)
                dst = os.path.join(new_abs, item)
                
                if not os.path.exists(src):
                    continue
                
                if os.path.isdir(src):
                    if os.path.exists(dst):
                        shutil.rmtree(dst)
                    shutil.copytree(src, dst)
                else:
                    shutil.copy2(src, dst)
                
                copied_items.append(item)
            
            # Phase 2: Verify copied items exist
            for item in copied_items:
                dst = os.path.join(new_abs, item)
                if not os.path.exists(dst):
                    raise IOError(f"Verification failed: {item} not found in new location")
            
            # Phase 3: Update config (this is the point of no return)
            config['general']['cache_path'] = new_path
            self.cachePathChanged.emit()
            self.settingsChanged.emit()
            
            # Phase 4: Delete old items (failure here is acceptable - data is safe in new location)
            for item in copied_items:
                src = os.path.join(old_abs, item)
                try:
                    if os.path.isdir(src):
                        shutil.rmtree(src, ignore_errors=True)
                    else:
                        os.remove(src)
                except Exception as e:
                    print(f"[SettingsHandler] Warning: Could not delete old {item}: {e}")
            
            print(f"[SettingsHandler] Cache moved from '{old_abs}' to '{new_abs}'")
            self.cacheMigrationFinished.emit("")  # Success
            
        except Exception as e:
            # Rollback: remove any partially copied items from new location
            print(f"[SettingsHandler] Copy failed, attempting rollback...")
            for item in copied_items:
                dst = os.path.join(new_abs, item)
                try:
                    if os.path.isdir(dst):
                        shutil.rmtree(dst, ignore_errors=True)
                    elif os.path.exists(dst):
                        os.remove(dst)
                except Exception:
                    pass
            
            error_msg = f"Failed to move cache: {e}"
            print(f"[SettingsHandler] {error_msg}")
            self.cacheMigrationFinished.emit(error_msg)

    @pyqtSlot()
    def cancelCacheMigration(self):
        """Cancel a pending migration."""
        self._pending_migration_path = None
        self.cacheMigrationFinished.emit("Migration cancelled")

    @pyqtSlot()
    def openCacheFolder(self):
        """Open the cache folder in the system file explorer."""
        import subprocess
        cache_path = self._get_absolute_cache_path(config['general']['cache_path'])
        
        if os.path.isdir(cache_path):
            # Windows
            subprocess.Popen(['explorer', cache_path])

    @pyqtSlot(result=bool)
    def getAnalyzeModeEnabled(self):
        return config['general']['analyze_mode']

    @pyqtSlot(bool)
    def setAnalyzeModeEnabled(self, enabled):
        if self._analyzer:
            self._analyzer.set_play_count_mode(enabled)
        else:
            config['general']['analyze_mode'] = enabled
        self.analyzeModeChanged.emit(enabled)
        self.settingsChanged.emit()
        
    @pyqtSlot(result=bool)
    def isUpdatingSongDatabase(self):
        return self._is_updating_song_db

    @pyqtSlot()
    def updateSongDatabase(self):
        if self._is_updating_song_db:
            return

        self._is_updating_song_db = True
        self.songDatabaseUpdateStarting.emit()

        def worker():
            import traceback
            try:
                rebuild_songs_db()
                self.songDatabaseUpdateFinished.emit(True, "Song database updated successfully.")
            except Exception as e:
                print(f"[SettingsHandler] Song database update failed: {e}")
                traceback.print_exc()
                self.songDatabaseUpdateFinished.emit(False, str(e))
            finally:
                self._is_updating_song_db = False

        threading.Thread(target=worker, daemon=True).start()

    # --- Sheet Management ---
    @pyqtSlot(result=str)
    def getBoundSheetInfo(self):
        """Get bound sheet info as JSON string."""
        connections = self._load_connections()
        gs_info = connections.get('google_sheet', {})
        bound_id = gs_info.get('bound_sheet_id', '')
        bound_name = gs_info.get('bound_sheet_name', '')
        if not bound_id:
            return json.dumps({})
        return json.dumps({
            'sheet_id': bound_id,
            'sheet_name': bound_name
        })

    @pyqtSlot()
    def fetchSheetVersions(self):
        """Fetch sheet version info in a background thread."""
        self._sheet_versions = {'sheet_ver': '?', 'arcaea_ver': '?'}
        self.sheetVersionsChanged.emit()

        def task():
            print("[SettingsHandler] Fetching sheet versions...")
            # We don't have a specific cancellation context for this yet, pass None
            versions = get_sheet_version_info()
            self._sheet_versions = versions
            print(f"[SettingsHandler] Sheet versions fetched: {versions}")
            self.sheetVersionsChanged.emit()
            
        thread = threading.Thread(target=task, daemon=True)
        thread.start()

    @pyqtSlot(result=str)
    def getSheetVersions(self):
        """Get cached sheet versions as JSON string."""
        return json.dumps(self._sheet_versions)


    @pyqtSlot(result=bool)
    def isBindingSheet(self):
        return self._is_binding_sheet

    @pyqtSlot(result=bool)
    def isSendingData(self):
        return self._is_sending_data

    @pyqtSlot()
    def bindSheet(self):
        """Open Google Picker to select and bind a spreadsheet."""
        if self._is_binding_sheet:
            return

        self._is_binding_sheet = True
        self.sheetBindingChanged.emit()

        def _bind():
            try:
                from web_consultantsheet import run_google_picker, CancellationContext
                self._bind_cancellation_context = CancellationContext()
                
                result = run_google_picker(self._bind_cancellation_context)
                self._bind_cancellation_context = None

                if result:
                    sheet_id, sheet_name = result
                    # Save to connections
                    connections = self._load_connections()
                    gs_info = connections.get('google_sheet', {})
                    gs_info['bound_sheet_id'] = sheet_id
                    gs_info['bound_sheet_name'] = sheet_name
                    connections['google_sheet'] = gs_info
                    self._save_connections(connections)
                    
                    print(f"[SettingsHandler] Sheet bound: {sheet_name} ({sheet_id})")
                else:
                    print("[SettingsHandler] Sheet binding cancelled")
            except Exception as e:
                print(f"[SettingsHandler] Error binding sheet: {e}")
                import traceback
                traceback.print_exc()
            finally:
                self._is_binding_sheet = False
                self._bind_cancellation_context = None
                self.sheetBindingChanged.emit()

        thread = threading.Thread(target=_bind, daemon=True)
        thread.start()

    @pyqtSlot()
    def cancelBindSheet(self):
        """Cancel ongoing sheet binding."""
        # Reflect cancellation in UI immediately to avoid stale "binding" state.
        if self._is_binding_sheet:
            self._is_binding_sheet = False
            self.sheetBindingChanged.emit()

        if self._bind_cancellation_context:
            self._bind_cancellation_context.cancel()
            self._bind_cancellation_context = None

    @pyqtSlot()
    def openBoundSheet(self):
        """Open bound sheet in the default web browser."""
        connections = self._load_connections()
        gs_info = connections.get('google_sheet', {})
        bound_id = gs_info.get('bound_sheet_id', '')
        if bound_id:
            import webbrowser
            url = f"https://docs.google.com/spreadsheets/d/{bound_id}"
            webbrowser.open(url)

    @pyqtSlot()
    def sendData(self):
        """Send score data to the bound Google Sheet."""
        if self._is_sending_data:
            return

        self._is_sending_data = True
        self.sendDataStatusChanged.emit()

        def _send():
            try:
                from web_consultantsheet import send_scores_to_sheet, CancellationContext
                self._send_cancellation_context = CancellationContext()
                
                connections = self._load_connections()
                gs_info = connections.get('google_sheet', {})
                sheet_id = gs_info.get('bound_sheet_id', '')
                
                if not sheet_id:
                    print("[SettingsHandler] No sheet bound for sending data")
                    return
                
                updated, total = send_scores_to_sheet(
                    sheet_id=sheet_id,
                    cancellation_context=self._send_cancellation_context
                )
                self._send_cancellation_context = None
                
                # Update last synced time
                config['sheet']['last_synced'] = str(time.time())
                print(f"[SettingsHandler] Send data complete: {updated}/{total} rows")
            except Exception as e:
                print(f"[SettingsHandler] Error sending data: {e}")
                import traceback
                traceback.print_exc()
            finally:
                self._is_sending_data = False
                self._send_cancellation_context = None
                self.sendDataStatusChanged.emit()

        thread = threading.Thread(target=_send, daemon=True)
        thread.start()


    @pyqtSlot(result=float)
    def getLastSyncedTime(self):
        """Get the last synced timestamp."""
        return config['sheet']['last_synced']

    # --- Profile Settings ---
    @pyqtSlot(result=bool)
    def getShowFriendCode(self):
        return config['profile']['show_friend_code']

    @pyqtSlot(bool)
    def setShowFriendCode(self, show):
        config['profile']['show_friend_code'] = str(show)
        self.settingsChanged.emit()

    @pyqtSlot(result=bool)
    def getShowPotential(self):
        return config['profile']['show_potential']

    @pyqtSlot(bool)
    def setShowPotential(self, show):
        config['profile']['show_potential'] = str(show)
        self.settingsChanged.emit()

    @pyqtSlot(result=str)
    def getProfileImage(self):
        return config['profile']['profile_image']

    @pyqtSlot(str)
    def setProfileImage(self, path):
        if path.startswith("file:///"):
            path = path[8:]
        config['profile']['profile_image'] = path
        self.settingsChanged.emit()

    @pyqtSlot(result=str)
    def getProfileDescription(self):
        return config['profile']['profile_description']

    @pyqtSlot(str)
    def setProfileDescription(self, text):
        config['profile']['profile_description'] = text
        self.settingsChanged.emit()

    @pyqtSlot(result=str)
    def getGroupingCriteria(self):
        return config['profile']['grouping_criteria']

    @pyqtSlot(str)
    def setGroupingCriteria(self, criteria):
        # 'song' or 'chart'
        config['profile']['grouping_criteria'] = criteria
        self.settingsChanged.emit()

    @pyqtSlot(result=str)
    def getDifficultyFilter(self):
        return config['profile']['difficulty_filter']

    @pyqtSlot(str)
    def setDifficultyFilter(self, filters):
        # 'all' or comma separated 'pst,prs'
        config['profile']['difficulty_filter'] = filters
        self.settingsChanged.emit()

    # --- Account Connections ---
    def _load_connections(self):
        """Load account connections from JSON file."""
        if not os.path.exists(self._connections_file):
            return {}
        try:
            with open(self._connections_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            print(f"[SettingsHandler] Error loading connections: {e}")
            return {}
    
    def _save_connections(self, connections):
        """Save account connections to JSON file."""
        try:
            with open(self._connections_file, 'w', encoding='utf-8') as f:
                json.dump(connections, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"[SettingsHandler] Error saving connections: {e}")
    
    @pyqtSlot(result=bool)
    def isArcaeaOnlineConnected(self):
        """Check if Arcaea Online is connected."""
        connections = self._load_connections()
        return connections.get('arcaea_online', {}).get('connected', False)

    @pyqtSlot(result=bool)
    def isArcaeaOnlineConnecting(self):
        return self._is_arcaea_connecting
    
    @pyqtSlot(result=bool)
    def isGoogleSheetConnected(self):
        """Check if Google Sheet is connected."""
        connections = self._load_connections()
        return connections.get('google_sheet', {}).get('connected', False)

    
    @pyqtSlot(result=str)
    def getArcaeaOnlineConnectionInfo(self):
        """Get Arcaea Online connection info as JSON string."""
        connections = self._load_connections()
        ao_info = connections.get('arcaea_online', {})
        if not ao_info.get('connected', False):
            return json.dumps({})
        
        return json.dumps({
            'connected_at': ao_info.get('connected_at', 0),
            'name': ao_info.get('name', ''),
            'user_id': ao_info.get('user_id', ''),
            'rating': ao_info.get('rating'),
            'join_date': ao_info.get('join_date'),
            'user_code': ao_info.get('user_code', '')
        })
    
    @pyqtSlot(result=str)
    def getGoogleSheetConnectionInfo(self):
        """Get Google Sheet connection info as JSON string."""
        connections = self._load_connections()
        gs_info = connections.get('google_sheet', {})
        if not gs_info.get('connected', False):
            return json.dumps({})
        
        return json.dumps({
            'connected_at': gs_info.get('connected_at', 0),
            'user_email': gs_info.get('user_email', '')
        })
    
    @pyqtSlot()
    def connectArcaeaOnline(self):
        """Connect to Arcaea Online."""
        if self._is_arcaea_connecting:
            return

        self._is_arcaea_connecting = True
        self.arcaeaOnlineConnectionChanged.emit()

        def _connect():
            try:
                # Create a temporary ArcaeaOnline instance for login
                temp_analyzer = ArcaeaOnline()
                temp_analyzer.log = lambda msg: print(f"[ArcaeaOnline] {msg}")
                
                lang = 'ko'
                url = f'https://arcaea.lowiro.com/{lang}/profile/scores?page=1'
                
                # Initialize browser and login
                from playwright.sync_api import sync_playwright
                from browser_utils import get_browser
                
                temp_analyzer.playwright = sync_playwright().start()
                temp_analyzer.browser = get_browser(temp_analyzer.playwright, headless=False)
                temp_analyzer.context = temp_analyzer.browser.new_context(
                    viewport={'width': 600, 'height': 1000}
                )
                temp_analyzer.page = temp_analyzer.context.new_page()
                
                self._arcaea_login_instance = temp_analyzer
                # Enable running status for polling loop in login()
                temp_analyzer.status.is_running = True
                
                # Setup listeners for close events
                temp_analyzer.setup_browser_listeners()

                # Perform login (this will save to account_connections.json)
                temp_analyzer.login(url)
                
                # Clean up
                temp_analyzer.stop()
                
            except Exception as e:
                print(f"[SettingsHandler] Error connecting Arcaea Online: {e}")
                import traceback
                traceback.print_exc()
            finally:
                self._is_arcaea_connecting = False
                self._arcaea_login_instance = None
                # Emit signal to update UI (on main thread)
                self.arcaeaOnlineConnectionChanged.emit()
        
        # Run in separate thread to avoid blocking UI
        thread = threading.Thread(target=_connect, daemon=True)
        thread.start()
    
    @pyqtSlot()
    def cancelArcaeaOnlineConnection(self):
        """Cancel the ongoing Arcaea Online connection process."""
        if self._arcaea_login_instance:
            print("[SettingsHandler] Cancelling Arcaea Online connection...")
            try:
                self._arcaea_login_instance.cancel()
            except Exception as e:
                print(f"[SettingsHandler] Error cancelling Arcaea instance: {e}")
            # The _connect thread will likely raise an exception or exit loop and finish

    
    @pyqtSlot()
    def disconnectArcaeaOnline(self):
        """Disconnect Arcaea Online."""
        try:
            connections = self._load_connections()
            if 'arcaea_online' in connections:
                del connections['arcaea_online']
                self._save_connections(connections)
            
            # Remove sensitive cookies from keyring
            try:
                keyring.delete_password('ArcaeaNap', 'sid')
            except:
                pass
            try:
                keyring.delete_password('ArcaeaNap', '__stripe_sid')
            except:
                pass
            try:
                keyring.delete_password('ArcaeaNap', '__stripe_mid')
            except:
                pass
            
            self.arcaeaOnlineConnectionChanged.emit()
        except Exception as e:
            print(f"[SettingsHandler] Error disconnecting Arcaea Online: {e}")
    
    @pyqtSlot()
    def connectGoogleSheet(self):
        """Connect to Google Sheet (fire-and-forget).
        
        Opens the OAuth browser page and immediately returns.
        If a previous session is in progress, it is cancelled first.
        """
        # Cancel any existing session before starting a new one
        if self._google_cancellation_context:
            print("[SettingsHandler] Cancelling previous Google Sheet session...")
            self._google_cancellation_context.cancel()
            self._google_cancellation_context = None

        def _connect():
            try:
                from web_consultantsheet import get_creds, CancellationContext
                
                ctx = CancellationContext()
                self._google_cancellation_context = ctx
                
                # Pass context to get_creds
                creds = get_creds(ctx)
                
                if ctx.is_cancelled():
                    print("[SettingsHandler] Google Sheet session was superseded.")
                    return
                
                self._google_cancellation_context = None # Clear context after done
                
                if creds and creds.valid:
                    # get_creds() already saves to account_connections.json
                    print("[SettingsHandler] Google Sheet connected successfully.")
                    self.googleSheetConnectionChanged.emit()
            except Exception as e:
                print(f"[SettingsHandler] Error connecting Google Sheet: {e}")
                import traceback
                traceback.print_exc()
        
        # Run in separate thread to avoid blocking UI
        thread = threading.Thread(target=_connect, daemon=True)
        thread.start()
    
    def _cancelGoogleSheetSession(self):
        """Cancel any ongoing Google Sheet OAuth session (internal use)."""
        if self._google_cancellation_context:
            self._google_cancellation_context.cancel()
            self._google_cancellation_context = None
            
    @pyqtSlot()
    def disconnectGoogleSheet(self):
        """Disconnect Google Sheet and clear bound sheet info."""
        # Cancel any ongoing OAuth session
        self._cancelGoogleSheetSession()
        
        try:
            connections = self._load_connections()
            if 'google_sheet' in connections:
                del connections['google_sheet']
                self._save_connections(connections)
            
            # Remove sensitive tokens from keyring
            try:
                keyring.delete_password('ArcaeaNap', 'google_token')
            except:
                pass
            try:
                keyring.delete_password('ArcaeaNap', 'google_refresh_token')
            except:
                pass
            
            self.googleSheetConnectionChanged.emit()
            self.sheetBindingChanged.emit()
        except Exception as e:
            print(f"[SettingsHandler] Error disconnecting Google Sheet: {e}")
    
    # Signals for connection changes (re-declared for PyQt6 metaclass resolution)
    arcaeaOnlineConnectionChanged = pyqtSignal()
    googleSheetConnectionChanged = pyqtSignal()
    sheetBindingChanged = pyqtSignal()
    sendDataStatusChanged = pyqtSignal()


def main():
    fmt = QSurfaceFormat()
    fmt.setSamples(8)  # MSAA 8x
    fmt.setRenderableType(QSurfaceFormat.RenderableType.OpenGL)
    QSurfaceFormat.setDefaultFormat(fmt)

    app = QGuiApplication(sys.argv)
    
    print("Arcaea Nap v0.1")

    print("UI loading...")
    engine = QQmlApplicationEngine()

    # Register handlers
    analysis_handler = AnalysisHandler()
    engine.rootContext().setContextProperty("analysisHandler", analysis_handler)
    
    startup_handler = StartupHandler()
    engine.rootContext().setContextProperty("startupHandler", startup_handler)

    stats_handler = StatsHandler()
    engine.rootContext().setContextProperty("statsHandler", stats_handler)

    statistics_handler = StatisticsHandler()
    engine.rootContext().setContextProperty("statisticsHandler", statistics_handler)

    profile_handler = ProfileHandler()
    engine.rootContext().setContextProperty("profileHandler", profile_handler)

    settings_handler = SettingsHandler()
    settings_handler.set_analyzer(analysis_handler.analyzer)
    analysis_handler.set_settings_handler(settings_handler)  # Enable connection status updates
    engine.rootContext().setContextProperty("settingsHandler", settings_handler)

    # Refresh profile when Arcaea Online connection changes
    settings_handler.arcaeaOnlineConnectionChanged.connect(profile_handler.refreshProfile)

    qml_filename = "main.qml"
    qml_filepath = os.path.join(config['general']['cache_path'], 'ui', qml_filename)
    
    engine.load(QUrl.fromLocalFile(qml_filepath))

    if not engine.rootObjects():
        sys.exit(-1)

    # Stop browser on app exit
    app.aboutToQuit.connect(analysis_handler.stopAnalysis)

    sys.exit(app.exec())

if __name__ == "__main__":
    main()