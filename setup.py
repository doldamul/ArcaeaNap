from __future__ import annotations

import json
import os
import re
import sys
import time

from cx_Freeze import Executable, setup

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
LOGO_ICO_PATH = os.path.join(PROJECT_ROOT, "logo.ico")
CLIENT_DATA_JSON_PATH = os.path.join(PROJECT_ROOT, "client_secret.json")
CONSULTANT_PATH = os.path.join(PROJECT_ROOT, "utils", "web_consultantsheet.py")

APP_TITLE = "ArcaeaNap"
APP_VERSION = "0.1"
BUILD_INFO_PATH = os.path.join(PROJECT_ROOT, "utils", "app_build_info.py")


def _write_build_info(app_title: str, app_version: str, build_timestamp: float = 0.0) -> None:
    with open(BUILD_INFO_PATH, "w", encoding="utf-8") as f:
        f.write('"""Auto-generated build information. Do not edit manually."""\n\n')
        f.write(f'APP_TITLE = "{app_title}"\n')
        f.write(f'APP_VERSION = "{app_version}"\n')
        f.write(f"BUILD_TIMESTAMP = {build_timestamp}\n")


def _load_client_data_for_build() -> list[str]:
    try:
        with open(CLIENT_DATA_JSON_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError as e:
        raise RuntimeError(
            f"Build requires {CLIENT_DATA_JSON_PATH}. Provide a real client_secret.json before building."
        ) from e
    except json.JSONDecodeError as e:
        raise RuntimeError(
            f"Build requires valid JSON in {CLIENT_DATA_JSON_PATH}."
        ) from e
    except OSError as e:
        raise RuntimeError(
            f"Build cannot read {CLIENT_DATA_JSON_PATH}: {e}"
        ) from e

    if not isinstance(data, dict):
        raise RuntimeError(f"Build requires a JSON object in {CLIENT_DATA_JSON_PATH}.")

    installed = data.get("installed", data.get("web", {}))
    if not isinstance(installed, dict):
        raise RuntimeError("Build requires installed/web object in client_secret.json.")

    key = str(installed.get("api_key", data.get("api_key", ""))).strip()
    idv = str(installed.get("client_id", "")).strip()
    sec = str(installed.get("client_secret", "")).strip()
    if not key or not idv or not sec:
        raise RuntimeError("Build requires non-empty api_key/client_id/client_secret values in client_secret.json.")

    return [key, idv, sec]


def _inject_client_const(values: list[str]) -> str:
    with open(CONSULTANT_PATH, "r", encoding="utf-8") as f:
        original = f.read()

    block = (
        "# CLIENT_CONST_BEGIN\n"
        f"CLIENT = {json.dumps(values, ensure_ascii=False)}  # [0]: key, [1]: id, [2]: sec\n"
        "# CLIENT_CONST_END"
    )
    patched = re.sub(
        r"# CLIENT_CONST_BEGIN\n.*?\n# CLIENT_CONST_END",
        block,
        original,
        count=1,
        flags=re.DOTALL,
    )
    if patched == original:
        raise RuntimeError("CLIENT constant block not found in utils/web_consultantsheet.py.")

    with open(CONSULTANT_PATH, "w", encoding="utf-8") as f:
        f.write(patched)
    return original

include_files = [
    (os.path.join(PROJECT_ROOT, "fonts"), "fonts"),
    (os.path.join(PROJECT_ROOT, "ui"), "ui"),
    (os.path.join(PROJECT_ROOT, "licenses"), "licenses"),
]

build_options = {
    "packages": [
        "PyQt6",
        "PyQt6.QtCore",
        "PyQt6.QtGui",
        "PyQt6.QtQml",
        "PyQt6.QtQuick",
        "PyQt6.QtNetwork",
        "playwright",
        "playwright._impl",
        "playwright.driver",
        "pandas",
        "requests",
        "bs4",
        "google.auth",
        "google.oauth2",
        "google_auth_oauthlib",
        "googleapiclient",
        "gspread",
        "keyring",
        "win32ctypes",
    ],
    "includes": [
        "win32timezone",
    ],
    "excludes": [
        "pytest",
        "unittest",
        "test",
        "tests",
        "pip",
        "setuptools",
        "wheel",
        "distutils",
        "tkinter",
        "matplotlib",
        "scipy",
        "PIL",
    ],
    "include_files": include_files,
}

base = "gui" if sys.platform == "win32" else None
executable_kwargs = {
    "script": "main.py",
    "base": base,
    "target_name": "ArcaeaNap.exe",
}
if os.path.isfile(LOGO_ICO_PATH):
    executable_kwargs["icon"] = LOGO_ICO_PATH
executables = [Executable(**executable_kwargs)]

try:
    _write_build_info(APP_TITLE, APP_VERSION, time.time())
    original_consultant = _inject_client_const(_load_client_data_for_build())
    setup(
        name="ArcaeaNap",
        version=APP_VERSION,
        description="a simple record viewer for Arcaea",
        options={"build_exe": build_options},
        executables=executables,
    )
finally:
    if "original_consultant" in locals():
        with open(CONSULTANT_PATH, "w", encoding="utf-8") as f:
            f.write(original_consultant)
    _write_build_info(APP_TITLE, APP_VERSION, 0.0)
