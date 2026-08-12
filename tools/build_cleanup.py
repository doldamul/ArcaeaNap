from __future__ import annotations

from pathlib import Path
import shutil

from .build_config import native_build_dir, native_stage_dir


def _reject_symlink_components(*, path: Path, project_root: Path) -> None:
    current = project_root
    for component in path.relative_to(project_root).parts:
        current /= component
        if current.is_symlink():
            raise RuntimeError(f"Refusing to clean symlink native build output path: {current}")


def validate_native_output_path(
    *, path: Path, expected_parent: Path, project_root: Path
) -> Path:
    try:
        path.relative_to(project_root)
    except ValueError as error:
        raise RuntimeError(
            f"Refusing to clean native build output outside {project_root}: {path}"
        ) from error
    _reject_symlink_components(path=path, project_root=project_root)
    resolved_path = path.resolve()
    if resolved_path.parent != expected_parent.resolve():
        raise RuntimeError(
            f"Refusing to clean native build output outside {expected_parent}: {resolved_path}"
        )
    return resolved_path


def _remove_target_directory(
    *, path: Path, expected_parent: Path, project_root: Path
) -> None:
    resolved_path = validate_native_output_path(
        path=path,
        expected_parent=expected_parent,
        project_root=project_root,
    )
    if not resolved_path.exists():
        return
    if not resolved_path.is_dir():
        raise RuntimeError(f"{resolved_path}: native build output is not a directory")
    shutil.rmtree(resolved_path)


def _remove_empty_directory(
    *, path: Path, expected_parent: Path, project_root: Path
) -> None:
    resolved_path = validate_native_output_path(
        path=path,
        expected_parent=expected_parent,
        project_root=project_root,
    )
    if not resolved_path.exists():
        return
    if not resolved_path.is_dir():
        raise RuntimeError(f"{resolved_path}: build output is not a directory")
    if any(resolved_path.iterdir()):
        return
    resolved_path.rmdir()


def cleanup_native_build_outputs(*, project_root: Path, target: str) -> None:
    project_root = project_root.resolve()
    build_root = project_root / "build" / "native"
    stage_root = project_root / "build" / "native-stage"
    _remove_target_directory(
        path=native_build_dir(project_root, target),
        expected_parent=build_root,
        project_root=project_root,
    )
    _remove_target_directory(
        path=native_stage_dir(project_root, target),
        expected_parent=stage_root,
        project_root=project_root,
    )
    _remove_empty_directory(
        path=build_root,
        expected_parent=project_root / "build",
        project_root=project_root,
    )
    _remove_empty_directory(
        path=stage_root,
        expected_parent=project_root / "build",
        project_root=project_root,
    )


def cleanup_macos_cxfreeze_outputs(*, project_root: Path) -> None:
    project_root = project_root.resolve()
    build_root = project_root / "build"
    _reject_symlink_components(path=build_root, project_root=project_root)
    if not build_root.exists():
        return
    if not build_root.is_dir():
        raise RuntimeError(f"{build_root}: build output root is not a directory")
    for path in build_root.glob("exe.macosx-*"):
        _remove_target_directory(
            path=path,
            expected_parent=build_root,
            project_root=project_root,
        )
