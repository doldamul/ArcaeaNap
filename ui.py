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

def main():
    app = QGuiApplication(sys.argv)
    
    print("Initializing Data... (Consultant Sheet & Wiki)")
    try:
        open_sheet()
    except Exception as e:
        print(f"Failed to load Consultant Sheet data: {e}")

    try:
        open_wiki()
    except Exception as e:
        print(f"Failed to load Wiki data: {e}")

    engine = QQmlApplicationEngine()

    # Register handler
    analysis_handler = AnalysisHandler()
    engine.rootContext().setContextProperty("analysisHandler", analysis_handler)

    qml_filename = "main.qml"
    qml_filepath = os.path.join(config['general']['cache_path'], 'ui', qml_filename)
    
    engine.load(QUrl.fromLocalFile(qml_filepath))

    if not engine.rootObjects():
        sys.exit(-1)

    sys.exit(app.exec())

if __name__ == "__main__":
    main()