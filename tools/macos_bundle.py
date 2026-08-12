from __future__ import annotations

import glob
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
from typing import Callable


CommandRunner = Callable[..., subprocess.CompletedProcess]
MACOS_DEPLOYMENT_TARGET = "14.0"


def host_macos_sdk_version(runner: CommandRunner | None = None) -> str | None:
    """Return the SDK version used by the host's Xcode command-line tools."""
    run = runner or subprocess.run
    try:
        result = run(
            ["xcrun", "--sdk", "macosx", "--show-sdk-version"],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError:
        return None
    if result.returncode != 0:
        return None
    version = (result.stdout or "").strip()
    return version or None


def promote_macos_ui_metrics(
    bundle_dir: Path,
    sdk_version: str,
    runner: CommandRunner | None = None,
) -> bool:
    """Make the frozen launcher opt into the macOS 26 title-bar metrics.

    cx_Freeze ships a prebuilt macOS base executable compiled with an older
    SDK.  The native bridge is compiled with the host SDK, but AppKit chooses
    the window-control metrics from the application's main executable.  On a
    macOS 26 SDK host, update only that load-command metadata before the final
    ad-hoc signing step.  This keeps the Python/Qt payload unchanged while
    making packaged and development launches use the same title-bar design.
    """
    try:
        major = int(sdk_version.split(".", 1)[0])
    except (AttributeError, ValueError):
        raise RuntimeError(f"Invalid macOS SDK version: {sdk_version!r}") from None
    if major < 26:
        print(f"[bdist_mac] macOS SDK {sdk_version} is older than 26; keeping legacy UI metrics.")
        return False

    executable = bundle_dir / "Contents" / "MacOS" / "ArcaeaNap"
    if not executable.is_file():
        raise RuntimeError(f"macOS app executable not found: {executable}")

    run = runner or subprocess.run
    temporary_fd, temporary_name = tempfile.mkstemp(
        prefix=".ArcaeaNap-sdk-",
        suffix=".tmp",
        dir=executable.parent,
    )
    os.close(temporary_fd)
    temporary = Path(temporary_name)
    temporary.unlink()
    try:
        result = run(
            [
                "vtool",
                "-set-build-version",
                "macos",
                MACOS_DEPLOYMENT_TARGET,
                sdk_version,
                "-output",
                str(temporary),
                str(executable),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0 or not temporary.is_file():
            detail = (result.stderr or "").strip()
            raise RuntimeError(
                "vtool could not update the macOS UI SDK metadata"
                + (f": {detail}" if detail else ".")
            )
        os.replace(temporary, executable)
    finally:
        if temporary.exists():
            temporary.unlink()

    print(f"[bdist_mac] macOS UI SDK metadata set to {sdk_version}: {executable}")
    return True


def _find_actool_dev_dir() -> str | None:
    def has_actool(dev: str | None) -> bool:
        return bool(dev) and os.path.isfile(os.path.join(dev, "usr", "bin", "actool"))

    env_dev = os.environ.get("DEVELOPER_DIR")
    if has_actool(env_dev):
        return env_dev

    candidates: list[tuple[int, str]] = []
    for app in glob.glob("/Applications/Xcode*.app"):
        dev = os.path.join(app, "Contents", "Developer")
        if not has_actool(dev):
            continue
        try:
            with open(os.path.join(app, "Contents", "version.plist"), "rb") as handle:
                version = plistlib.load(handle).get("CFBundleShortVersionString", "")
            major = int(str(version).split(".")[0])
        except (OSError, ValueError, TypeError):
            major = 0
        if major >= 26:
            candidates.append((major, dev))
    return max(candidates, default=(0, None))[1]


def install_liquid_glass_icon(bundle_dir: Path, icon_source: Path, app_icon_name: str) -> bool:
    if not icon_source.is_dir():
        return False
    developer_dir = _find_actool_dev_dir()
    if not developer_dir:
        print("[bdist_mac] Xcode 26+ actool not found; keeping the .icns icon.")
        return False

    resources_dir = bundle_dir / "Contents" / "Resources"
    info_plist = resources_dir.parent / "Info.plist"
    if not resources_dir.is_dir() or not info_plist.is_file():
        print("[bdist_mac] bundle Resources/Info.plist missing; keeping the .icns icon.")
        return False

    temporary_dir = Path(tempfile.mkdtemp(prefix="arcaeanap-icon-"))
    try:
        staged_icon = temporary_dir / f"{app_icon_name}.icon"
        shutil.copytree(icon_source, staged_icon)
        icon_json = staged_icon / "icon.json"
        try:
            spec = json.loads(icon_json.read_text(encoding="utf-8"))
            spec.pop("features", None)
            for group in spec.get("groups", []):
                if isinstance(group, dict):
                    group.pop("specular", None)
            icon_json.write_text(json.dumps(spec, indent=2), encoding="utf-8")
        except (OSError, ValueError) as exc:
            print(f"[bdist_mac] could not sanitize icon.json ({exc}); attempting compile as-is.")

        out_dir = temporary_dir / "out"
        out_dir.mkdir()
        partial_plist = temporary_dir / "partial.plist"
        env = dict(os.environ, DEVELOPER_DIR=developer_dir)
        result = subprocess.run(
            [
                "xcrun", "actool", str(staged_icon), "--compile", str(out_dir),
                "--app-icon", app_icon_name, "--include-all-app-icons",
                "--output-partial-info-plist", str(partial_plist), "--target-device", "mac",
                "--minimum-deployment-target", "26.0", "--platform", "macosx",
            ],
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )
        assets_car = out_dir / "Assets.car"
        if result.returncode != 0 or not assets_car.is_file():
            first_error = result.stderr.strip().splitlines()[0] if result.stderr.strip() else ""
            print(f"[bdist_mac] actool failed; keeping the .icns icon. {first_error}")
            return False

        shutil.copy2(assets_car, resources_dir / "Assets.car")
        icon_name = app_icon_name
        try:
            with partial_plist.open("rb") as handle:
                icon_name = plistlib.load(handle).get("CFBundleIconName", app_icon_name)
        except (OSError, ValueError, TypeError):
            pass
        with info_plist.open("rb") as handle:
            plist = plistlib.load(handle)
        plist["CFBundleIconName"] = icon_name
        with info_plist.open("wb") as handle:
            plistlib.dump(plist, handle)
        print(f"[bdist_mac] Liquid Glass icon installed (CFBundleIconName={icon_name}).")
        return True
    finally:
        shutil.rmtree(temporary_dir, ignore_errors=True)


def adhoc_resign(bundle_dir: Path, runner: CommandRunner | None = None) -> None:
    run = runner or subprocess.run
    if not bundle_dir.is_dir():
        raise RuntimeError(f"macOS bundle not found for re-sign: {bundle_dir}")

    for root, _, files in os.walk(bundle_dir):
        for filename in files:
            if filename.endswith((".dylib", ".so")):
                run(["codesign", "--force", "--sign", "-", os.path.join(root, filename)], check=False, capture_output=True)

    result = run(
        ["codesign", "--force", "--deep", "--sign", "-", str(bundle_dir)],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        detail = getattr(result, "stderr", "") or ""
        raise RuntimeError(f"macOS ad-hoc signing failed: {detail.strip()}")

    verify = run(
        ["codesign", "--verify", "--deep", "--strict", str(bundle_dir)],
        check=False,
        capture_output=True,
        text=True,
    )
    if verify.returncode != 0:
        detail = getattr(verify, "stderr", "") or ""
        raise RuntimeError(f"macOS code signature verification failed: {detail.strip()}")
    print(f"[bdist_mac] ad-hoc signature verified: {bundle_dir}")


def postprocess_macos(bundle_dir: Path, *, icon_source: Path, app_icon_name: str) -> None:
    from .build_postprocess import (
        remove_bundled_playwright_browsers,
        replace_bundled_playwright_app_icons,
    )

    resources_root = bundle_dir / "Contents" / "Resources"
    remove_bundled_playwright_browsers(resources_root)
    replace_bundled_playwright_app_icons(resources_root)
    sdk_version = host_macos_sdk_version()
    if sdk_version:
        promote_macos_ui_metrics(bundle_dir, sdk_version)
    else:
        print("[bdist_mac] macOS SDK version unavailable; keeping legacy UI metrics.")
    install_liquid_glass_icon(bundle_dir, icon_source, app_icon_name)
    adhoc_resign(bundle_dir)
