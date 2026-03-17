"""Stable per-machine client identity helpers."""
from __future__ import annotations

import hashlib
import os
import platform
import re
import subprocess
from functools import lru_cache

CLIENT_KEY_NAMESPACE = "ArcaeaNap::client_key::v1"


def _read_windows_machine_guid() -> str:
    import winreg

    key_path = r"SOFTWARE\Microsoft\Cryptography"
    access_candidates = [winreg.KEY_READ]
    if hasattr(winreg, "KEY_WOW64_64KEY"):
        access_candidates.insert(0, winreg.KEY_READ | winreg.KEY_WOW64_64KEY)

    last_error = None
    for access in access_candidates:
        try:
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, key_path, 0, access) as key:
                value, _ = winreg.QueryValueEx(key, "MachineGuid")
                machine_guid = str(value or "").strip()
                if machine_guid:
                    return machine_guid
        except OSError as e:
            last_error = e

    raise RuntimeError(f"Failed to read Windows MachineGuid: {last_error}")


def _read_macos_platform_uuid() -> str:
    proc = subprocess.run(
        ["ioreg", "-rd1", "-c", "IOPlatformExpertDevice"],
        check=True,
        capture_output=True,
        text=True,
        timeout=5,
    )
    match = re.search(r'"IOPlatformUUID"\s*=\s*"([^"]+)"', proc.stdout or "")
    if not match:
        raise RuntimeError("IOPlatformUUID not found in ioreg output")
    return match.group(1).strip()


def _read_linux_machine_id() -> str:
    candidates = [
        "/etc/machine-id",
        "/var/lib/dbus/machine-id",
    ]
    for path in candidates:
        if not os.path.exists(path):
            continue
        with open(path, "r", encoding="utf-8") as f:
            machine_id = f.read().strip()
        if machine_id:
            return machine_id
    raise RuntimeError("Linux machine-id not found")


def _read_raw_machine_id() -> str:
    system = platform.system().lower()
    if system == "windows":
        return _read_windows_machine_guid()
    if system == "darwin":
        return _read_macos_platform_uuid()
    if system == "linux":
        return _read_linux_machine_id()
    raise RuntimeError(f"Unsupported platform for client key: {platform.system()}")


@lru_cache(maxsize=1)
def get_client_key() -> str:
    """Return deterministic client key derived from machine identity."""
    raw_machine_id = _read_raw_machine_id()
    normalized = raw_machine_id.strip().lower()
    if not normalized:
        raise RuntimeError("Machine identity is empty")

    digest_source = f"{CLIENT_KEY_NAMESPACE}:{normalized}".encode("utf-8")
    return hashlib.sha256(digest_source).hexdigest()

