from __future__ import annotations

import glob
import json
import os
import plistlib
import re
import shutil
import sys
import time

from cx_Freeze import Executable, setup
from cx_Freeze.command.build_exe import build_exe

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
LOGO_ICO_PATH = os.path.join(PROJECT_ROOT, "resources", "logo.ico")
LOGO_ICNS_PATH = os.path.join(PROJECT_ROOT, "resources", "logo.icns")
LOGO_ICON_PATH = os.path.join(PROJECT_ROOT, "resources", "ArcaeaNap.icon")  # Icon Composer source (macOS 26 Tahoe)
APP_ICON_NAME = "ArcaeaNap"  # asset name inside Assets.car; must match CFBundleIconName
MIN_MACOS_VERSION = "14.0"  # supported floor: Apple Silicon, macOS 14 Sonoma+ (deps need 13.5+)
CLIENT_DATA_JSON_PATH = os.path.join(PROJECT_ROOT, "client_secret.json")
CONSULTANT_PATH = os.path.join(PROJECT_ROOT, "utils", "web_consultantsheet.py")

APP_TITLE = "ArcaeaNap"
APP_VERSION = "1.1.0"
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
if os.path.isfile(LOGO_ICO_PATH):
    executable_kwargs["icon"] = LOGO_ICO_PATH
executables = [Executable(**executable_kwargs)]


class ExtendedBuildExe(build_exe):
    """Custom build command for post-build optimizations."""

    def finalize_options(self) -> None:
        super().finalize_options()
        self.build_exe = os.path.join(self.build_exe, "ArcaeaNap")

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

        if sys.platform == "win32":
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

bdist_mac_options: dict = {
    "bundle_name": "ArcaeaNap",
    # Enforce the supported floor so older macOS shows a clean "requires macOS 14"
    # message instead of a cryptic crash from arm64/Qt/node minimums.
    "plist_items": [("LSMinimumSystemVersion", MIN_MACOS_VERSION)],
}
if os.path.isfile(LOGO_ICNS_PATH):
    bdist_mac_options["iconfile"] = LOGO_ICNS_PATH

cmdclass: dict = {"build_exe": ExtendedBuildExe}

