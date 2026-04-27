from __future__ import annotations

import os
import sys
import time

from cx_Freeze import Executable, setup

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
LOGO_ICO_PATH = os.path.join(PROJECT_ROOT, "logo.ico")

# Update build info in source code
APP_TITLE = "ArcaeaNap"
APP_VERSION = "0.1"
BUILD_INFO_PATH = os.path.join(PROJECT_ROOT, "utils", "app_build_info.py")
with open(BUILD_INFO_PATH, "w", encoding="utf-8") as f:
    f.write(f'"""Auto-generated build information. Do not edit manually."""\n\n')
    f.write(f'APP_TITLE = "{APP_TITLE}"\n')
    f.write(f'APP_VERSION = "{APP_VERSION}"\n')
    f.write(f'BUILD_TIMESTAMP = {time.time()}\n')

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

setup(
    name="ArcaeaNap",
    version="0.1",
    description="a simple record viewer for Arcaea",
    options={"build_exe": build_options},
    executables=executables,
)
