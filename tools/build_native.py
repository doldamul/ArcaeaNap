from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import subprocess
import shutil
from typing import Callable, Sequence

from .build_cleanup import validate_native_output_path
from .build_config import (
    BridgeArtifact,
    expected_bridge_artifacts,
    native_build_dir,
    native_stage_dir,
    platform_key,
)
from .windows_native_inputs import prepare_windows_native_inputs


CommandRunner = Callable[..., object]


@dataclass(frozen=True)
class NativeBuildResult:
    target: str
    build_dir: Path
    stage_dir: Path
    artifacts: tuple[Path, ...]


def native_command_sequence(
    *,
    source_dir: Path,
    build_dir: Path,
    stage_dir: Path,
    preset: str,
    target: str,
    configure_definitions: Sequence[str] = (),
) -> list[list[str]]:
    del source_dir
    build_path = Path(build_dir).as_posix()
    stage_path = Path(stage_dir).as_posix()
    return [
        ["cmake", "--preset", preset, *configure_definitions],
        ["cmake", "--build", build_path, "--config", "Release", "--target", target],
        [
            "cmake",
            "--install",
            build_path,
            "--config",
            "Release",
            "--prefix",
            stage_path,
        ],
    ]


def build_native_bridge(
    *,
    project_root: Path,
    platform_name: str,
    machine: str,
    runner: CommandRunner | None = None,
) -> NativeBuildResult:
    project_root = project_root.resolve()
    target = platform_key(platform_name, machine)
    source_dir = project_root / "native"
    build_dir = native_build_dir(project_root, target)
    stage_dir = native_stage_dir(project_root, target)
    build_dir = validate_native_output_path(
        path=build_dir,
        expected_parent=project_root / "build" / "native",
        project_root=project_root,
    )
    stage_dir = validate_native_output_path(
        path=stage_dir,
        expected_parent=project_root / "build" / "native-stage",
        project_root=project_root,
    )
    preset = "windows-release" if target == "windows-x64" else "macos-release"
    cmake_target = "appwindow_titlebar_bridge" if target == "windows-x64" else "macos_window_bridge"
    run = runner or subprocess.run
    configure_definitions: tuple[str, ...] = ()
    if target == "windows-x64":
        windows_inputs = prepare_windows_native_inputs(
            project_root=project_root,
            runner=run,
        )
        configure_definitions = (
            f"-DWINDOWS_NATIVE_INPUT_ROOT={windows_inputs.root.as_posix()}",
        )
    commands = native_command_sequence(
        source_dir=source_dir,
        build_dir=build_dir,
        stage_dir=stage_dir,
        preset=preset,
        target=cmake_target,
        configure_definitions=configure_definitions,
    )
    stage_dir.mkdir(parents=True, exist_ok=True)
    for child in stage_dir.iterdir():
        if child.is_dir():
            shutil.rmtree(child)
        else:
            child.unlink()
    for command in commands:
        run(command, cwd=source_dir, check=True)

    artifacts = tuple(stage_dir / item.source for item in expected_bridge_artifacts(target))
    missing = [path for path in artifacts if not path.is_file() or path.stat().st_size == 0]
    if missing:
        missing_text = ", ".join(str(path) for path in missing)
        raise RuntimeError(f"Native bridge install completed without required artifacts: {missing_text}")
    expected_files = set(artifacts)
    unexpected = [
        path for path in stage_dir.rglob("*")
        if path.is_file() and path not in expected_files
    ]
    if unexpected:
        unexpected_text = ", ".join(str(path) for path in unexpected)
        raise RuntimeError(f"Native bridge staging contains unexpected files: {unexpected_text}")
    return NativeBuildResult(target, build_dir, stage_dir, artifacts)
