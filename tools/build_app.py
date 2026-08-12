from __future__ import annotations

import platform
from pathlib import Path
import shutil
import subprocess
import sys
import time
from typing import Callable

from .build_config import APP_TITLE, APP_VERSION, platform_key
from .build_cleanup import (
    cleanup_macos_cxfreeze_outputs,
    cleanup_native_build_outputs,
)
from .build_inputs import load_client_values, prepared_build_inputs
from .build_native import build_native_bridge
from .build_postprocess import (
    find_macos_bundle,
    find_windows_build_root,
    postprocess_windows,
    verify_macos_artifact,
    verify_windows_artifact,
)
from .macos_bundle import postprocess_macos


CommandRunner = Callable[..., object]
PROJECT_ROOT = Path(__file__).resolve().parent.parent


def cxfreeze_command(platform_name: str | None = None) -> list[str]:
    platform_name = platform_name or sys.platform
    if platform_name == "win32":
        return [sys.executable, "setup.py", "build"]
    if platform_name == "darwin":
        return [sys.executable, "setup.py", "bdist_mac"]
    raise RuntimeError(f"Unsupported cx_Freeze platform: {platform_name}")


def _preflight(project_root: Path, platform_name: str, machine: str) -> tuple[str, list[str]]:
    target = platform_key(platform_name, machine)
    if shutil.which("cmake") is None:
        raise RuntimeError("Build requires CMake on PATH.")
    if target == "macos-arm64" and shutil.which("codesign") is None:
        raise RuntimeError("Build requires codesign on PATH for the macOS ad-hoc signing step.")
    values = load_client_values(project_root / "client_secret.json")
    return target, values


def run_build(
    *,
    project_root: Path = PROJECT_ROOT,
    platform_name: str | None = None,
    machine: str | None = None,
    runner: CommandRunner | None = None,
    timestamp: float | None = None,
) -> Path:
    platform_name = platform_name or sys.platform
    machine = machine or platform.machine()
    run = runner or subprocess.run
    target = None
    target, values = _preflight(project_root, platform_name, machine)
    try:
        print(f"[build] target={target}")
        native_result = build_native_bridge(
            project_root=project_root,
            platform_name=platform_name,
            machine=machine,
            runner=run,
        )
        print(f"[build] native bridge staged under {native_result.stage_dir}")

        command = cxfreeze_command(platform_name)
        consultant_path = project_root / "utils" / "web_consultantsheet.py"
        build_info_path = project_root / "utils" / "app_build_info.py"
        build_timestamp = time.time() if timestamp is None else timestamp
        with prepared_build_inputs(
            consultant_path=consultant_path,
            build_info_path=build_info_path,
            values=values,
            app_title=APP_TITLE,
            app_version=APP_VERSION,
            timestamp=build_timestamp,
        ):
            print("[build] running " + " ".join(command))
            run(command, cwd=project_root, check=True)

        if target == "windows-x64":
            build_root = find_windows_build_root(project_root)
            postprocess_windows(build_root)
            verify_windows_artifact(build_root)
            print(f"[build] Windows artifact ready: {build_root}")
            return build_root

        bundle_dir = find_macos_bundle(project_root)
        postprocess_macos(
            bundle_dir,
            icon_source=project_root / "resources" / "ArcaeaNap.icon",
            app_icon_name="ArcaeaNap",
        )
        verify_macos_artifact(bundle_dir)
        print(f"[build] macOS artifact ready: {bundle_dir}")
        return bundle_dir
    finally:
        if target is not None:
            cleanup_native_build_outputs(project_root=project_root, target=target)
            if target == "macos-arm64":
                cleanup_macos_cxfreeze_outputs(project_root=project_root)


def main() -> int:
    try:
        run_build()
    except Exception as exc:
        print(f"[build] FAILED: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
