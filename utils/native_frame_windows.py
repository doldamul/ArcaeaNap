"""QML-facing controller for the Windows AppWindowTitleBar bridge."""

from __future__ import annotations

import ctypes
import math
import sys
import weakref
from dataclasses import dataclass
from enum import IntEnum
from pathlib import Path
from typing import Any, Protocol, Sequence

from PyQt6.QtCore import QEvent, QObject, QTimer, pyqtProperty, pyqtSignal, pyqtSlot

from utils.app_fonts import get_app_root


WINDOWS_10_1809_BUILD = 17763


class TitleBarTheme(IntEnum):
    LIGHT = 1
    DARK = 2


class _Bridge(Protocol):
    def prepare(self) -> bool: ...
    def initialize(self, hwnd: int) -> bool: ...
    def set_theme(self, theme: int) -> bool: ...
    def set_drag_rectangles(self, rects: list[tuple[int, int, int, int]]) -> bool: ...
    def metrics(self) -> tuple[int, int, int]: ...
    def diagnostics(self) -> WindowDiagnostics: ...
    def last_error(self) -> str: ...
    def shutdown(self) -> None: ...


def is_supported_windows_build(build: int) -> bool:
    return build >= WINDOWS_10_1809_BUILD


class _Metrics(ctypes.Structure):
    _fields_ = [("left", ctypes.c_int), ("right", ctypes.c_int), ("height", ctypes.c_int)]


@dataclass(frozen=True)
class WindowDiagnostics:
    window_left: int
    window_top: int
    window_width: int
    window_height: int
    client_origin_x: int
    client_origin_y: int
    client_width: int
    client_height: int
    style: int
    ex_style: int
    extends_content: bool
    left_inset: int
    right_inset: int
    title_bar_height: int


class _Diagnostics(ctypes.Structure):
    _fields_ = [
        ("window_left", ctypes.c_int),
        ("window_top", ctypes.c_int),
        ("window_width", ctypes.c_int),
        ("window_height", ctypes.c_int),
        ("client_origin_x", ctypes.c_int),
        ("client_origin_y", ctypes.c_int),
        ("client_width", ctypes.c_int),
        ("client_height", ctypes.c_int),
        ("style", ctypes.c_uint64),
        ("ex_style", ctypes.c_uint64),
        ("extends_content", ctypes.c_int),
        ("left_inset", ctypes.c_int),
        ("right_inset", ctypes.c_int),
        ("title_bar_height", ctypes.c_int),
    ]


class _Rect(ctypes.Structure):
    _fields_ = [
        ("x", ctypes.c_int),
        ("y", ctypes.c_int),
        ("width", ctypes.c_int),
        ("height", ctypes.c_int),
    ]


