from __future__ import annotations

import json
import os
import re
import shutil
import sys
import time

from cx_Freeze import Executable, setup
from cx_Freeze.command.build_exe import build_exe

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
LOGO_ICO_PATH = os.path.join(PROJECT_ROOT, "resources", "logo.ico")
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
    (os.path.join(PROJECT_ROOT, "resources"), "resources"),
    (os.path.join(PROJECT_ROOT, "ui"), os.path.join("resources", "ui")),
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
        "win32ctypes",
    ],
    "includes": [],
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
        "googleapiclient.discovery_cache.documents",
        "PyQt6.QAxContainer",
        "PyQt6.QtSql",
        "PyQt6.QtBluetooth",
        "PyQt6.QtDBus",
        "PyQt6.QtDesigner",
        "PyQt6.uic",
        "PyQt6.QtHelp",
        "PyQt6.QtMultimedia",
        "PyQt6.QtMultimediaWidgets",
        "PyQt6.QtOpenGL",
        "PyQt6.QtOpenGLWidgets",
        "PyQt6.QtPdf",
        "PyQt6.QtPdfWidgets",
        "PyQt6.QtPositioning",
        "PyQt6.QtPrintSupport",
        "PyQt6.QtQuick3D",
        "PyQt6.QtQuickWidgets",
        "PyQt6.QtRemoteObjects",
        "PyQt6.QtSensors",
        "PyQt6.QtSerialPort",
        "PyQt6.QtSpatialAudio",
        "PyQt6.QtStateMachine",
        "PyQt6.QtSvgWidgets",
        "PyQt6.QtTest",
        "PyQt6.QtTextToSpeech",
        "PyQt6.QtWebChannel",
        "PyQt6.QtWebSockets",
        "PyQt6.QtXml",
        "PyQt6.Qt3DCore",
        "PyQt6.Qt3DInput",
        "PyQt6.Qt3DLogic",
        "PyQt6.Qt3DRender",
        "PyQt6.QtNfc",
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


