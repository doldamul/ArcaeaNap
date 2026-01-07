from configuration import config
import sys
import os
import threading
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQml import QQmlApplicationEngine
from PyQt6.QtCore import QUrl, QObject, pyqtSlot, pyqtSignal
from web_arcaeaonline import ArcaeaOnline
from web_consultantsheet import open_sheet
from web_wiki import open_wiki
from db_utils import get_db_path, calculate_user_stats, get_top_10_most_played

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

    def __init__(self):
        super().__init__()
        self.analyzer = None
        self.thread = None

    @pyqtSlot()
    def startAnalysis(self):
        if self.thread and self.thread.is_alive():
            print("Analysis already running.")
            return

        print("Starting analysis thread...")
        self.analyzer = ArcaeaOnline()
        self.analyzer.set_log_callback(self.emit_log)
        
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

class StatsHandler(QObject):
    statsChanged = pyqtSignal()
    
    def __init__(self):
        super().__init__()
        self._total_count = 0
        self._total_time_str = "0h 0m"
        self._thumbnails_dir = os.path.join(config['general']['cache_path'], 'thumbnails')
        self.refreshStats()

    @pyqtSlot(result=int)
    def getTotalPlayCount(self):
        return self._total_count

    @pyqtSlot(result=str)
    def getTotalPlayTime(self):
        return self._total_time_str

    @pyqtSlot(result=list)
    def getMostPlayed(self):
        return get_top_10_most_played()

    @pyqtSlot(str, result=str)
    def getThumbnailPath(self, arcaea_id: str) -> str:
        """
        주어진 arcaea_id에 해당하는 썸네일 경로를 반환
        FTR > BYD > ETR > PRS > PST 순서로 검색
        """
        if not arcaea_id:
            return ""
        
        # 난이도 우선순위: FTR, BYD, ETR, PRS, PST
        difficulty_priority = ['ftr', 'byd', 'etr', 'prs', 'pst']
        
        for diff in difficulty_priority:
            filename = f"{arcaea_id}_{diff}.jpg"
            filepath = os.path.join(self._thumbnails_dir, filename)
            if os.path.exists(filepath):
                # QML에서 사용할 수 있도록 file:// URL 반환
                return QUrl.fromLocalFile(filepath).toString()
        
        return ""

    @pyqtSlot()
    def refreshStats(self):
        count, seconds = calculate_user_stats()
        self._total_count = count
        
        hours = seconds // 3600
        minutes = (seconds % 3600) // 60
        self._total_time_str = f"{hours}h {minutes}m"
        
        self.statsChanged.emit()

def main():
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

    qml_filename = "main.qml"
    qml_filepath = os.path.join(config['general']['cache_path'], 'ui', qml_filename)
    
    engine.load(QUrl.fromLocalFile(qml_filepath))

    if not engine.rootObjects():
        sys.exit(-1)

    sys.exit(app.exec())

if __name__ == "__main__":
    main()