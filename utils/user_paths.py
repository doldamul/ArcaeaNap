"""Per-user writable data directory resolution (macOS only; others keep legacy)."""
from __future__ import annotations
import os
import sys

APP_NAME = "ArcaeaNap"


def get_user_data_dir() -> str | None:
    """Return the writable per-user data directory for config/cache/browsers.

    Only the **frozen macOS app** needs this: mutable data cannot live inside the
    read-only/signed .app bundle, so it goes to ~/Library/Application Support/ArcaeaNap
    (created if missing).

    Everywhere else — **macOS development (non-frozen)**, Windows, Linux — returns
    None so callers use the app-root/package-relative location (data alongside the
    project/install, i.e. the normal dev behavior).
    """
    if sys.platform == "darwin" and getattr(sys, "frozen", False):
        path = os.path.join(
            os.path.expanduser("~/Library/Application Support"), APP_NAME
        )
        os.makedirs(path, exist_ok=True)
        return path
    return None


def get_app_root() -> str:
    """Application base directory (CWD-independent), Qt-free.

    frozen: the executable's directory (install folder);
    dev: the repository root (parent of utils/).
    Used as the base for resolving './'-relative paths on non-macOS so that
    cache/config live next to the app, not relative to a volatile CWD or __file__."""
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
