"""Startup 핸들러: 앱 시작 시 songs.db 존재 확인 및 초기 데이터 로드."""
import os
import threading
from PyQt6.QtCore import QObject, pyqtSlot, pyqtSignal
from repositories.song_repository import get_db_path
from utils.song_db_builder import rebuild_songs_db


class StartupHandler(QObject):
    loadingStarted = pyqtSignal()
    loadingFinished = pyqtSignal()
    errorOccurred = pyqtSignal(str)
    logAdded = pyqtSignal(str)
    songsDbMissing = pyqtSignal()  # 추가된 시그널

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

        print("songs.db missing. Waiting for user decision...")
        self.songsDbMissing.emit()  # 자동 생성 대신 시그널 발생

    @pyqtSlot()
    def startInitialLoad(self):
        """사용자가 DB 생성을 수락했을 때 수동으로 호출되는 슬롯"""
        print("Starting initial data load...")
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