class ExtendedBuildExe(build_exe):
    """Custom build command for post-build optimizations."""

    def run(self) -> None:
        super().run()
        build_root = os.path.abspath(str(self.build_exe))

        # --- Playwright Optimizations ---
        bundled_browsers = os.path.join(
            build_root,
            "lib",
            "playwright",
            "driver",
            "package",
            ".local-browsers",
        )
        if os.path.isdir(bundled_browsers):
            shutil.rmtree(bundled_browsers)
            print(f"Removed Playwright bundled browsers: {bundled_browsers}")

        # --- PyQt6 Optimizations ---
        qt_dir = os.path.join(build_root, "lib", "PyQt6")
        if not os.path.isdir(qt_dir):
            return

        qt6_dir = os.path.join(qt_dir, "Qt6")
        if not os.path.isdir(qt6_dir):
            return

        def _remove_path(path: str):
            try:
                if os.path.isfile(path) or os.path.islink(path):
                    os.remove(path)
                elif os.path.isdir(path):
                    shutil.rmtree(path, ignore_errors=True)
            except OSError:
                pass

        # 0. Rescue: 삭제 전, bin/에 없는 필수 DLL을 bin/으로 복사
        # cx_Freeze는 ICU/pcre2 등을 Qt6/bin/이 아닌 QML 플러그인 폴더에만 복사한다.
        # QML 폴더를 삭제하기 전에 이들을 bin/으로 rescue해야 하드링크 dedup의 기준이 생기고
        # Qt6Core.dll 등이 ICU 의존성을 정상적으로 로드할 수 있다.
        bin_dir = os.path.join(qt6_dir, "bin")
        wl_prefixes = (
            "Qt6Core", "Qt6Gui", "Qt6Network", "Qt6OpenGL",
            "Qt6Qml", "Qt6Quick", "Qt6ShaderTools", "Qt6Svg",
            "icu", "pcre2", "zlib", "zstd",
            "libcrypto", "libssl", "d3dcompiler",
        )
        if os.path.isdir(bin_dir):
            existing_in_bin = set(os.listdir(bin_dir))
            for walk_root, _, walk_files in os.walk(qt6_dir):
                if os.path.abspath(walk_root) == os.path.abspath(bin_dir):
                    continue
                for fname in walk_files:
                    if not fname.endswith(".dll"):
                        continue
                    if fname in existing_in_bin:
                        continue
                    if fname.startswith(wl_prefixes):
                        src = os.path.join(walk_root, fname)
                        dst = os.path.join(bin_dir, fname)
                        shutil.copy2(src, dst)
                        existing_in_bin.add(fname)
                        print(f"  Rescued to bin/: {fname}")

        # 1. Clean up unused QML modules
        qml_dir = os.path.join(qt6_dir, "qml")
        if os.path.isdir(qml_dir):
            whitelist_qml = ["QtQml", "QtQuick"]
            for d in os.listdir(qml_dir):
                if d not in whitelist_qml:
                    _remove_path(os.path.join(qml_dir, d))

            # QtQml 하위 정리 (XmlListModel 55MB 등)
            qtqml_dir = os.path.join(qml_dir, "QtQml")
            if os.path.isdir(qtqml_dir):
                whitelist_qtqml = ["Models", "Base", "WorkerScript"]
                for d in os.listdir(qtqml_dir):
                    if os.path.isdir(os.path.join(qtqml_dir, d)) and d not in whitelist_qtqml:
                        _remove_path(os.path.join(qtqml_dir, d))

            qtquick_dir = os.path.join(qml_dir, "QtQuick")
            if os.path.isdir(qtquick_dir):
                whitelist_qtquick = ["Controls", "Dialogs", "Effects", "Layouts", "Particles", "Shapes", "Templates", "Window", "NativeStyle"]
                for d in os.listdir(qtquick_dir):
                    if d not in whitelist_qtquick:
                        _remove_path(os.path.join(qtquick_dir, d))

                controls_dir = os.path.join(qtquick_dir, "Controls")
                if os.path.isdir(controls_dir):
                    whitelist_controls = ["Basic", "Windows", "impl", "Fusion"]
                    for d in os.listdir(controls_dir):
                        if os.path.isdir(os.path.join(controls_dir, d)) and d not in whitelist_controls:
                            _remove_path(os.path.join(controls_dir, d))

        # 2. Clean up unused plugins
        plugins_dir = os.path.join(qt6_dir, "plugins")
        if os.path.isdir(plugins_dir):
            whitelist_plugins = ["generic", "iconengines", "imageformats", "networkinformation", "platforms", "styles", "tls"]
            for d in os.listdir(plugins_dir):
                if d not in whitelist_plugins:
                    _remove_path(os.path.join(plugins_dir, d))

        # 3. Clean up translations
        translations_dir = os.path.join(qt6_dir, "translations")
        if os.path.isdir(translations_dir):
            _remove_path(translations_dir)

        # 6. Deduplicate DLLs with Hardlinks
        self._dedup_dlls_with_hardlinks(qt6_dir, bin_dir)

    def _dedup_dlls_with_hardlinks(self, qt6_dir: str, bin_dir: str):
        if not os.path.isdir(bin_dir):
            return
            
        import hashlib
        def _hash_file(filepath: str) -> str:
            h = hashlib.sha256()
            with open(filepath, "rb") as f:
                for chunk in iter(lambda: f.read(8192), b""):
                    h.update(chunk)
            return h.hexdigest()

        # Gather reference DLLs in bin_dir
        reference_dlls = {}
        for f in os.listdir(bin_dir):
            if f.endswith(".dll"):
                filepath = os.path.join(bin_dir, f)
                filehash = _hash_file(filepath)
                reference_dlls[f] = (filepath, filehash)

        dedup_count = 0
        saved_bytes = 0
        for root, _, files in os.walk(qt6_dir):
            if os.path.abspath(root) == os.path.abspath(bin_dir):
                continue
            for filename in files:
                if filename.endswith(".dll") and filename in reference_dlls:
                    target_path = os.path.join(root, filename)
                    target_hash = _hash_file(target_path)
                    
                    ref_path, ref_hash = reference_dlls[filename]
                    if target_hash == ref_hash:
                        saved_bytes += os.path.getsize(target_path)
                        os.remove(target_path)
                        try:
                            os.link(ref_path, target_path)
                            dedup_count += 1
                        except OSError as e:
                            shutil.copy2(ref_path, target_path)
                            # print(f"Hardlink failed for {filename}, copied instead: {e}")

        if dedup_count > 0:
            print(f"PyQt6 DLL Dedup: Hardlinked {dedup_count} files, saved {saved_bytes / (1024*1024):.2f} MB")

try:
    _write_build_info(APP_TITLE, APP_VERSION, time.time())
    original_consultant = _inject_client_const(_load_client_data_for_build())
    setup(
        name="ArcaeaNap",
        version=APP_VERSION,
        description="a simple record viewer for Arcaea",
        options={"build_exe": build_options},
        executables=executables,
        cmdclass={"build_exe": ExtendedBuildExe},
    )
finally:
    if "original_consultant" in locals():
        with open(CONSULTANT_PATH, "w", encoding="utf-8") as f:
            f.write(original_consultant)
    _write_build_info(APP_TITLE, APP_VERSION, 0.0)