class CtypesTitleBarBridge:
    """Small ctypes adapter for the C++/WinRT DLL's C ABI."""

    def __init__(self, path: Path):
        self._dll = ctypes.WinDLL(str(path))
        self._dll.awtb_prepare.argtypes = []
        self._dll.awtb_prepare.restype = ctypes.c_int
        self._dll.awtb_initialize.argtypes = [ctypes.c_void_p]
        self._dll.awtb_initialize.restype = ctypes.c_void_p
        self._dll.awtb_set_theme.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self._dll.awtb_set_theme.restype = ctypes.c_int
        self._dll.awtb_set_drag_rectangles.argtypes = [ctypes.c_void_p, ctypes.POINTER(_Rect), ctypes.c_size_t]
        self._dll.awtb_set_drag_rectangles.restype = ctypes.c_int
        self._dll.awtb_get_metrics.argtypes = [ctypes.c_void_p, ctypes.POINTER(_Metrics)]
        self._dll.awtb_get_metrics.restype = ctypes.c_int
        self._dll.awtb_get_diagnostics.argtypes = [ctypes.c_void_p, ctypes.POINTER(_Diagnostics)]
        self._dll.awtb_get_diagnostics.restype = ctypes.c_int
        self._dll.awtb_last_attach_error.argtypes = []
        self._dll.awtb_last_attach_error.restype = ctypes.c_wchar_p
        self._dll.awtb_last_error.argtypes = [ctypes.c_void_p]
        self._dll.awtb_last_error.restype = ctypes.c_wchar_p
        self._dll.awtb_shutdown.argtypes = [ctypes.c_void_p]
        self._dll.awtb_shutdown.restype = None
        self._ctx = None

    def prepare(self) -> bool:
        return self._dll.awtb_prepare() == 0

    def initialize(self, hwnd: int) -> bool:
        self._ctx = self._dll.awtb_initialize(ctypes.c_void_p(hwnd))
        return bool(self._ctx)

    def set_theme(self, theme: int) -> bool:
        if not self._ctx:
            return False
        return self._dll.awtb_set_theme(ctypes.c_void_p(self._ctx), theme) == 0

    def set_drag_rectangles(self, rects: list[tuple[int, int, int, int]]) -> bool:
        if not self._ctx:
            return False
        array = (_Rect * len(rects))(*(_Rect(*rect) for rect in rects)) if rects else None
        return self._dll.awtb_set_drag_rectangles(ctypes.c_void_p(self._ctx), array, len(rects)) == 0

    def metrics(self) -> tuple[int, int, int]:
        if not self._ctx:
            raise RuntimeError("Not initialized")
        metrics = _Metrics()
        if self._dll.awtb_get_metrics(ctypes.c_void_p(self._ctx), ctypes.byref(metrics)) != 0:
            raise RuntimeError(self.last_error())
        return metrics.left, metrics.right, metrics.height

    def diagnostics(self) -> WindowDiagnostics:
        if not self._ctx:
            raise RuntimeError("Not initialized")
        diagnostics = _Diagnostics()
        if self._dll.awtb_get_diagnostics(ctypes.c_void_p(self._ctx), ctypes.byref(diagnostics)) != 0:
            raise RuntimeError(self.last_error())
        return WindowDiagnostics(
            window_left=diagnostics.window_left,
            window_top=diagnostics.window_top,
            window_width=diagnostics.window_width,
            window_height=diagnostics.window_height,
            client_origin_x=diagnostics.client_origin_x,
            client_origin_y=diagnostics.client_origin_y,
            client_width=diagnostics.client_width,
            client_height=diagnostics.client_height,
            style=diagnostics.style,
            ex_style=diagnostics.ex_style,
            extends_content=bool(diagnostics.extends_content),
            left_inset=diagnostics.left_inset,
            right_inset=diagnostics.right_inset,
            title_bar_height=diagnostics.title_bar_height,
        )

    def last_error(self) -> str:
        if not self._ctx:
            return self._dll.awtb_last_attach_error() or "Windows AppWindowTitleBar bridge failed."
        return self._dll.awtb_last_error(ctypes.c_void_p(self._ctx)) or "Windows AppWindowTitleBar bridge failed."

    def shutdown(self) -> None:
        if self._ctx:
            self._dll.awtb_shutdown(ctypes.c_void_p(self._ctx))
            self._ctx = None


class UnavailableBridge:
    def __init__(self, message: str):
        self._message = message

    def prepare(self) -> bool:
        return False

    def initialize(self, hwnd: int) -> bool:
        return False

    def set_theme(self, theme: int) -> bool:
        return False

    def set_drag_rectangles(self, rects: list[tuple[int, int, int, int]]) -> bool:
        return False

    def metrics(self) -> tuple[int, int, int]:
        return 0, 0, 0

    def diagnostics(self) -> WindowDiagnostics:
        raise RuntimeError(self._message)

    def last_error(self) -> str:
        return self._message

    def shutdown(self) -> None:
        pass


def windows_bridge_candidates(*, app_root: Path, frozen: bool) -> tuple[Path, ...]:
    filename = "appwindow_titlebar_bridge.dll"
    if frozen:
        return (
            app_root / "lib" / "native" / filename,
            app_root / "native" / filename,
        )
    return (app_root / "native" / filename,)


def default_bridge() -> _Bridge:
    if sys.platform != "win32":
        return UnavailableBridge("Windows AppWindowTitleBar is only available on Windows.")
    candidates = windows_bridge_candidates(
        app_root=Path(get_app_root()),
        frozen=bool(getattr(sys, "frozen", False)),
    )
    path = next((candidate for candidate in candidates if candidate.is_file()), None)
    if path is None:
        checked_paths = ", ".join(str(candidate) for candidate in candidates)
        return UnavailableBridge(
            f"Windows AppWindowTitleBar bridge not found; checked: {checked_paths}"
        )
    try:
        return CtypesTitleBarBridge(path)
    except OSError as error:
        return UnavailableBridge(f"Could not load Windows AppWindowTitleBar bridge: {error}")


