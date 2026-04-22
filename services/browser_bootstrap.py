"""Playwright 브라우저 바이너리 감지 및 설치 유틸리티."""
from __future__ import annotations

import os
import subprocess
from typing import Optional


def _get_driver_command() -> tuple[list[str], dict]:
    """Playwright driver 실행 경로를 반환한다.

    frozen exe 환경에서도 동작하도록 playwright 내부 API를 사용한다.
    """
    from playwright._impl._driver import compute_driver_executable, get_driver_env
    
    # compute_driver_executable() returns (node_exe, cli_js) tuple in recent playwright versions
    driver_executable = compute_driver_executable()
    if isinstance(driver_executable, tuple):
        node_exe, cli_js = driver_executable
        cmd = [str(node_exe), str(cli_js)]
    else:
        cmd = [str(driver_executable)]
        
    return cmd, get_driver_env()


def is_browser_installed(browser: str = "chromium") -> bool:
    """지정된 브라우저 바이너리가 설치되어 있는지 확인한다.

    playwright의 내부 driver를 사용하여 확인하므로 frozen 환경에서도 동작한다.
    launch 시도 방식 대신 가벼운 경로 확인을 사용한다.
    """
    try:
        from playwright.sync_api import sync_playwright
        with sync_playwright() as p:
            browser_type = getattr(p, browser, None)
            if browser_type is None:
                return False
            # executable_path가 존재하고 파일이 있으면 설치된 것
            exec_path = browser_type.executable_path
            return bool(exec_path and os.path.isfile(exec_path))
    except Exception:
        return False


def install_browser(
    browser: str = "chromium",
    on_output: Optional[callable] = None,
) -> tuple[bool, str]:
    """Playwright 브라우저 바이너리를 설치한다.

    Args:
        browser: 설치할 브라우저 이름 ("chromium", "firefox", "webkit")
        on_output: 설치 과정의 stdout/stderr 라인을 받을 콜백

    Returns:
        (success, message) 튜플
    """
    try:
        driver_cmd, driver_env = _get_driver_command()
        cmd = driver_cmd + ["install", browser]

        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=driver_env,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
        )

        output_lines = []
        for line in proc.stdout:
            line = line.rstrip()
            output_lines.append(line)
            if on_output:
                on_output(line)

        proc.wait()

        if proc.returncode == 0:
            return True, "Browser installed successfully."
        else:
            return False, f"Install failed (exit {proc.returncode}):\n" + "\n".join(output_lines[-5:])

    except FileNotFoundError:
        return False, "Playwright driver not found. The application may be corrupted."
    except Exception as e:
        return False, f"Unexpected error: {e}"