if sys.platform == "darwin":
    # cx_Freeze가 bdist_mac 중 번들을 서명하지만, 이후 dylib 경로 보정 등으로
    # 서명이 무효화되어 Apple Silicon에서 실행이 거부될 수 있다
    # (SIGKILL: Code Signature Invalid). 빌드 완료 후 최종 바이트 기준으로
    # inside-out ad-hoc 재서명하여 실행 가능하도록 보장한다.
    from cx_Freeze.command.bdist_mac import bdist_mac

    class ExtendedBdistMac(bdist_mac):
        """Re-sign the finished .app ad-hoc so it launches on Apple Silicon."""

        def run(self) -> None:
            super().run()
            # macOS 26 Tahoe Liquid Glass icon (Default/Dark/Clear/Tinted) must be
            # installed BEFORE re-signing, since it adds Assets.car + edits Info.plist.
            self._install_liquid_glass_icon(self.bundle_dir)
            self._adhoc_resign(self.bundle_dir)

        @staticmethod
        def _find_actool_dev_dir():
            """Locate a DEVELOPER_DIR whose actool can compile .icon (Xcode 26+).

            Honors $DEVELOPER_DIR, else picks the highest-version Xcode>=26 in
            /Applications. Returns the Developer dir path, or None if unavailable.
            """
            def _has_actool(dev):
                return bool(dev) and os.path.isfile(os.path.join(dev, "usr", "bin", "actool"))

            def _xcode_major(app_dir):
                try:
                    with open(os.path.join(app_dir, "Contents", "version.plist"), "rb") as f:
                        ver = plistlib.load(f).get("CFBundleShortVersionString", "")
                    return int(str(ver).split(".")[0])
                except Exception:
                    return 0

            env_dev = os.environ.get("DEVELOPER_DIR")
            if _has_actool(env_dev):
                return env_dev

            candidates = []
            for app in glob.glob("/Applications/Xcode*.app"):
                dev = os.path.join(app, "Contents", "Developer")
                if _has_actool(dev):
                    candidates.append((_xcode_major(app), dev))
            candidates = [c for c in candidates if c[0] >= 26]
            if candidates:
                return max(candidates, key=lambda c: c[0])[1]
            return None

        def _install_liquid_glass_icon(self, bundle_dir: str) -> None:
            import subprocess
            import tempfile

            if not os.path.isdir(LOGO_ICON_PATH):
                return  # no .icon source -> keep .icns-only icon (older macOS look)

            dev_dir = self._find_actool_dev_dir()
            if not dev_dir:
                print("[bdist_mac] Xcode 26+ actool not found; skipping Liquid Glass icon "
                      "(.icns icon kept).")
                return

            resources_dir = os.path.join(bundle_dir, "Contents", "Resources")
            info_plist = os.path.join(bundle_dir, "Contents", "Info.plist")
            if not os.path.isdir(resources_dir) or not os.path.isfile(info_plist):
                print("[bdist_mac] bundle Resources/Info.plist missing; skipping Liquid Glass icon.")
                return

            tmp = tempfile.mkdtemp()
            try:
                # Work on a sanitized copy of the .icon so the committed source stays pristine.
                staged_icon = os.path.join(tmp, f"{APP_ICON_NAME}.icon")
                shutil.copytree(LOGO_ICON_PATH, staged_icon)

                # Workaround: Xcode 26.6's actool crashes ("nil object") on the
                # specular-highlight fields some Icon Composer versions emit. Strip
                # only those; all other Liquid Glass layers/effects are preserved.
                icon_json = os.path.join(staged_icon, "icon.json")
                try:
                    with open(icon_json, "r", encoding="utf-8") as f:
                        spec = json.load(f)
                    spec.pop("features", None)
                    for group in spec.get("groups", []):
                        if isinstance(group, dict):
                            group.pop("specular", None)
                    with open(icon_json, "w", encoding="utf-8") as f:
                        json.dump(spec, f, indent=2)
                except (OSError, ValueError) as e:
                    print(f"[bdist_mac] could not sanitize icon.json ({e}); attempting compile as-is.")

                out_dir = os.path.join(tmp, "out")
                os.makedirs(out_dir, exist_ok=True)
                partial_plist = os.path.join(tmp, "partial.plist")
                env = dict(os.environ, DEVELOPER_DIR=dev_dir)
                result = subprocess.run(
                    [
                        "xcrun", "actool", staged_icon, "--compile", out_dir,
                        "--app-icon", APP_ICON_NAME, "--include-all-app-icons",
                        "--output-partial-info-plist", partial_plist,
                        "--target-device", "mac",
                        "--minimum-deployment-target", "26.0",
                        "--platform", "macosx",
                    ],
                    check=False, capture_output=True, text=True, env=env,
                )
                assets_car = os.path.join(out_dir, "Assets.car")
                if result.returncode != 0 or not os.path.isfile(assets_car):
                    print("[bdist_mac] actool failed to build Assets.car; keeping .icns icon.\n"
                          f"  {result.stderr.strip().splitlines()[0] if result.stderr.strip() else ''}")
                    return

                shutil.copy2(assets_car, os.path.join(resources_dir, "Assets.car"))

                # Point Tahoe at the catalog icon while keeping CFBundleIconFile (.icns)
                # for macOS < 26.
                icon_name = APP_ICON_NAME
                try:
                    with open(partial_plist, "rb") as f:
                        icon_name = plistlib.load(f).get("CFBundleIconName", APP_ICON_NAME)
                except Exception:
                    pass
                with open(info_plist, "rb") as f:
                    plist = plistlib.load(f)
                plist["CFBundleIconName"] = icon_name
                with open(info_plist, "wb") as f:
                    plistlib.dump(plist, f)

                print(f"[bdist_mac] Liquid Glass icon installed (Assets.car, "
                      f"CFBundleIconName={icon_name}).")
            finally:
                shutil.rmtree(tmp, ignore_errors=True)

        def _adhoc_resign(self, bundle_dir: str) -> None:
            import subprocess

            if not os.path.isdir(bundle_dir):
                print(f"[bdist_mac] bundle not found for re-sign: {bundle_dir}")
                return

            # 1) 내부 모든 Mach-O(dylib/so)를 먼저 ad-hoc 서명 (inside-out)
            for root, _, files in os.walk(bundle_dir):
                for fname in files:
                    if fname.endswith((".dylib", ".so")):
                        subprocess.run(
                            ["codesign", "--force", "--sign", "-", os.path.join(root, fname)],
                            check=False, capture_output=True,
                        )

            # 2) 번들 전체 deep ad-hoc 서명 (메인 실행파일 포함)
            result = subprocess.run(
                ["codesign", "--force", "--deep", "--sign", "-", bundle_dir],
                check=False, capture_output=True, text=True,
            )
            if result.returncode != 0:
                print(f"[bdist_mac] ad-hoc re-sign FAILED: {result.stderr.strip()}")
                return
            print(f"[bdist_mac] ad-hoc re-signed: {bundle_dir}")

            # 3) 검증
            verify = subprocess.run(
                ["codesign", "--verify", "--deep", "--strict", bundle_dir],
                check=False, capture_output=True, text=True,
            )
            if verify.returncode == 0:
                print("[bdist_mac] signature verified valid.")
            else:
                print(f"[bdist_mac] WARNING signature still invalid: {verify.stderr.strip()}")

    cmdclass["bdist_mac"] = ExtendedBdistMac

try:
    _write_build_info(APP_TITLE, APP_VERSION, time.time())
    original_consultant = _inject_client_const(_load_client_data_for_build())
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
        cmdclass=cmdclass,
    )
finally:
    if "original_consultant" in locals():
        with open(CONSULTANT_PATH, "w", encoding="utf-8") as f:
            f.write(original_consultant)
    _write_build_info(APP_TITLE, APP_VERSION, 0.0)