"""Restore and validate the pinned Windows native build inputs."""

from __future__ import annotations

from dataclasses import dataclass, replace
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import time
from types import MappingProxyType
from typing import BinaryIO, Callable, ContextManager, Mapping
from urllib.parse import urlsplit
import urllib.request
import uuid
import zipfile

from .build_config import windows_native_inputs_dir


_EXPECTED_PACKAGES = {
    "foundation": ("Microsoft.WindowsAppSDK.Foundation", "2.3.5"),
    "interactive": ("Microsoft.WindowsAppSDK.InteractiveExperiences", "2.1.3"),
    "runtime": ("Microsoft.WindowsAppSDK.Runtime", "2.3.1"),
    "cppwinrt": ("Microsoft.Windows.CppWinRT", "2.0.250303.1"),
}
_PROJECTION_METADATA_VERSION = "10.0.17763.0"
_SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")
_REQUIRED_GENERATED_FILES = (
    "Microsoft.Graphics.DirectX.h",
    "Microsoft.Graphics.Display.h",
    "Microsoft.UI.h",
    "Microsoft.UI.Windowing.h",
    "impl/Microsoft.UI.Windowing.2.h",
)
_REQUIRED_PACKAGE_FILES = {
    "foundation": (
        "include/MddBootstrap.h",
        "lib/native/x64/Microsoft.WindowsAppRuntime.Bootstrap.lib",
        "runtimes/win-x64/native/Microsoft.WindowsAppRuntime.Bootstrap.dll",
    ),
    "runtime": ("include/WindowsAppSDK-VersionInfo.h",),
}
_REQUIRED_PACKAGE_DIRECTORIES = {
    "interactive": (
        "include",
        f"metadata/{_PROJECTION_METADATA_VERSION}",
    ),
}
_REPLACE_RETRY_DELAYS = (0.05, 0.1, 0.2, 0.4, 0.8, 1.6, 3.2, 6.4, 12.8)

UrlOpener = Callable[..., ContextManager[BinaryIO]]
CommandRunner = Callable[..., object]


@dataclass(frozen=True)
class PackagePin:
    key: str
    package_id: str
    version: str
    sha256: str


@dataclass(frozen=True)
class WindowsNativeLock:
    packages: Mapping[str, PackagePin]
    projection_metadata_version: str


@dataclass(frozen=True)
class WindowsNativeInputs:
    root: Path
    foundation_root: Path
    interactive_root: Path
    runtime_root: Path
    generated_root: Path
    cppwinrt_root: Path
    cppwinrt_executable: Path
    projection_metadata_version: str


