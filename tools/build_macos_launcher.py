from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import sysconfig
from typing import Callable


if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.build_config import platform_key


CommandRunner = Callable[..., object]
PROJECT_ROOT = Path(__file__).resolve().parent.parent
BRIDGE_FILENAME = "libmacos_window_bridge.dylib"


@dataclass(frozen=True)
class MacosLauncherBuildResult:
    launcher_path: Path
    bridge_path: Path


def _python_link_name(python_library: str) -> str:
    library_name = Path(python_library).name.removeprefix("lib")
    return library_name.removesuffix(Path(library_name).suffix)


def launcher_compile_command(
    *,
    python_prefix: Path,
    python_include_dir: Path,
    python_lib_dir: Path,
    python_library: str,
    source_path: Path,
    output_path: Path,
) -> list[str]:
    python_link_name = _python_link_name(python_library)
    return [
        "clang++",
        "-std=c++17",
        "-O2",
        f"-I{python_include_dir}",
        f'-DPYTHON_PREFIX="{python_prefix}"',
        f"-L{python_lib_dir}",
        f"-Wl,-rpath,{python_lib_dir}",
        f"-l{python_link_name}",
        str(source_path),
        "-o",
        str(output_path),
    ]


def _require_compiler() -> None:
    if shutil.which("clang++") is None:
        raise RuntimeError("Build requires clang++ on PATH.")


def _validate_platform(machine: str) -> str:
    if sys.platform != "darwin":
        platform_key(sys.platform, machine)
    if machine.lower() != "arm64":
        platform_key("darwin", machine)
    return platform_key("darwin", machine)


def _require_output(path: Path, label: str) -> None:
    if not path.is_file() or path.stat().st_size == 0:
        raise RuntimeError(f"macOS launcher build did not produce {label}: {path}")


def _require_existing_bridge(path: Path) -> None:
    if not path.is_file() or path.stat().st_size == 0:
        raise RuntimeError(
            "macOS development bridge is missing or empty. "
            "Run `python -m tools.build_macos_bridge` first."
        )


def build_macos_launcher(
    *,
    project_root: Path = PROJECT_ROOT,
    machine: str | None = None,
    runner: CommandRunner | None = None,
) -> MacosLauncherBuildResult:
    project_root = project_root.resolve()
    machine = machine or platform.machine()
    _validate_platform(machine)
    run = runner or subprocess.run
    bridge_path = project_root / "native" / BRIDGE_FILENAME
    launcher_path = project_root / "ArcaeaNapLauncher"
    _require_existing_bridge(bridge_path)
    _require_compiler()

    python_include_dir = sysconfig.get_path("include")
    python_lib_dir = sysconfig.get_config_var("LIBDIR")
    python_library = sysconfig.get_config_var("LDLIBRARY")
    if not python_include_dir or not python_lib_dir or not python_library:
        raise RuntimeError("Active Python is missing launcher compile configuration.")
    command = launcher_compile_command(
        python_prefix=Path(sys.prefix),
        python_include_dir=Path(python_include_dir),
        python_lib_dir=Path(python_lib_dir),
        python_library=python_library,
        source_path=project_root / "native" / "launcher.cpp",
        output_path=launcher_path,
    )
    run(command, cwd=project_root, check=True)
    _require_output(launcher_path, "launcher executable")
    return MacosLauncherBuildResult(
        launcher_path=launcher_path,
        bridge_path=bridge_path,
    )


def main() -> int:
    try:
        result = build_macos_launcher()
    except Exception as exc:
        print(f"[launcher] FAILED: {exc}", file=sys.stderr)
        return 1
    print(result.launcher_path.resolve())
    print(result.bridge_path.resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
