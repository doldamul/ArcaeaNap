from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import platform
import shutil
import subprocess
import sys
from typing import Callable


if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.build_cleanup import cleanup_native_build_outputs
from tools.build_config import platform_key
from tools.build_native import build_native_bridge
from tools.native_dev import install_development_bridge


CommandRunner = Callable[..., object]
PROJECT_ROOT = Path(__file__).resolve().parent.parent
BRIDGE_FILENAME = "libmacos_window_bridge.dylib"


@dataclass(frozen=True)
class MacosBridgeBuildResult:
    bridge_path: Path


def _require_cmake() -> None:
    if shutil.which("cmake") is None:
        raise RuntimeError("Build requires CMake on PATH.")


def _validate_platform(machine: str) -> str:
    if sys.platform != "darwin":
        platform_key(sys.platform, machine)
    if machine.lower() != "arm64":
        platform_key("darwin", machine)
    return platform_key("darwin", machine)


def _require_output(path: Path) -> None:
    if not path.is_file() or path.stat().st_size == 0:
        raise RuntimeError(f"macOS bridge build did not produce development bridge: {path}")


def _cleanup_after_failure(*, project_root: Path, target: str, error: BaseException) -> None:
    try:
        cleanup_native_build_outputs(project_root=project_root, target=target)
    except BaseException as cleanup_error:
        error.add_note(f"macOS bridge cleanup failed: {cleanup_error}")


def build_macos_bridge(
    *,
    project_root: Path = PROJECT_ROOT,
    machine: str | None = None,
    runner: CommandRunner | None = None,
) -> MacosBridgeBuildResult:
    project_root = project_root.resolve()
    machine = machine or platform.machine()
    target = _validate_platform(machine)
    run = runner or subprocess.run
    bridge_path = project_root / "native" / BRIDGE_FILENAME

    try:
        _require_cmake()
        native_result = build_native_bridge(
            project_root=project_root,
            platform_name="darwin",
            machine="arm64",
            runner=run,
        )
        install_development_bridge(
            source=native_result.artifacts[0],
            destination=bridge_path,
        )
        _require_output(bridge_path)
        result = MacosBridgeBuildResult(bridge_path=bridge_path)
    except BaseException as error:
        _cleanup_after_failure(project_root=project_root, target=target, error=error)
        raise

    cleanup_native_build_outputs(project_root=project_root, target=target)
    return result


def main() -> int:
    try:
        result = build_macos_bridge()
    except Exception as exc:
        print(f"[macos-bridge] FAILED: {exc}", file=sys.stderr)
        return 1
    print(result.bridge_path.resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
