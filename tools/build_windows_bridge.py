from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
from typing import Callable

from .build_cleanup import cleanup_native_build_outputs
from .build_config import platform_key
from .build_native import build_native_bridge
from .native_dev import install_development_bridges


CommandRunner = Callable[..., object]
PROJECT_ROOT = Path(__file__).resolve().parent.parent


@dataclass(frozen=True)
class WindowsBridgeBuildResult:
    bridge_paths: tuple[Path, ...]


def build_windows_bridge(
    *,
    project_root: Path = PROJECT_ROOT,
    machine: str | None = None,
    runner: CommandRunner | None = None,
) -> WindowsBridgeBuildResult:
    project_root = project_root.resolve()
    machine = machine or platform.machine()
    target = _validate_platform(machine)
    _require_build_tools()
    run = runner or _run_subprocess
    build_error: BaseException | None = None

    try:
        native_result = build_native_bridge(
            project_root=project_root,
            platform_name="win32",
            machine=machine,
            runner=run,
        )
        artifact_pairs = tuple(
            (source, project_root / "native" / source.name)
            for source in native_result.artifacts
        )
        install_development_bridges(artifacts=artifact_pairs)
        return WindowsBridgeBuildResult(
            tuple(destination for _, destination in artifact_pairs)
        )
    except BaseException as error:
        build_error = error
        raise
    finally:
        try:
            cleanup_native_build_outputs(project_root=project_root, target=target)
        except Exception as cleanup_error:
            if build_error is None:
                raise
            build_error.add_note(f"Native build cleanup failed: {cleanup_error}")


def _validate_platform(machine: str) -> str:
    if sys.platform != "win32":
        raise RuntimeError("Windows native bridge build must run on Windows.")
    return platform_key("win32", machine)


def _require_build_tools() -> None:
    if shutil.which("cmake") is None:
        raise RuntimeError("Build requires CMake on PATH.")


def _deduplicate_windows_environment(
    environment: Mapping[str, str],
) -> dict[str, str]:
    deduplicated: dict[str, str] = {}
    seen: set[str] = set()
    for key, value in environment.items():
        normalized_key = key.casefold()
        if normalized_key in seen:
            continue
        seen.add(normalized_key)
        deduplicated[key] = value
    return deduplicated


def _run_subprocess(command: list[str], **kwargs: object) -> object:
    environment = kwargs.get("env") or os.environ
    kwargs["env"] = _deduplicate_windows_environment(environment)
    return subprocess.run(command, **kwargs)


def main() -> int:
    try:
        result = build_windows_bridge()
    except Exception as exc:
        print(f"[windows-bridge] FAILED: {exc}", file=sys.stderr)
        for note in getattr(exc, "__notes__", ()):
            print(f"[windows-bridge] NOTE: {note}", file=sys.stderr)
        return 1
    for path in result.bridge_paths:
        print(path.resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
