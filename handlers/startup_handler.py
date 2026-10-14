"""Startup 핸들러: 앱 시작 시 songs.db 존재 확인 및 초기 데이터 로드."""
import os
import threading
from PyQt6.QtCore import QObject, pyqtSlot, pyqtSignal, QCoreApplication
from repositories.song_repository import get_db_path
from utils.song_db_builder import rebuild_songs_db


class StartupHandler(QObject):
    loadingStarted = pyqtSignal()
    loadingFinished = pyqtSignal()
    errorOccurred = pyqtSignal(str)
    logAdded = pyqtSignal(str)
    songsDbMissing = pyqtSignal()  # 추가된 시그널
    appBecameIdle = pyqtSignal()  # 초기 렌더링 큐 소진 및 진정한 유휴 상태 도달 시그널

    def __init__(self):
        super().__init__()
        self.thread = None
        self._idle_detected = False
        self._target_window = None
        self._dispatcher_connected = False

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

    @pyqtSlot()
    @pyqtSlot(QObject)
    def start_idle_detection(self, window=None):
        """메인 윈도우 첫 프레임 스왑 후 QAbstractEventDispatcher가 유휴(aboutToBlock)로 전환되는 시점 1회 감지."""
        if self._idle_detected:
            return
        self._target_window = window
        if window is not None and hasattr(window, "frameSwapped"):
            try:
                window.frameSwapped.connect(self._on_window_frame_swapped)
                return
            except Exception:
                pass
        self._connect_about_to_block()

    def _on_window_frame_swapped(self):
        if self._target_window is not None:
            try:
                self._target_window.frameSwapped.disconnect(self._on_window_frame_swapped)
            except Exception:
                pass
        self._connect_about_to_block()

    def _connect_about_to_block(self):
        if self._idle_detected or self._dispatcher_connected:
            return
        dispatcher = QCoreApplication.eventDispatcher()
        if dispatcher is None:
            self._on_about_to_block()
            return
        self._dispatcher_connected = True
        dispatcher.aboutToBlock.connect(self._on_about_to_block)

    def _on_about_to_block(self):
        if self._idle_detected:
            return
        self._idle_detected = True
        dispatcher = QCoreApplication.eventDispatcher()
        if dispatcher is not None and self._dispatcher_connected:
            try:
                dispatcher.aboutToBlock.disconnect(self._on_about_to_block)
            except Exception:
                pass
            self._dispatcher_connected = False
        self.appBecameIdle.emit()
