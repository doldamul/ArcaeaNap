"""Per-user writable data directory resolution (macOS only; others keep legacy)."""
from __future__ import annotations
import os
import sys

APP_NAME = "ArcaeaNap"


def get_user_data_dir() -> str | None:
    """Return the writable per-user data directory for config/cache/browsers.

    macOS: ~/Library/Application Support/ArcaeaNap (created if missing).
    Windows/Linux: None  -> callers keep existing CWD/package-relative behavior.
    """
    if sys.platform == "darwin":
        path = os.path.join(
            os.path.expanduser("~/Library/Application Support"), APP_NAME
        )
        os.makedirs(path, exist_ok=True)
        return path
    return None
