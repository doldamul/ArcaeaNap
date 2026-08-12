"""QML-facing controller for the macOS Cocoa full-size content bridge."""

from __future__ import annotations

import ctypes
import sys
from enum import IntEnum
from pathlib import Path
from typing import Protocol

from PyQt6.QtCore import QObject, pyqtProperty, pyqtSignal, pyqtSlot

from utils.app_fonts import get_app_root


PROJECT_ROOT = Path(__file__).resolve().parents[1]
MACOS_BRIDGE_FILENAME: str = "libmacos_window_bridge.dylib"


class MacWindowTheme(IntEnum):
    LIGHT = 1
    DARK = 2


class _MacBridge(Protocol):
    def attach(self, view_handle: int, toolbar_style: int = 0) -> bool: ...
    def metrics(self) -> tuple[float, float, float, float]: ...
    def set_theme(self, theme: int) -> bool: ...
    def last_error(self) -> str: ...
    def shutdown(self) -> None: ...


class _Metrics(ctypes.Structure):
    _fields_ = [
        ("top", ctypes.c_double),
        ("left", ctypes.c_double),
        ("right", ctypes.c_double),
        ("bottom", ctypes.c_double),
    ]


class CtypesMacWindowBridge:
    """ctypes adapter for native/macos_window_bridge.mm."""

    def __init__(self, path: Path):
        self._dll = ctypes.CDLL(str(path))
        self._dll.bwm_attach.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self._dll.bwm_attach.restype = ctypes.c_void_p
        self._dll.bwm_get_metrics.argtypes = [ctypes.c_void_p, ctypes.POINTER(_Metrics)]
        self._dll.bwm_get_metrics.restype = ctypes.c_int
        self._dll.bwm_set_theme.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self._dll.bwm_set_theme.restype = ctypes.c_int
        self._dll.bwm_last_attach_error.argtypes = []
        self._dll.bwm_last_attach_error.restype = ctypes.c_char_p
        self._dll.bwm_last_error.argtypes = [ctypes.c_void_p]
        self._dll.bwm_last_error.restype = ctypes.c_char_p
        self._dll.bwm_shutdown.argtypes = [ctypes.c_void_p]
        self._dll.bwm_shutdown.restype = None
        self._ctx = None

    def attach(self, view_handle: int, toolbar_style: int = 0) -> bool:
        self._ctx = self._dll.bwm_attach(ctypes.c_void_p(view_handle), ctypes.c_int(toolbar_style))
        return bool(self._ctx)

    def metrics(self) -> tuple[float, float, float, float]:
        if not self._ctx:
            raise RuntimeError("Not attached to a window")
        metrics = _Metrics()
        if self._dll.bwm_get_metrics(ctypes.c_void_p(self._ctx), ctypes.byref(metrics)) != 0:
            raise RuntimeError(self.last_error())
        return metrics.top, metrics.left, metrics.right, metrics.bottom

    def set_theme(self, theme: int) -> bool:
        if not self._ctx:
            return False
        return self._dll.bwm_set_theme(ctypes.c_void_p(self._ctx), theme) == 0

    def last_error(self) -> str:
        if not self._ctx:
            raw = self._dll.bwm_last_attach_error()
        else:
            raw = self._dll.bwm_last_error(ctypes.c_void_p(self._ctx))
        return raw.decode("utf-8", errors="replace") if raw else "macOS Cocoa window bridge failed."

    def shutdown(self) -> None:
        if self._ctx:
            self._dll.bwm_shutdown(ctypes.c_void_p(self._ctx))
            self._ctx = None


class UnavailableMacBridge:
    def __init__(self, message: str):
        self._message = message

    def attach(self, view_handle: int, toolbar_style: int = 0) -> bool:
        return False

    def metrics(self) -> tuple[float, float, float, float]:
        return 0.0, 0.0, 0.0, 0.0

    def set_theme(self, theme: int) -> bool:
        return False

    def last_error(self) -> str:
        return self._message

    def shutdown(self) -> None:
        pass