def load_windows_native_lock(path: Path) -> WindowsNativeLock:
    """Read the strict, version-and-hash-pinned input manifest."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise RuntimeError(f"Windows native input lock file is missing: {path}") from exc
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"Cannot read Windows native input lock file {path}: {exc}") from exc
    schema_version = data.get("schema_version") if isinstance(data, dict) else None
    if type(schema_version) is not int or schema_version != 1:
        raise RuntimeError("Windows native input lock has an unsupported schema version.")
    if data.get("projection_metadata_version") != _PROJECTION_METADATA_VERSION:
        raise RuntimeError(
            "Windows native input lock must use projection metadata "
            f"{_PROJECTION_METADATA_VERSION}."
        )
    raw_packages = data.get("packages")
    if not isinstance(raw_packages, dict) or set(raw_packages) != set(_EXPECTED_PACKAGES):
        raise RuntimeError(
            "Windows native input lock must contain exactly the expected package keys."
        )

    packages: dict[str, PackagePin] = {}
    for key, (expected_id, expected_version) in _EXPECTED_PACKAGES.items():
        raw_pin = raw_packages[key]
        if not isinstance(raw_pin, dict):
            raise RuntimeError(f"Windows native input package {key} must be an object.")
        package_id = raw_pin.get("id")
        version = raw_pin.get("version")
        sha256 = raw_pin.get("sha256")
        if (
            not isinstance(package_id, str)
            or not package_id.strip()
            or package_id != expected_id
        ):
            raise RuntimeError(f"Windows native input package {key} has an invalid package ID.")
        if (
            not isinstance(version, str)
            or not version.strip()
            or version != expected_version
        ):
            raise RuntimeError(
                f"Windows native input package {key} has an invalid package version."
            )
        if not isinstance(sha256, str) or not _SHA256_RE.fullmatch(sha256):
            raise RuntimeError(
                f"Windows native input package {key} requires a lowercase SHA-256 digest."
            )
        packages[key] = PackagePin(key, package_id, version, sha256)
    return WindowsNativeLock(MappingProxyType(packages), _PROJECTION_METADATA_VERSION)


def _package_url(pin: PackagePin) -> str:
    package = pin.package_id.casefold()
    version = pin.version.casefold()
    return f"https://api.nuget.org/v3-flatcontainer/{package}/{version}/{package}.{version}.nupkg"


def _marker_matches(package_root: Path, pin: PackagePin) -> bool:
    marker = package_root / ".complete.json"
    if not package_root.is_dir() or not marker.is_file():
        return False
    try:
        value = json.loads(marker.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    expected = {
        "id": pin.package_id,
        "version": pin.version,
        "sha256": pin.sha256,
    }
    if not isinstance(value, dict) or any(value.get(key) != item for key, item in expected.items()):
        return False
    recorded_files = value.get("files")
    return isinstance(recorded_files, list) and recorded_files == _package_file_manifest(
        package_root
    )


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _package_file_manifest(package_root: Path) -> list[dict[str, int | str]] | None:
    """Return the complete extracted-file manifest, rejecting non-regular cache entries."""
    try:
        files: list[dict[str, int | str]] = []
        for path in sorted(package_root.rglob("*"), key=lambda item: item.as_posix()):
            if path.name == ".complete.json":
                continue
            if path.is_symlink():
                return None
            if path.is_dir():
                continue
            if not path.is_file():
                return None
            stat = path.stat()
            files.append(
                {
                    "path": path.relative_to(package_root).as_posix(),
                    "size": stat.st_size,
                    "sha256": _sha256_file(path),
                }
            )
        return files
    except OSError:
        return None


def _package_contents_are_valid(package_root: Path, pin: PackagePin) -> bool:
    if _EXPECTED_PACKAGES.get(pin.key) != (pin.package_id, pin.version):
        return True
    if not all(
        (package_root / relative).is_file()
        for relative in _REQUIRED_PACKAGE_FILES.get(pin.key, ())
    ):
        return False
    if not all(
        (package_root / relative).is_dir()
        for relative in _REQUIRED_PACKAGE_DIRECTORIES.get(pin.key, ())
    ):
        return False
    if pin.key == "cppwinrt":
        return sum(
            path.is_file() and path.name == "cppwinrt.exe"
            for path in package_root.rglob("*")
        ) == 1
    return True


def _unsafe_member(member: str) -> bool:
    normalized = member.replace("\\", "/")
    path = PurePosixPath(normalized)
    return (
        not member
        or path.is_absolute()
        or ".." in path.parts
        or bool(re.match(r"^[A-Za-z]:", normalized))
    )


def safe_extract_nupkg(archive_bytes: bytes, destination: Path) -> None:
    """Extract a NuGet archive after checking every member is destination-safe."""
    try:
        with zipfile.ZipFile(io.BytesIO(archive_bytes)) as archive:
            members = archive.infolist()
            for info in members:
                if _unsafe_member(info.filename):
                    raise RuntimeError(f"unsafe NuGet member: {info.filename}")
            destination.mkdir(parents=True, exist_ok=False)
            for info in members:
                target = destination.joinpath(*PurePosixPath(info.filename).parts)
                if info.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with archive.open(info) as source, target.open("wb") as output:
                        shutil.copyfileobj(source, output)
    except zipfile.BadZipFile as exc:
        raise RuntimeError("Downloaded NuGet package is not a valid ZIP archive.") from exc


def _download_to_part(pin: PackagePin, part_path: Path, opener: UrlOpener) -> bytes:
    with opener(_package_url(pin)) as response, part_path.open("wb") as output:
        final_url_getter = getattr(response, "geturl", None)
        final_url = final_url_getter() if callable(final_url_getter) else _package_url(pin)
        if urlsplit(final_url).scheme.casefold() != "https":
            raise RuntimeError(
                f"NuGet download final URL must use HTTPS, got: {final_url}"
            )
        while chunk := response.read(1024 * 1024):
            output.write(chunk)
    archive = part_path.read_bytes()
    if hashlib.sha256(archive).hexdigest() != pin.sha256:
        raise RuntimeError(f"SHA-256 mismatch for {pin.package_id} {pin.version}.")
    return archive


def _publish_package(temporary_root: Path, package_root: Path) -> None:
    backup_root = package_root.parent / f".{package_root.name}.previous-{uuid.uuid4().hex}"
    had_previous = package_root.exists()
    if had_previous:
        _replace_with_retry(package_root, backup_root)
    try:
        _replace_with_retry(temporary_root, package_root)
    except BaseException as publish_error:
        if had_previous:
            try:
                _replace_with_retry(backup_root, package_root)
            except BaseException as rollback_error:
                publish_error.add_note(
                    "Windows native input rollback failed; previous cache remains at "
                    f"{backup_root}: {rollback_error}"
                )
        raise
    if had_previous:
        shutil.rmtree(backup_root)


def _replace_with_retry(source: Path, destination: Path) -> None:
    for delay in (*_REPLACE_RETRY_DELAYS, None):
        try:
            os.replace(source, destination)
            return
        except PermissionError:
            if delay is None:
                raise
            time.sleep(delay)


def materialize_package(
    pin: PackagePin,
    cache_root: Path,
    opener: UrlOpener = urllib.request.urlopen,
) -> Path:
    """Return one verified package cache entry, downloading it only when needed."""
    cache_root.mkdir(parents=True, exist_ok=True)
    package_root = cache_root / pin.key
    if _marker_matches(package_root, pin) and _package_contents_are_valid(
        package_root, pin
    ):
        return package_root

    part_path = cache_root / f".{pin.key}.{uuid.uuid4().hex}.nupkg.part"
    temporary_root = cache_root / f".{pin.key}.extract-{uuid.uuid4().hex}"
    active_error: BaseException | None = None
    try:
        archive = _download_to_part(pin, part_path, opener)
        safe_extract_nupkg(archive, temporary_root)
        if not _package_contents_are_valid(temporary_root, pin):
            raise RuntimeError(
                f"Windows native input package {pin.package_id} is missing required files."
            )
        manifest = _package_file_manifest(temporary_root)
        if manifest is None:
            raise RuntimeError(
                f"Windows native input package {pin.package_id} has an invalid extracted tree."
            )
        (temporary_root / ".complete.json").write_text(
            json.dumps(
                {
                    "id": pin.package_id,
                    "version": pin.version,
                    "sha256": pin.sha256,
                    "files": manifest,
                },
                sort_keys=True,
            ),
            encoding="utf-8",
        )
        _publish_package(temporary_root, package_root)
        return package_root
    except BaseException as error:
        active_error = error
        raise
    finally:
        cleanup_errors: list[BaseException] = []
        try:
            part_path.unlink(missing_ok=True)
        except BaseException as error:
            cleanup_errors.append(error)
        try:
            if temporary_root.exists():
                shutil.rmtree(temporary_root)
        except BaseException as error:
            cleanup_errors.append(error)
        if cleanup_errors:
            if active_error is None:
                raise cleanup_errors[0]
            for cleanup_error in cleanup_errors:
                active_error.add_note(f"Windows native input cleanup failed: {cleanup_error}")


def _find_cppwinrt_executable(cppwinrt_root: Path) -> Path:
    candidates = [
        path
        for path in cppwinrt_root.rglob("*")
        if path.is_file() and path.name == "cppwinrt.exe"
    ]
    if len(candidates) != 1:
        raise RuntimeError(
            f"Expected exactly one cppwinrt.exe in {cppwinrt_root}; "
            f"found {len(candidates)}."
        )
    return candidates[0]


def _validate_package_inputs(inputs: WindowsNativeInputs) -> None:
    required_files = (
        inputs.foundation_root / "include" / "MddBootstrap.h",
        inputs.foundation_root
        / "lib"
        / "native"
        / "x64"
        / "Microsoft.WindowsAppRuntime.Bootstrap.lib",
        inputs.foundation_root
        / "runtimes"
        / "win-x64"
        / "native"
        / "Microsoft.WindowsAppRuntime.Bootstrap.dll",
        inputs.runtime_root / "include" / "WindowsAppSDK-VersionInfo.h",
        inputs.interactive_root / "include",
        inputs.interactive_root / "metadata" / inputs.projection_metadata_version,
        inputs.cppwinrt_executable,
    )
    missing = [path for path in required_files if not path.exists()]
    if missing:
        raise RuntimeError(
            "Windows native input packages are missing required files: "
            + ", ".join(map(str, missing))
        )


def generate_cppwinrt_projection(
    inputs: WindowsNativeInputs, *, runner: CommandRunner = subprocess.run
) -> None:
    """Generate projection headers with the exact C++/WinRT package pinned in the lock."""
    inputs.generated_root.mkdir(parents=True, exist_ok=True)
    runner(
        [
            str(inputs.cppwinrt_executable),
            "-input",
            str(
                inputs.interactive_root
                / "metadata"
                / inputs.projection_metadata_version
            ),
            "-reference",
            "sdk",
            "-output",
            str(inputs.generated_root),
        ],
        check=True,
    )


def validate_generated_projection(generated_root: Path, generator_version: str) -> None:
    projection_root = generated_root / "winrt"
    missing = [
        projection_root / relative
        for relative in _REQUIRED_GENERATED_FILES
        if not (projection_root / relative).is_file()
    ]
    if missing:
        raise RuntimeError(
            "Generated C++/WinRT projection is missing required headers: "
            + ", ".join(map(str, missing))
        )
    windowing_header = (projection_root / "Microsoft.UI.Windowing.h").read_text(
        encoding="utf-8", errors="replace"
    )
    generated_marker = re.search(
        rf"(?m)^//[^\r\n]*C\+\+/WinRT v{re.escape(generator_version)}\s*$",
        windowing_header,
    )
    version_macro = re.search(
        r'(?m)^\s*#\s*define\s+CPPWINRT_VERSION\s+"([^"]+)"\s*$',
        windowing_header,
    )
    has_version = generated_marker is not None or (
        version_macro is not None and version_macro.group(1) == generator_version
    )
    if not has_version:
        raise RuntimeError(
            "Generated C++/WinRT projection does not declare generator version "
            f"{generator_version}."
        )


def _generate_and_publish_projection(
    inputs: WindowsNativeInputs,
    generator_version: str,
    *,
    runner: CommandRunner,
) -> None:
    temporary_root = inputs.generated_root.parent / (
        f".{inputs.generated_root.name}.generate-{uuid.uuid4().hex}"
    )
    temporary_inputs = replace(inputs, generated_root=temporary_root)
    active_error: BaseException | None = None
    try:
        generate_cppwinrt_projection(temporary_inputs, runner=runner)
        validate_generated_projection(temporary_root, generator_version)
        _publish_package(temporary_root, inputs.generated_root)
    except BaseException as error:
        active_error = error
        raise
    finally:
        try:
            if temporary_root.exists():
                shutil.rmtree(temporary_root)
        except BaseException as cleanup_error:
            if active_error is None:
                raise
            active_error.add_note(
                f"Generated projection cleanup failed: {cleanup_error}"
            )


def prepare_windows_native_inputs(
    *,
    project_root: Path,
    opener: UrlOpener = urllib.request.urlopen,
    runner: CommandRunner = subprocess.run,
) -> WindowsNativeInputs:
    """Restore all locked inputs, generate projections, and validate their build contract."""
    project_root = project_root.resolve()
    lock = load_windows_native_lock(project_root / "native" / "windows-native-inputs.lock.json")
    root = windows_native_inputs_dir(project_root)
    packages_root = root / "packages"
    package_roots = {
        key: materialize_package(pin, packages_root, opener)
        for key, pin in lock.packages.items()
    }
    cppwinrt_executable = _find_cppwinrt_executable(package_roots["cppwinrt"])
    inputs = WindowsNativeInputs(
        root=root,
        foundation_root=package_roots["foundation"],
        interactive_root=package_roots["interactive"],
        runtime_root=package_roots["runtime"],
        generated_root=root / "generated",
        cppwinrt_root=package_roots["cppwinrt"],
        cppwinrt_executable=cppwinrt_executable,
        projection_metadata_version=lock.projection_metadata_version,
    )
    _validate_package_inputs(inputs)
    _generate_and_publish_projection(
        inputs,
        lock.packages["cppwinrt"].version,
        runner=runner,
    )
    return inputs
