"""
Playwright Chromium 브라우저 유틸리티 모듈

Selenium의 browserdriver.py를 대체하며, Chromium 실행과 테마 동기화를 담당합니다.
"""

import ctypes
import logging
import sys
from ctypes import wintypes

from playwright.sync_api import Playwright, Browser


logger = logging.getLogger(__name__)


def get_chromium_launch_args(is_dark_mode: bool) -> list[str]:
    """Return Chromium launch arguments for the requested color scheme."""
    args = [
        '--disable-blink-features=AutomationControlled',
        '--disable-infobars',
        '--disable-dev-shm-usage',
        '--no-first-run',
        '--no-default-browser-check',
    ]

    if is_dark_mode:
        args.append('--force-dark-mode')

    return args


def get_context_theme_options(is_dark_mode: bool) -> dict[str, str]:
    """Return Playwright context options for the requested color scheme."""
    return {'color_scheme': 'dark' if is_dark_mode else 'light'}


def apply_browser_window_theme(pid: int, is_dark_mode: bool) -> bool:
    """Apply a Chromium window's dark-mode frame attribute on Windows.

    The helper is intentionally best-effort: unsupported platforms and any
    ctypes/DWM failure return ``False`` so browser analysis can continue.
    """
    if sys.platform != 'win32':
        return False

    try:
        target_pid = int(pid)
    except (TypeError, ValueError):
        return False

    if target_pid <= 0:
        return False

    try:
        user32 = ctypes.windll.user32
        dwmapi = ctypes.windll.dwmapi
        enum_windows = user32.EnumWindows
        is_window_visible = user32.IsWindowVisible
        get_window_thread_process_id = user32.GetWindowThreadProcessId
        set_window_pos = user32.SetWindowPos
        set_window_attribute = dwmapi.DwmSetWindowAttribute

        enum_window_callback_type = ctypes.WINFUNCTYPE(
            wintypes.BOOL,
            wintypes.HWND,
            wintypes.LPARAM,
        )
        enum_windows.argtypes = [
            enum_window_callback_type,
            wintypes.LPARAM,
        ]
        enum_windows.restype = wintypes.BOOL
        is_window_visible.argtypes = [wintypes.HWND]
        is_window_visible.restype = wintypes.BOOL
        get_window_thread_process_id.argtypes = [
            wintypes.HWND,
            ctypes.POINTER(wintypes.DWORD),
        ]
        get_window_thread_process_id.restype = wintypes.DWORD
        set_window_attribute.argtypes = [
            wintypes.HWND,
            wintypes.DWORD,
            ctypes.c_void_p,
            wintypes.DWORD,
        ]
        set_window_attribute.restype = wintypes.LONG
        set_window_pos.argtypes = [
            wintypes.HWND,
            wintypes.HWND,
            wintypes.INT,
            wintypes.INT,
            wintypes.INT,
            wintypes.INT,
            wintypes.UINT,
        ]
        set_window_pos.restype = wintypes.BOOL

        window_handles = []

        @enum_window_callback_type
        def enum_window_callback(hwnd, _lparam):
            if not hwnd or not is_window_visible(hwnd):
                return True

            process_id = wintypes.DWORD()
            get_window_thread_process_id(hwnd, ctypes.byref(process_id))
            if process_id.value == target_pid:
                window_handles.append(hwnd)
            return True

        enum_windows(enum_window_callback, 0)
        if not window_handles:
            return False

        dark_mode_value = ctypes.c_int(1 if is_dark_mode else 0)
        frame_change_flags = (
            0x0001  # SWP_NOSIZE
            | 0x0002  # SWP_NOMOVE
            | 0x0004  # SWP_NOZORDER
            | 0x0010  # SWP_NOACTIVATE
            | 0x0020  # SWP_FRAMECHANGED
        )
        updated = False

        for hwnd in window_handles:
            try:
                result = set_window_attribute(
                    hwnd,
                    20,  # DWMWA_USE_IMMERSIVE_DARK_MODE
                    ctypes.byref(dark_mode_value),
                    ctypes.sizeof(dark_mode_value),
                )
            except Exception as exc:
                logger.warning(
                    "Chromium window dark-mode attribute 20 failed: %s", exc
                )
                result = 1

            if result != 0:
                try:
                    result = set_window_attribute(
                        hwnd,
                        19,  # Older Windows builds use attribute 19.
                        ctypes.byref(dark_mode_value),
                        ctypes.sizeof(dark_mode_value),
                    )
                except Exception as exc:
                    logger.warning(
                        "Chromium window dark-mode attribute 19 failed: %s", exc
                    )
                    result = 1
            if result != 0:
                logger.warning(
                    "DwmSetWindowAttribute failed for Chromium window %s", hwnd
                )
                continue

            try:
                refreshed = set_window_pos(
                    hwnd, 0, 0, 0, 0, 0, frame_change_flags
                )
            except Exception as exc:
                logger.warning("SetWindowPos failed for Chromium window %s: %s", hwnd, exc)
                continue
            if not refreshed:
                logger.warning("SetWindowPos returned failure for Chromium window %s", hwnd)
                continue

            updated = True

        return updated
    except Exception as exc:
        logger.warning("Unable to apply Chromium window theme: %s", exc)
        return False


def get_browser(
    playwright: Playwright,
    headless: bool = False,
    is_dark_mode: bool = False,
) -> Browser:
    """
    설치된 Playwright Chromium 브라우저를 반환합니다.

    Args:
        playwright: Playwright 인스턴스
        headless: 헤드리스 모드 여부
        is_dark_mode: 다크 모드 실행 여부

    Returns:
        Browser: 실행된 브라우저 인스턴스

    Raises:
        RuntimeError: Chromium이 설치되지 않았거나 실행할 수 없는 경우
    """
    try:
        return playwright.chromium.launch(
            headless=headless,
            args=get_chromium_launch_args(is_dark_mode),
        )
    except Exception as exc:
        raise RuntimeError(
            "Chromium is required to run the browser. "
            "Run 'playwright install chromium' first. "
            f"Launch error: {exc}"
        ) from exc
