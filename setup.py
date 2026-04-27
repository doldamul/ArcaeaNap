from __future__ import annotations

import os
import sys
import time

from cx_Freeze import Executable, setup

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
LOGO_ICO_PATH = os.path.join(PROJECT_ROOT, "logo.ico")

APP_TITLE = "ArcaeaNap"
APP_VERSION = "0.1"
BUILD_INFO_PATH = os.path.join(PROJECT_ROOT, "utils", "app_build_info.py")


def _write_build_info(app_title: str, app_version: str, build_timestamp: float = 0.0) -> None:
    with open(BUILD_INFO_PATH, "w", encoding="utf-8") as f:
        f.write('"""Auto-generated build information. Do not edit manually."""\n\n')
        f.write(f'APP_TITLE = "{app_title}"\n')
        f.write(f'APP_VERSION = "{app_version}"\n')
        f.write(f"BUILD_TIMESTAMP = {build_timestamp}\n")

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
    setup(
        name="ArcaeaNap",
        version=APP_VERSION,
        description="a simple record viewer for Arcaea",
        options={"build_exe": build_options},
        executables=executables,
    )
finally:
    _write_build_info(APP_TITLE, APP_VERSION, 0.0)
