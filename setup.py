from __future__ import annotations

import os
import sys

from cx_Freeze import Executable, setup

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
LOGO_ICO_PATH = os.path.join(PROJECT_ROOT, "logo.ico")

include_files = [
    (os.path.join(PROJECT_ROOT, "fonts"), "fonts"),
    (os.path.join(PROJECT_ROOT, "ui"), "ui"),
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
