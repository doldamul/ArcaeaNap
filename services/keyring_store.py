"""Client-scoped keyring helpers."""
from __future__ import annotations

import json
import sys
import threading

import keyring

from services.client_identity import get_client_key

KEYRING_SERVICE_NAME = "ArcaeaNap"

_backend_cache = None

# ---------------------------------------------------------------------------
# macOS bundle cache — collapses all secrets into a single Keychain item to
# reduce ACL password prompts from ~3-4/session to ~1.
#
# On macOS, secrets are stored as a JSON dict under the account key
# "__bundle__::{client_key}" instead of five separate Keychain items.
# The dict is read once per session (first access) and then kept in memory.
#
# NOTE: Legacy per-item secrets are NOT migrated to the bundle item.
# macOS users will need to re-authenticate once after upgrading so the
# bundle item can be populated from scratch.
# ---------------------------------------------------------------------------
_bundle_cache: dict | None = None
_bundle_cache_key: str | None = None   # which client_key the cached bundle belongs to
_bundle_lock = threading.Lock()


def _get_backend():
    global _backend_cache
    if _backend_cache is not None:
        return _backend_cache

    import platform

    # cx_Freeze 빌드된 환경에서는 keyring의 자동 백엔드 검색(importlib.metadata 사용)이
    # 오동작하여 TypeError를 유발하므로 직접 백엔드를 생성하여 사용한다.
    if getattr(sys, 'frozen', False):
        if platform.system() == "Windows":
            try:
                from keyring.backends.Windows import WinVaultKeyring
                _backend_cache = WinVaultKeyring()
                return _backend_cache
            except Exception:
                pass
        elif platform.system() == "Darwin":
            try:
                from keyring.backends.macOS import Keyring
                _backend_cache = Keyring()
                return _backend_cache
            except Exception:
                pass

    _backend_cache = keyring
    return _backend_cache


def _scoped_key_name(raw_key_name: str, client_key: str | None = None) -> str:
    key = client_key or get_client_key()
    return f"{raw_key_name}::{key}"


# --- macOS bundle helpers (must be called with _bundle_lock held) ----------

def _load_bundle(resolved_key: str) -> dict:
    """Return the in-memory bundle dict, loading from Keychain on first call.

    Reads from the Keychain at most once per session (or when resolved_key
    changes), so subsequent calls never trigger an additional ACL prompt.

    MUST be called with _bundle_lock held.
    """
    global _bundle_cache, _bundle_cache_key
    if _bundle_cache is None or _bundle_cache_key != resolved_key:
        raw = _get_backend().get_password(KEYRING_SERVICE_NAME, f"__bundle__::{resolved_key}")
        if raw:
            try:
                loaded = json.loads(raw)
            except (json.JSONDecodeError, TypeError):
                # Corrupt/foreign value: don't crash the app on first secret access.
                # Fall back to empty; it will be overwritten on the next save.
                print("[keyring_store] Corrupt bundle value; resetting to empty.")
                loaded = {}
            _bundle_cache = loaded if isinstance(loaded, dict) else {}
        else:
            _bundle_cache = {}
        _bundle_cache_key = resolved_key
    return _bundle_cache


def _save_bundle(resolved_key: str) -> None:
    """Persist the in-memory bundle dict to the Keychain (write-through).

    MUST be called with _bundle_lock held.
    """
    _get_backend().set_password(
        KEYRING_SERVICE_NAME,
        f"__bundle__::{resolved_key}",
        json.dumps(_bundle_cache, ensure_ascii=False),
    )


# --- Public API ------------------------------------------------------------

def get_secret(raw_key_name: str, client_key: str | None = None) -> str | None:
    if sys.platform == "darwin":
        resolved_key = client_key or get_client_key()
        with _bundle_lock:
            return _load_bundle(resolved_key).get(raw_key_name)
    return _get_backend().get_password(KEYRING_SERVICE_NAME, _scoped_key_name(raw_key_name, client_key))


def set_secret(raw_key_name: str, value: str, client_key: str | None = None) -> None:
    if sys.platform == "darwin":
        resolved_key = client_key or get_client_key()
        with _bundle_lock:
            _load_bundle(resolved_key)[raw_key_name] = value
            _save_bundle(resolved_key)
        return
    _get_backend().set_password(KEYRING_SERVICE_NAME, _scoped_key_name(raw_key_name, client_key), value)


def delete_secret(raw_key_name: str, client_key: str | None = None) -> None:
    if sys.platform == "darwin":
        resolved_key = client_key or get_client_key()
        with _bundle_lock:
            _load_bundle(resolved_key).pop(raw_key_name, None)
            _save_bundle(resolved_key)
        return
    _get_backend().delete_password(KEYRING_SERVICE_NAME, _scoped_key_name(raw_key_name, client_key))