def mac_bridge_candidates(
    *, app_root: Path, project_root: Path, frozen: bool
) -> tuple[Path, ...]:
    filename = MACOS_BRIDGE_FILENAME
    if frozen:
        return (
            app_root / "lib" / "native" / filename,
            app_root / "native" / filename,
        )
    stage = project_root / "build" / "native-stage" / "macos-arm64"
    return (
        app_root / "native" / filename,
        stage / "lib" / "native" / filename,
        stage / "native" / filename,
    )


def default_mac_bridge() -> _MacBridge:
    if sys.platform != "darwin":
        return UnavailableMacBridge("The Cocoa window bridge is only available on macOS.")
    candidates = mac_bridge_candidates(
        app_root=Path(get_app_root()),
        project_root=PROJECT_ROOT,
        frozen=bool(getattr(sys, "frozen", False)),
    )
    path = next((candidate for candidate in candidates if candidate.is_file()), None)
    if path is None:
        checked_paths = ", ".join(str(candidate) for candidate in candidates)
        return UnavailableMacBridge(
            f"macOS Cocoa window bridge not found; checked: {checked_paths}"
        )
    try:
        return CtypesMacWindowBridge(path)
    except OSError as error:
        return UnavailableMacBridge(f"Could not load macOS Cocoa window bridge: {error}")


class MacWindowController(QObject):
    availableChanged = pyqtSignal()
    errorMessageChanged = pyqtSignal()
    metricsChanged = pyqtSignal()

    def __init__(self, *, bridge: _MacBridge | None = None, parent: QObject | None = None):
        super().__init__(parent)
        self._bridge = bridge or default_mac_bridge()
        self._available = False
        self._error_message = ""
        self._safe_area_top = 0.0
        self._safe_area_left = 0.0
        self._safe_area_right = 0.0
        self._safe_area_bottom = 0.0

    @pyqtProperty(bool, notify=availableChanged)
    def available(self) -> bool:
        return self._available

    @pyqtProperty(str, notify=errorMessageChanged)
    def errorMessage(self) -> str:
        return self._error_message

    @pyqtProperty(float, notify=metricsChanged)
    def safeAreaTop(self) -> float:
        return self._safe_area_top

    @pyqtProperty(float, notify=metricsChanged)
    def safeAreaLeft(self) -> float:
        return self._safe_area_left

    @pyqtProperty(float, notify=metricsChanged)
    def safeAreaRight(self) -> float:
        return self._safe_area_right

    @pyqtProperty(float, notify=metricsChanged)
    def safeAreaBottom(self) -> float:
        return self._safe_area_bottom

    def attach(self, view_handle: int, toolbar_style: int = 0) -> bool:
        try:
            attached = self._bridge.attach(view_handle, toolbar_style)
            if not attached:
                self._set_error(self._bridge.last_error())
                return False
            self._refresh_metrics()
        except Exception as error:
            self._set_error(str(error))
            return False
        self._available = True
        self.availableChanged.emit()
        return True

    def set_dark_mode(self, is_dark: bool) -> bool:
        if not self._available:
            return False
        theme = MacWindowTheme.DARK if is_dark else MacWindowTheme.LIGHT
        try:
            applied = self._bridge.set_theme(int(theme))
            if not applied:
                self._set_error(self._bridge.last_error())
                return False
        except Exception as error:
            self._set_error(str(error))
            return False
        return True

    @pyqtSlot(bool)
    def setDarkMode(self, is_dark: bool) -> None:
        self.set_dark_mode(is_dark)

    @pyqtSlot()
    def refreshMetrics(self) -> None:
        if not self._available:
            return
        try:
            self._refresh_metrics()
        except Exception as error:
            self._set_error(str(error))

    def _refresh_metrics(self) -> None:
        top, left, right, bottom = self._bridge.metrics()
        values = (float(top), float(left), float(right), float(bottom))
        current = (
            self._safe_area_top,
            self._safe_area_left,
            self._safe_area_right,
            self._safe_area_bottom,
        )
        if values == current:
            return
        (
            self._safe_area_top,
            self._safe_area_left,
            self._safe_area_right,
            self._safe_area_bottom,
        ) = values
        self.metricsChanged.emit()

    def _set_error(self, message: str) -> None:
        if message != self._error_message:
            self._error_message = message
            self.errorMessageChanged.emit()

    def __del__(self):
        if hasattr(self, '_bridge') and self._bridge:
            self._bridge.shutdown()
