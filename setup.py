from __future__ import annotations

import os
import sys

from cx_Freeze import Executable, setup

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))

build_options = {
    "packages": [
        "PyQt6",
        "PyQt6.QtCore",
        "PyQt6.QtGui",
        "PyQt6.QtQml",
        "PyQt6.QtQuick",
        "PyQt6.QtNetwork",
        "playwright",
        "pandas",
        "requests",
        "bs4",
        "google.auth",
        "google.oauth2",
        "google_auth_oauthlib",
        "googleapiclient",
        "gspread",
        "keyring",
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
    "include_files": [
        (os.path.join(PROJECT_ROOT, "fonts"), "fonts"),
        (os.path.join(PROJECT_ROOT, "ui"), "ui"),
    ],
}

base = "gui" if sys.platform == "win32" else None
executables = [Executable("main.py", base=base, target_name="ArcaeaNap.exe")]

setup(
    name="ArcaeaNap",
    version="0.1",
    description="a simple record viewer for Arcaea",
    options={"build_exe": build_options},
    executables=executables,
)
