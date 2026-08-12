from __future__ import annotations

import hashlib
import os
from pathlib import Path
import shutil


PLAYWRIGHT_PACKAGE_RELATIVE_PATH = Path("lib/playwright/driver/package")
APP_ICON_RELATIVE_PATH = Path("resources/appIcon.png")
WINDOWS_ARTIFACT_REQUIRED_RELATIVE_PATHS = (
    Path("ArcaeaNap.exe"),
    Path("lib/native/appwindow_titlebar_bridge.dll"),
    Path("lib/native/Microsoft.WindowsAppRuntime.Bootstrap.dll"),
    Path("resources/licenses/windows-app-sdk.txt"),
    Path("resources/licenses/cppwinrt-mit.txt"),
)
WINDOWS_ARTIFACT_FORBIDDEN_SUFFIXES = (".pdb", ".ilk", ".exp", ".lib")
WINDOWS_ARTIFACT_FORBIDDEN_PATHS = (
    "client_secret.json",
    "native/cmakelists.txt",
    "native/generated/",
    "native/third_party/",
    ".local-browsers/",
)


def replace_bundled_playwright_app_icons(build_root: Path) -> tuple[Path, ...]:
    source = build_root / APP_ICON_RELATIVE_PATH
    if not source.is_file():
        raise RuntimeError(f"Replacement app icon is missing: {source}")

    package_root = build_root / PLAYWRIGHT_PACKAGE_RELATIVE_PATH
    if not package_root.is_dir():
        return ()

    replaced: list[Path] = []
    for target in sorted(package_root.rglob("appIcon.png")):
        if target.is_symlink() or target.is_file():
            target.unlink()
            shutil.copy2(source, target)
            replaced.append(target)
        elif target.exists():
            raise RuntimeError(f"Playwright app icon must be a file: {target}")
    return tuple(replaced)


def remove_bundled_playwright_browsers(build_root: Path) -> bool:
    browser_dir = build_root / "lib" / "playwright" / "driver" / "package" / ".local-browsers"
    if not browser_dir.is_dir():
        return False
    shutil.rmtree(browser_dir)
    return True


def _remove_path(path: Path) -> None:
    try:
        if path.is_file() or path.is_symlink():
            path.unlink()
        elif path.is_dir():
            shutil.rmtree(path, ignore_errors=True)
    except OSError:
        pass


def _dedup_dlls_with_hardlinks(qt6_dir: Path, bin_dir: Path) -> int:
    if not bin_dir.is_dir():
        return 0

    def file_hash(path: Path) -> str:
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(8192), b""):
                digest.update(chunk)
        return digest.hexdigest()

    references = {
        path.name: (path, file_hash(path))
        for path in bin_dir.iterdir()
        if path.is_file() and path.suffix.lower() == ".dll"
    }
    dedup_count = 0
    for root, _, files in os.walk(qt6_dir):
        root_path = Path(root)
        if root_path.resolve() == bin_dir.resolve():
            continue
        for filename in files:
            if not filename.lower().endswith(".dll") or filename not in references:
                continue
            target = root_path / filename
            reference, reference_hash = references[filename]
            if file_hash(target) != reference_hash:
                continue
            try:
                target.unlink()
                os.link(reference, target)
                dedup_count += 1
            except OSError:
                try:
                    shutil.copy2(reference, target)
                except OSError:
                    pass
    return dedup_count


