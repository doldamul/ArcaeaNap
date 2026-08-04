"""Runtime bridge between the persisted theme preference and Qt color schemes."""
import logging

from PyQt6.QtCore import QObject, QTimer, Qt, pyqtProperty, pyqtSignal, pyqtSlot
from PyQt6.QtGui import QGuiApplication

from utils.configuration import config


logger = logging.getLogger(__name__)


class ThemeHandler(QObject):
    """Expose the requested theme mode and its effective dark-mode value to QML."""

    themeModeChanged = pyqtSignal(str)
    isDarkModeChanged = pyqtSignal(bool)

    _ALLOWED_MODES = {"system", "light", "dark"}

    def __init__(self, style_hints=None, config_store=None, schedule_refresh=None):
        super().__init__()
        self._style_hints = (
            QGuiApplication.styleHints() if style_hints is None else style_hints
        )
        self._config_store = config if config_store is None else config_store
        self._schedule_refresh = (
            self._schedule_next_event_loop
            if schedule_refresh is None
            else schedule_refresh
        )
        self._theme_mode = self._load_theme_mode()
        self._is_dark_mode = False

        # This is deliberately the only connection: a manual choice must not be
        # turned back into a system value by Qt's subsequent platform signal.
        self._style_hints.colorSchemeChanged.connect(self._on_color_scheme_changed)
        self._apply_runtime_mode(schedule_system_refresh=True)

    @pyqtProperty(str, notify=themeModeChanged)
    def themeMode(self):
        return self._theme_mode

    @pyqtProperty(bool, notify=isDarkModeChanged)
    def isDarkMode(self):
        return self._is_dark_mode

    @pyqtSlot(str)
    def setThemeMode(self, mode):
        normalized = self._normalize_mode(mode)
        if normalized is None or normalized == self._theme_mode:
            return

        try:
            self._config_store["general"]["theme_mode"] = normalized
        except Exception:
            logger.exception("Failed to persist theme mode %r", normalized)
            return

        self._theme_mode = normalized
        self.themeModeChanged.emit(normalized)
        self._apply_runtime_mode(schedule_system_refresh=True)

    def _load_theme_mode(self):
        try:
            stored_mode = self._config_store["general"]["theme_mode"]
        except Exception:
            logger.exception("Failed to read persisted theme mode; using system")
            return "system"

        return self._normalize_mode(stored_mode) or "system"

    @classmethod
    def _normalize_mode(cls, mode):
        if not isinstance(mode, str):
            return None
        normalized = mode.strip().lower()
        return normalized if normalized in cls._ALLOWED_MODES else None

    def _apply_runtime_mode(self, *, schedule_system_refresh):
        if self._theme_mode == "system":
            self._apply_system_mode(schedule_system_refresh=schedule_system_refresh)
            return

        requested_dark = self._theme_mode == "dark"
        qt_scheme = Qt.ColorScheme.Dark if requested_dark else Qt.ColorScheme.Light
        try:
            self._style_hints.setColorScheme(qt_scheme)
        except Exception:
            logger.exception("Failed to force Qt color scheme %r", qt_scheme)
        self._set_effective_dark_mode(requested_dark)

    def _apply_system_mode(self, *, schedule_system_refresh):
        try:
            self._style_hints.unsetColorScheme()
        except Exception:
            logger.exception("Failed to release Qt color scheme override")
            self._set_effective_dark_mode(False)
            return

        self._refresh_system_color_scheme()
        if schedule_system_refresh:
            self._schedule_refresh(self._refresh_scheduled_system_color_scheme)

    def _refresh_scheduled_system_color_scheme(self):
        if self._theme_mode == "system":
            self._refresh_system_color_scheme()

    def _refresh_system_color_scheme(self):
        try:
            scheme = self._style_hints.colorScheme()
        except Exception:
            logger.exception("Failed to query Qt color scheme; using light mode")
            self._set_effective_dark_mode(False)
            return

        self._set_effective_dark_mode(scheme == Qt.ColorScheme.Dark)

    def _on_color_scheme_changed(self, *_):
        if self._theme_mode == "system":
            self._refresh_system_color_scheme()

    def _set_effective_dark_mode(self, is_dark):
        if self._is_dark_mode == is_dark:
            return
        self._is_dark_mode = is_dark
        self.isDarkModeChanged.emit(is_dark)

    @staticmethod
    def _schedule_next_event_loop(callback):
        QTimer.singleShot(0, callback)
