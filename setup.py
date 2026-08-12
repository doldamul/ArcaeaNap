from __future__ import annotations

import os
from pathlib import Path
import platform
import sys

from cx_Freeze import Executable, setup
from cx_Freeze.command.build_exe import build_exe
import PyQt6

from tools.build_config import (
    APP_VERSION,
    MIN_MACOS_VERSION,
    expected_bridge_artifacts,
    native_stage_dir,
    platform_key,
    playwright_browser_exclude_paths,
)


PROJECT_ROOT = Path(__file__).resolve().parent
LOGO_ICO_PATH = PROJECT_ROOT / "resources" / "logo.ico"
LOGO_ICNS_PATH = PROJECT_ROOT / "resources" / "logo.icns"


def _native_include_files() -> list[tuple[str, str]]:
    target = platform_key(sys.platform, platform.machine())
    stage_dir = native_stage_dir(PROJECT_ROOT, target)
    include_files: list[tuple[str, str]] = []
    missing: list[Path] = []
    for artifact in expected_bridge_artifacts(target):
        source = stage_dir / artifact.source
        if not source.is_file() or source.stat().st_size == 0:
            missing.append(source)
        else:
            include_files.append((str(source), str(artifact.destination)))
    if missing:
        missing_text = "\n".join(f"  - {path}" for path in missing)
        raise RuntimeError(
            "Native bridge artifacts are not staged. Run `python -m tools.build_app` first.\n"
            + missing_text
        )
    return include_files


def _qt_qml_include_files() -> list[tuple[str, str]]:
    """Include the top-level QtQuick module metadata and plugin.

    cx_Freeze discovers the nested QtQuick QML modules through PyQt6, but it
    does not always copy the top-level ``QtQuick/qmldir`` and
    ``qtquick2plugin`` files.  Without them the packaged engine falls back to
    Qt's built-in resource path and cannot load the QtObject type used by the
    application's singleton Theme module.
    """
    qml_root = Path(PyQt6.__file__).resolve().parent / "Qt6" / "qml"
    qtquick_root = qml_root / "QtQuick"
    include_files: list[tuple[str, str]] = []
    for source in qtquick_root.iterdir() if qtquick_root.is_dir() else ():
        if source.name in {"qmldir", "plugins.qmltypes"} or (
            source.stem in {"qtquick2plugin", "libqtquick2plugin"}
            and source.suffix.lower() in {".dll", ".dylib", ".so"}
        ):
            destination = Path("lib") / "PyQt6" / "Qt6" / "qml" / "QtQuick" / source.name
            include_files.append((str(source), str(destination)))
    return include_files


include_files: list[tuple[str, str]] = [
    (str(PROJECT_ROOT / "resources"), "resources"),
    (str(PROJECT_ROOT / "ui"), os.path.join("resources", "ui")),
]
licenses_dir = PROJECT_ROOT / "licenses"
if licenses_dir.is_dir():
    include_files.append((str(licenses_dir), "licenses"))
include_files.extend(_native_include_files())
include_files.extend(_qt_qml_include_files())
playwright_exclude_paths = [
    str(path) for path in playwright_browser_exclude_paths()
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
        "requests",
        "bs4",
        "google.auth",
        "google.oauth2",
        "google_auth_oauthlib",
        "googleapiclient",
        "gspread",
        "keyring",
    ],
    "includes": [],
    "bin_path_excludes": playwright_exclude_paths,
    "excludes": [
        "pytest", "unittest", "test", "tests", "pip", "setuptools", "wheel",
        "distutils", "tkinter", "matplotlib", "scipy", "PIL",
        "googleapiclient.discovery_cache.documents",
        "PyQt6.QAxContainer", "PyQt6.QtSql", "PyQt6.QtBluetooth", "PyQt6.QtDBus",
        "PyQt6.QtDesigner", "PyQt6.uic", "PyQt6.QtHelp", "PyQt6.QtMultimedia",
        "PyQt6.QtMultimediaWidgets", "PyQt6.QtOpenGL", "PyQt6.QtOpenGLWidgets",
        "PyQt6.QtPdf", "PyQt6.QtPdfWidgets", "PyQt6.QtPositioning",
        "PyQt6.QtPrintSupport", "PyQt6.QtQuick3D", "PyQt6.QtQuickWidgets",
        "PyQt6.QtRemoteObjects", "PyQt6.QtSensors", "PyQt6.QtSerialPort",
        "PyQt6.QtSpatialAudio", "PyQt6.QtStateMachine", "PyQt6.QtSvgWidgets",
        "PyQt6.QtTest", "PyQt6.QtTextToSpeech", "PyQt6.QtWebChannel",
        "PyQt6.QtWebSockets", "PyQt6.QtXml", "PyQt6.Qt3DCore", "PyQt6.Qt3DInput",
        "PyQt6.Qt3DLogic", "PyQt6.Qt3DRender", "PyQt6.QtNfc",
    ],
    "include_files": include_files,
}
if sys.platform == "win32":
    build_options["packages"] += ["win32ctypes"]
elif sys.platform == "darwin":
    build_options["packages"] += ["objc", "Foundation", "AppKit", "keyring.backends.macOS"]


if sys.platform == "win32":
    base = "gui"
    target_name = "ArcaeaNap.exe"
else:
    base = None
    target_name = "ArcaeaNap"
executable_kwargs = {
    "script": "main.py",
    "base": base,
    "target_name": target_name,
}
if LOGO_ICO_PATH.is_file():
    executable_kwargs["icon"] = str(LOGO_ICO_PATH)
executables = [Executable(**executable_kwargs)]


class ExtendedBuildExe(build_exe):
    """Keep the historical Windows output directory layout."""

    def finalize_options(self) -> None:
        super().finalize_options()
        self.build_exe = os.path.join(self.build_exe, "ArcaeaNap")


bdist_mac_options: dict = {
    "bundle_name": "ArcaeaNap",
    "plist_items": [
        ("LSMinimumSystemVersion", MIN_MACOS_VERSION),
    ],
}
if LOGO_ICNS_PATH.is_file():
    bdist_mac_options["iconfile"] = str(LOGO_ICNS_PATH)


setup(
    name="ArcaeaNap",
    version=APP_VERSION,
    description="a simple record viewer for Arcaea",
    options={
        "build_exe": build_options,
        "bdist_mac": bdist_mac_options,
        "bdist_dmg": {"volume_label": "ArcaeaNap", "applications_shortcut": True},
    },
    executables=executables,
    cmdclass={"build_exe": ExtendedBuildExe},
)