def optimize_windows_qt(build_root: Path) -> int:
    qt6_dir = build_root / "lib" / "PyQt6" / "Qt6"
    if not qt6_dir.is_dir():
        return 0

    bin_dir = qt6_dir / "bin"
    wl_prefixes = (
        "Qt6Core", "Qt6Gui", "Qt6Network", "Qt6OpenGL", "Qt6Qml", "Qt6Quick",
        "Qt6ShaderTools", "Qt6Svg", "icu", "pcre2", "zlib", "zstd",
        "libcrypto", "libssl", "d3dcompiler",
    )
    if bin_dir.is_dir():
        existing_in_bin = {path.name for path in bin_dir.iterdir()}
        for root, _, files in os.walk(qt6_dir):
            root_path = Path(root)
            if root_path.resolve() == bin_dir.resolve():
                continue
            for filename in files:
                if not filename.lower().endswith(".dll") or filename in existing_in_bin:
                    continue
                if filename.startswith(wl_prefixes):
                    shutil.copy2(root_path / filename, bin_dir / filename)
                    existing_in_bin.add(filename)

    qml_dir = qt6_dir / "qml"
    if qml_dir.is_dir():
        whitelist_qml = ["QtQml", "QtQuick"]
        for child in qml_dir.iterdir():
            if child.name not in whitelist_qml:
                _remove_path(child)

        qtqml_dir = qml_dir / "QtQml"
        whitelist_qtqml = ["Models", "Base", "WorkerScript"]
        if qtqml_dir.is_dir():
            for child in qtqml_dir.iterdir():
                if child.is_dir() and child.name not in whitelist_qtqml:
                    _remove_path(child)

        qtquick_dir = qml_dir / "QtQuick"
        whitelist_qtquick = [
            "Controls", "Dialogs", "Effects", "Layouts", "Particles", "Shapes",
            "Templates", "Window", "NativeStyle",
        ]
        if qtquick_dir.is_dir():
            for child in qtquick_dir.iterdir():
                if child.is_dir() and child.name not in whitelist_qtquick:
                    _remove_path(child)
                elif (
                    child.is_file()
                    and child.name not in {"qmldir", "plugins.qmltypes"}
                    and child.suffix.lower() not in {".dll", ".dylib", ".so"}
                ):
                    _remove_path(child)
            controls_dir = qtquick_dir / "Controls"
            whitelist_controls = ["Basic", "Windows", "impl", "Fusion"]
            if controls_dir.is_dir():
                for child in controls_dir.iterdir():
                    if child.is_dir() and child.name not in whitelist_controls:
                        _remove_path(child)

    plugins_dir = qt6_dir / "plugins"
    whitelist_plugins = [
        "generic", "iconengines", "imageformats", "networkinformation", "platforms",
        "styles", "tls",
    ]
    if plugins_dir.is_dir():
        for child in plugins_dir.iterdir():
            if child.name not in whitelist_plugins:
                _remove_path(child)

    _remove_path(qt6_dir / "translations")
    return _dedup_dlls_with_hardlinks(qt6_dir, bin_dir)


def postprocess_windows(build_root: Path) -> None:
    remove_bundled_playwright_browsers(build_root)
    replace_bundled_playwright_app_icons(build_root)
    optimize_windows_qt(build_root)


def find_windows_build_root(project_root: Path) -> Path:
    candidates = [path / "ArcaeaNap" for path in (project_root / "build").glob("exe.*")]
    candidates = [path for path in candidates if path.is_dir()]
    if not candidates:
        raise RuntimeError("Could not locate cx_Freeze Windows output under build/exe.*/ArcaeaNap.")
    return max(candidates, key=lambda path: path.stat().st_mtime)


def find_macos_bundle(project_root: Path) -> Path:
    candidates = [
        path
        for output_dir in (project_root / "build", project_root / "dist")
        for path in output_dir.glob("*.app")
        if path.is_dir()
    ]
    if not candidates:
        raise RuntimeError("Could not locate the cx_Freeze macOS .app bundle under build/.")
    return max(candidates, key=lambda path: path.stat().st_mtime)


def verify_windows_artifact(build_root: Path) -> None:
    required = [build_root / path for path in WINDOWS_ARTIFACT_REQUIRED_RELATIVE_PATHS]
    missing = [path for path in required if not path.is_file() or path.stat().st_size == 0]
    forbidden: list[Path] = []
    if build_root.is_dir():
        for path in build_root.rglob("*"):
            relative = path.relative_to(build_root).as_posix().lower()
            parts = relative.split("/")
            is_forbidden_path = (
                relative == "client_secret.json"
                or relative == "native/cmakelists.txt"
                or relative == "native/generated"
                or relative.startswith("native/generated/")
                or relative == "native/third_party"
                or relative.startswith("native/third_party/")
                or ".local-browsers" in parts
            )
            if path.suffix.lower() in WINDOWS_ARTIFACT_FORBIDDEN_SUFFIXES or is_forbidden_path:
                forbidden.append(path)

    failures: list[str] = []
    if missing:
        failures.append("missing required files: " + ", ".join(map(str, missing)))
    if forbidden:
        failures.append("forbidden files: " + ", ".join(map(str, forbidden)))
    if failures:
        raise RuntimeError("Windows artifact validation failed: " + "; ".join(failures))


def verify_macos_artifact(bundle_dir: Path) -> None:
    executable = bundle_dir / "Contents" / "MacOS" / "ArcaeaNap"
    bridge = bundle_dir / "Contents" / "Resources" / "lib" / "native" / "libmacos_window_bridge.dylib"
    if not executable.is_file() or not bridge.is_file() or bridge.stat().st_size == 0:
        raise RuntimeError(f"macOS artifact is missing the app executable or bridge dylib: {bundle_dir}")
    browser_dir = bundle_dir / "Contents" / "Resources" / "lib" / "playwright" / "driver" / "package" / ".local-browsers"
    if browser_dir.exists():
        raise RuntimeError("macOS artifact still contains bundled Playwright browsers.")
