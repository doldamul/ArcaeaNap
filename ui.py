from configuration import config
import sys
import os
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQml import QQmlApplicationEngine
from PyQt6.QtCore import QUrl

def main():
    app = QGuiApplication(sys.argv)
    engine = QQmlApplicationEngine()

    qml_filename = "main.qml"
    qml_filepath = os.path.join(config['general']['cache_path'], qml_filename)
    
    engine.load(QUrl.fromLocalFile(qml_filepath))

    if not engine.rootObjects():
        sys.exit(-1)

    sys.exit(app.exec())

if __name__ == "__main__":
    main()