class NativeTitleBarController(QObject):
    availableChanged = pyqtSignal()
    errorMessageChanged = pyqtSignal()
    metricsChanged = pyqtSignal()
    diagnosticTextChanged = pyqtSignal()

    def __init__(self, *, bridge: _Bridge | None = None, os_build: int = WINDOWS_10_1809_BUILD, parent: QObject | None = None):
        super().__init__(parent)
        self._bridge = bridge or default_bridge()
        self._os_build = os_build
        self._available = False
        self._prepared = False
        self._error_message = ""
        self._left_inset = 0.0
        self._right_inset = 0.0
        self._height = 0.0
        self._diagnostic_text = "Native diagnostics are unavailable until attachment."
        self._window: QObject | None = None
        self._window_destroyed_handler: object | None = None
        self._window_dpr = 1.0
        self._raw_metrics = (0, 0, 0)
        self._sync_pending = False
        self._sync_generation = 0
        self._pending_sync_reason = "attach"
        self._sync_retry_count = 0
        self._attaching = False
        self._last_sync_reason = "unattached"
        self._last_sync_status = "unattached"
        self._bridge_initialized = False

    @pyqtProperty(bool, notify=availableChanged)
    def available(self) -> bool:
        return self._available

    @pyqtProperty(str, notify=errorMessageChanged)
    def errorMessage(self) -> str:
        return self._error_message

    @pyqtProperty(float, notify=metricsChanged)
    def leftInset(self) -> float:
        return self._left_inset

    @pyqtProperty(float, notify=metricsChanged)
    def rightInset(self) -> float:
        return self._right_inset

    @pyqtProperty(float, notify=metricsChanged)
    def height(self) -> float:
        return self._height

    @pyqtProperty(float, notify=metricsChanged)
    def devicePixelRatio(self) -> float:
        return self._window_dpr

    @pyqtProperty(str, notify=diagnosticTextChanged)
    def diagnosticText(self) -> str:
        return self._diagnostic_text

    def attach(self, hwnd: int, toolbar_style: int = 0) -> bool:
        return self._attach_native(hwnd, toolbar_style, None)

    def attach_window(self, hwnd: int, qml_window: QObject, toolbar_style: int = 0) -> bool:
        return self._attach_native(hwnd, toolbar_style, qml_window)

    def _attach_native(self, hwnd: int, toolbar_style: int, qml_window: QObject | None) -> bool:
        self._reset_attachment()
        if not self.prepare():
            return False
        if not self._bridge.initialize(hwnd):
            self._set_error(self._bridge.last_error())
            return False
        self._bridge_initialized = True
        self._window = qml_window
        if qml_window is not None:
            generation = self._sync_generation
            controller_ref = weakref.ref(self)

            def handle_window_destroyed(_destroyed_window: object = None) -> None:
                controller = controller_ref()
                if controller is not None:
                    controller._on_window_destroyed(generation)

            self._window_destroyed_handler = handle_window_destroyed
            qml_window.destroyed.connect(handle_window_destroyed)
            qml_window.installEventFilter(self)
            qml_window.screenChanged.connect(self._on_screen_changed)
        self._attaching = True
        if self._synchronize_metrics("attach"):
            return True
        return self._attaching

    def prepare(self) -> bool:
        if not is_supported_windows_build(self._os_build):
            self._set_error("Windows 10 version 1809 (build 17763) or newer is required.")
            return False
        if self._prepared:
            return True
        if not self._bridge.prepare():
            self._set_error(self._bridge.last_error())
            return False
        self._prepared = True
        return True

    def set_dark_mode(self, is_dark: bool) -> bool:
        theme = TitleBarTheme.DARK if is_dark else TitleBarTheme.LIGHT
        if not self._available:
            return False
        if not self._bridge.set_theme(int(theme)):
            self._set_error(self._bridge.last_error())
            return False
        self._synchronize_metrics("themeChanged")
        return True

    @pyqtSlot(bool)
    def setDarkMode(self, is_dark: bool) -> None:
        self.set_dark_mode(is_dark)

    def set_drag_rectangles(self, rects: Sequence[dict[str, Any]]) -> bool:
        if not self._available or not self._is_valid_dpr(self._window_dpr):
            return False
        physical_rects = [
            (
                round(float(rect["x"]) * self._window_dpr),
                round(float(rect["y"]) * self._window_dpr),
                round(float(rect["width"]) * self._window_dpr),
                round(float(rect["height"]) * self._window_dpr),
            )
            for rect in rects
        ]
        if not self._bridge.set_drag_rectangles(physical_rects):
            self._set_error(self._bridge.last_error())
            return False
        return True

    @pyqtSlot("QVariantList")
    def setDragRectangles(self, rects: list[dict[str, Any]]) -> None:
        self.set_drag_rectangles(rects)

    @pyqtSlot()
    def refreshMetrics(self) -> None:
        self._schedule_metrics_sync("manual")

    def eventFilter(self, watched: QObject, event: QEvent) -> bool:
        if watched is self._window and event.type() == QEvent.Type.DevicePixelRatioChange:
            self._schedule_metrics_sync("devicePixelRatioChanged")
        return super().eventFilter(watched, event)

    def _on_screen_changed(self, _screen: object) -> None:
        self._schedule_metrics_sync("screenChanged")

    def _on_window_destroyed(self, generation: int) -> None:
        if generation != self._sync_generation:
            return
        self._window = None
        self._window_destroyed_handler = None
        self._reset_attachment()

    def _schedule_metrics_sync(self, reason: str) -> None:
        if not (self._available or self._attaching):
            return
        self._pending_sync_reason = reason
        if self._sync_pending:
            return
        self._sync_pending = True
        generation = self._sync_generation
        QTimer.singleShot(0, lambda: self._run_scheduled_sync(generation))

    def _run_scheduled_sync(self, generation: int) -> None:
        if generation != self._sync_generation:
            return
        self._sync_pending = False
        if not (self._available or self._attaching):
            return
        self._synchronize_metrics(self._pending_sync_reason)

    def _synchronize_metrics(self, reason: str) -> bool:
        try:
            dpr = self._read_window_dpr()
            raw_metrics = self._read_raw_metrics()
            left, right, height = raw_metrics
            logical_metrics = (left / dpr, right / dpr, height / dpr)
            if any(not math.isfinite(value) for value in logical_metrics):
                raise ValueError("Invalid logical title bar metrics.")
        except (OverflowError, TypeError, ValueError, RuntimeError) as error:
            return self._handle_metrics_failure(reason, str(error))

        changed = (
            dpr != self._window_dpr
            or raw_metrics != self._raw_metrics
            or logical_metrics != (self._left_inset, self._right_inset, self._height)
        )
        is_initial_sync = self._attaching
        self._window_dpr = dpr
        self._raw_metrics = raw_metrics
        self._left_inset, self._right_inset, self._height = logical_metrics
        self._sync_retry_count = 0
        self._last_sync_reason = reason
        self._last_sync_status = "success"
        self._set_error("")
        self._refresh_diagnostics()
        if is_initial_sync or changed:
            self.metricsChanged.emit()
        self._complete_initial_attachment()
        return True

    def _read_window_dpr(self) -> float:
        dpr = 1.0 if self._window is None else float(self._window.devicePixelRatio())
        if not self._is_valid_dpr(dpr):
            raise ValueError("Invalid window device pixel ratio.")
        return dpr

    def _read_raw_metrics(self) -> tuple[float, float, float]:
        raw_metrics = tuple(float(value) for value in self._bridge.metrics())
        if len(raw_metrics) != 3 or any(not math.isfinite(value) or value < 0 for value in raw_metrics):
            raise ValueError("Invalid native title bar metrics.")
        return raw_metrics

    @staticmethod
    def _is_valid_dpr(dpr: float) -> bool:
        return math.isfinite(dpr) and dpr > 0

    def _handle_metrics_failure(self, reason: str, error: str) -> bool:
        self._last_sync_reason = reason
        self._last_sync_status = "failed"
        if self._sync_retry_count == 0 and (self._available or self._attaching):
            self._sync_retry_count = 1
            self._schedule_metrics_sync(reason)
        else:
            self._sync_retry_count = 0
            self._set_error(error or self._bridge.last_error())
            self._refresh_diagnostics()
            if self._attaching:
                self._reset_attachment()
        return False

    def _complete_initial_attachment(self) -> None:
        if not self._attaching:
            return
        self._attaching = False
        self._available = True
        self.availableChanged.emit()

    def _reset_attachment(self) -> None:
        metrics_changed = (
            self._window_dpr != 1.0
            or self._raw_metrics != (0, 0, 0)
            or (self._left_inset, self._right_inset, self._height) != (0.0, 0.0, 0.0)
        )
        self._sync_generation += 1
        self._sync_pending = False
        self._pending_sync_reason = "attach"
        self._sync_retry_count = 0
        self._attaching = False
        self._unbind_window()
        if self._bridge_initialized:
            self._bridge.shutdown()
            self._bridge_initialized = False
        if self._available:
            self._available = False
            self.availableChanged.emit()
        self._window_dpr = 1.0
        self._raw_metrics = (0, 0, 0)
        self._left_inset = 0.0
        self._right_inset = 0.0
        self._height = 0.0
        self._last_sync_reason = "unattached"
        self._last_sync_status = "unattached"
        self._set_diagnostic_text("Native diagnostics are unavailable until attachment.")
        if metrics_changed:
            self.metricsChanged.emit()

    def _unbind_window(self) -> None:
        window = self._window
        destroyed_handler = self._window_destroyed_handler
        try:
            if window is None:
                return
            try:
                window.removeEventFilter(self)
            except RuntimeError:
                pass
            try:
                window.screenChanged.disconnect(self._on_screen_changed)
            except (TypeError, RuntimeError):
                pass
            if destroyed_handler is not None:
                try:
                    window.destroyed.disconnect(destroyed_handler)
                except (TypeError, RuntimeError):
                    pass
        finally:
            self._window = None
            self._window_destroyed_handler = None

    def shutdown(self) -> None:
        self._reset_attachment()

    def _refresh_diagnostics(self) -> None:
        try:
            diagnostics = self._bridge.diagnostics()
            top_offset = diagnostics.client_origin_y - diagnostics.window_top
            left_offset = diagnostics.client_origin_x - diagnostics.window_left
            native_diagnostics = (
                f"Extends content: {str(diagnostics.extends_content).lower()}",
                f"Window: {diagnostics.window_width} x {diagnostics.window_height} "
                f"at ({diagnostics.window_left}, {diagnostics.window_top})",
                f"Client: {diagnostics.client_width} x {diagnostics.client_height} "
                f"at screen ({diagnostics.client_origin_x}, {diagnostics.client_origin_y})",
                f"Client offsets: left={left_offset} px, top={top_offset} px",
                f"Client top offset: {top_offset} px",
                f"Title bar: height={diagnostics.title_bar_height} px, "
                f"right inset={diagnostics.right_inset} px",
                f"Style: 0x{diagnostics.style:016X}",
                f"ExStyle: 0x{diagnostics.ex_style:016X}",
                "Native diagnostics: status=success",
            )
        except Exception as error:
            native_diagnostics = (f"Native diagnostics: status=failed, error={error}",)

        self._set_diagnostic_text(
            "\n".join(
                (*native_diagnostics, *self._synchronization_diagnostics())
            )
        )

    def _synchronization_diagnostics(self) -> tuple[str, ...]:
        return (
            f"Window DPR: {self._window_dpr}",
            f"Raw metrics: left={self._raw_metrics[0]} px, right={self._raw_metrics[1]} px, "
            f"height={self._raw_metrics[2]} px",
            f"Logical metrics: left={self._left_inset}, right={self._right_inset}, "
            f"height={self._height}",
            f"Synchronization: reason={self._last_sync_reason}, status={self._last_sync_status}",
        )

    def _set_diagnostic_text(self, diagnostic_text: str) -> None:
        if diagnostic_text != self._diagnostic_text:
            self._diagnostic_text = diagnostic_text
            self.diagnosticTextChanged.emit()

    def _set_error(self, message: str) -> None:
        if message != self._error_message:
            self._error_message = message
            self.errorMessageChanged.emit()

    def __del__(self):
        if hasattr(self, "_bridge") and self._bridge:
            self.shutdown()
