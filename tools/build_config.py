from __future__ import annotations

from dataclasses import dataclass
import importlib.util
from pathlib import Path
import platform as platform_module
import sys


APP_TITLE = "ArcaeaNap"
APP_VERSION = "1.2.0"
MIN_MACOS_VERSION = "14.0"
APP_ICON_NAME = "ArcaeaNap"


@dataclass(frozen=True)
class BridgeArtifact:
    source: Path
    destination: Path


def platform_key(platform_name: str | None = None, machine: str | None = None) -> str:
    platform_name = platform_name or sys.platform
    machine = (machine or platform_module.machine()).lower()

    if platform_name == "win32" and machine in {"amd64", "x86_64"}:
        return "windows-x64"
    if platform_name == "darwin" and machine in {"arm64", "aarch64"}:
        return "macos-arm64"
    raise RuntimeError(
        f"Unsupported native build platform: {platform_name}/{machine}. "
        "Supported targets are Windows x64 and Apple Silicon macOS."
    )


def native_build_dir(project_root: Path, target: str) -> Path:
    return project_root / "build" / "native" / target


def native_stage_dir(project_root: Path, target: str) -> Path:
    return project_root / "build" / "native-stage" / target


def windows_native_inputs_dir(project_root: Path) -> Path:
    """Return the reproducible cache for Windows native build inputs."""
    return project_root / "build" / "windows-native-inputs"


def playwright_browser_exclude_paths() -> tuple[Path, ...]:
    """Return Playwright browser data directories that cx_Freeze must skip.

    Playwright's downloaded browser executables are runtime downloads, not
    application resources.  cx_Freeze otherwise treats them as package data
    and analyzes every Mach-O file while copying it.  Some Chromium helper
    names cannot be opened by Apple's ``otool-classic`` when their path
    contains parentheses, so excluding the directory at copy time also keeps
    the macOS build independent of that tool limitation.
    """
    spec = importlib.util.find_spec("playwright")
    if spec is None or spec.origin in {None, "built-in"}:
        return ()
    browser_dir = (
        Path(spec.origin).resolve().parent
        / "driver"
        / "package"
        / ".local-browsers"
    )
    return (browser_dir,) if browser_dir.is_dir() else ()


def expected_bridge_artifacts(target: str) -> tuple[BridgeArtifact, ...]:
    if target == "windows-x64":
        return (
            BridgeArtifact(
                Path("lib/native/appwindow_titlebar_bridge.dll"),
                Path("lib/native/appwindow_titlebar_bridge.dll"),
            ),
            BridgeArtifact(
                Path("lib/native/Microsoft.WindowsAppRuntime.Bootstrap.dll"),
                Path("lib/native/Microsoft.WindowsAppRuntime.Bootstrap.dll"),
            ),
        )
    if target == "macos-arm64":
        return (
            BridgeArtifact(
                Path("lib/native/libmacos_window_bridge.dylib"),
                Path("lib/native/libmacos_window_bridge.dylib"),
            ),
        )
    raise RuntimeError(f"Unknown native target: {target}")
