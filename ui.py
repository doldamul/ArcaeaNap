from configuration import config
import sys
import os
import threading
import time
import random
from datetime import datetime
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQml import QQmlApplicationEngine
from PyQt6.QtCore import QUrl, QObject, pyqtSlot, pyqtSignal, pyqtProperty, QVariant
from PyQt6.QtGui import QImage, QColor, QSurfaceFormat
from web_arcaeaonline import ArcaeaOnline
from web_consultantsheet import open_sheet
from web_wiki import open_wiki
from db_utils import (
    get_db_path, play_stats_total, play_stats_difficulty, get_top_10_most_played,
    get_all_songs_with_charts, get_best_scores_per_chart, get_play_counts, 
    get_this_year_play_counts, calculate_rank
)

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
            print("Loading data from Consultant Sheet...")
            open_sheet()
            print("Consultant Sheet load successful.")
            
            print("Loading data from Wiki...")
            open_wiki()
            print("Wiki load successful.")
            
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

    def __init__(self):
        super().__init__()
        self.analyzer = ArcaeaOnline()  # Create on init to load pin_updates from DB
        self.thread = None

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

    @pyqtSlot(result=str)
    def getStatus(self):
        """Returns current analysis status: 'closed', 'login', 'ready', 'analyzing'"""
        if self.analyzer:
            return self.analyzer.status.status
        return 'closed'

    @pyqtSlot(result='QVariant')
    def getPinDates(self):
        """
        Returns last updated dates for each difficulty from AnalysisStatus.
        Returns: 
            dict: { difficulty_code(str): timestamp(int) }
        """
        if self.analyzer and self.analyzer.status.pin_updates:
            return {str(k): v for k, v in self.analyzer.status.pin_updates.items()}
        return {}

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
        self._thumbnails_dir = os.path.join(config['general']['cache_path'], 'thumbnails')
        self.refreshStats()

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
                return f"{score:,} ({rank})"
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