from __future__ import annotations

from collections.abc import Sequence
import os
from pathlib import Path
import shutil
import tempfile


def install_development_bridge(*, source: Path, destination: Path) -> None:
    install_development_bridges(artifacts=((source, destination),))


def install_development_bridges(
    *, artifacts: Sequence[tuple[Path, Path]]
) -> None:
    pairs = tuple((Path(source), Path(destination)) for source, destination in artifacts)
    for source, destination in pairs:
        if not source.is_file() or source.stat().st_size == 0:
            raise RuntimeError(f"Development bridge source is missing or empty: {source}")
        destination.parent.mkdir(parents=True, exist_ok=True)

    temporary_paths: list[Path] = []
    backup_paths: list[tuple[Path, Path]] = []
    installed_destinations: list[Path] = []
    try:
        for source, destination in pairs:
            temporary_path = _create_temporary_path(destination.parent, suffix=".tmp")
            shutil.copy2(source, temporary_path)
            temporary_paths.append(temporary_path)

        for _, destination in pairs:
            if not destination.exists():
                continue
            backup_path = _create_temporary_path(destination.parent, suffix=".bak")
            backup_paths.append((destination, backup_path))
            os.replace(destination, backup_path)

        for temporary_path, (_, destination) in zip(temporary_paths, pairs):
            os.replace(temporary_path, destination)
            installed_destinations.append(destination)

        for _, backup_path in backup_paths:
            backup_path.unlink(missing_ok=True)
    except BaseException as error:
        try:
            for destination in installed_destinations:
                destination.unlink(missing_ok=True)
            for destination, backup_path in reversed(backup_paths):
                if backup_path.exists():
                    os.replace(backup_path, destination)
        except BaseException as rollback_error:
            error.add_note(f"Development bridge rollback failed: {rollback_error}")
        raise
    finally:
        for temporary_path in temporary_paths:
            temporary_path.unlink(missing_ok=True)
        for _, backup_path in backup_paths:
            backup_path.unlink(missing_ok=True)


def _create_temporary_path(directory: Path, *, suffix: str) -> Path:
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=".", suffix=suffix, dir=directory
    )
    os.close(descriptor)
    temporary_path = Path(temporary_name)
    temporary_path.unlink(missing_ok=True)
    return temporary_path
