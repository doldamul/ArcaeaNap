from configuration import config
import sys
import os
import threading
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQml import QQmlApplicationEngine
from PyQt6.QtCore import QUrl, QObject, pyqtSlot
from web_arcaeaonline import open_arcaea_online
from web_consultantsheet import open_sheet
from web_wiki import open_wiki

class AnalysisHandler(QObject):
    def __init__(self):
        super().__init__()

    @pyqtSlot()
    def startAnalysis(self):
        print("Starting analysis thread...")
        thread = threading.Thread(target=open_arcaea_online, daemon=True)
        thread.start()

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