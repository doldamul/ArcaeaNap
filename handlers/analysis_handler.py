"""Analysis 핸들러: ArcaeaOnline 분석기와 QML 간 브릿지."""
import os
import random
import sqlite3
import threading
from datetime import datetime
from configuration import config
from PyQt6.QtCore import QObject, pyqtSlot, pyqtSignal, QVariant, QUrl
from web_arcaeaonline import ArcaeaOnline
from repositories.score_repository import PinRepository


def _format_timestamp(ts) -> str:
    """Unix 타임스탬프(ms) → 'YYYY-MM-DD HH:MM' 포맷. 유효하지 않으면 '-'."""
    if not ts or ts <= 0:
        return "-"
    try:
        dt = datetime.fromtimestamp(ts / 1000)
        return dt.strftime("%Y-%m-%d %H:%M")
    except (OSError, ValueError, OverflowError):
        return "-"


class AnalysisHandler(QObject):
    logAdded = pyqtSignal(str, arguments=['message'])
    dataUpdated = pyqtSignal()  # Emitted when user_scores.db or thumbnails are updated
    pinUpdated = pyqtSignal()   # Emitted when pin data is updated
    statusChanged = pyqtSignal(str, arguments=['status'])  # Emitted when analysis status changes
    progressChanged = pyqtSignal()  # Emitted when progress data (checked_page/total_page) changes
    sessionReset = pyqtSignal(str, arguments=['message'])  # Emitted when session is auto-reset

    def __init__(self):
        super().__init__()
        self.analyzer = ArcaeaOnline()  # Create on init to load pin_updates from DB
        self.thread = None
        self._settings_handler = None  # Reference to SettingsHandler
        self._pin_repo = PinRepository()

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
        result = {}

        try:
            db_path = os.path.join(config['general']['cache_path'], 'user_scores.db')
            if not os.path.exists(db_path):
                return {}

            with sqlite3.connect(db_path) as conn:
                cursor = conn.cursor()
                pin_details = self._pin_repo.get_pin_details_with_scores(cursor)

                for difficulty, data in pin_details.items():
                    data['formatted_updated_at'] = _format_timestamp(data.get('updated_at'))
                    data['formatted_time_played'] = _format_timestamp(data.get('time_played'))
                    result[str(difficulty)] = data

        except Exception as e:
            print(f"Error in getPinDates: {e}")
            # Fallback to simple pin_updates if DB query fails
            if self.analyzer and self.analyzer.status.pin_updates:
                for k, v in self.analyzer.status.pin_updates.items():
                    result[str(k)] = {
                        'updated_at': v,
                        'time_played': 0,
                        'arcaea_id': '',
                        'formatted_updated_at': _format_timestamp(v),
                        'formatted_time_played': '-',
                    }

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
