"""Client-scoped keyring helpers."""
from __future__ import annotations

import keyring

from services.client_identity import get_client_key

KEYRING_SERVICE_NAME = "ArcaeaNap"

_backend_cache = None

def _get_backend():
    global _backend_cache
    if _backend_cache is not None:
        return _backend_cache
        
    import sys
    import platform
    
    # cx_Freeze 빌드된 Windows 환경에서는 keyring의 자동 백엔드 검색(importlib.metadata 사용)이 
    # 오동작하여 TypeError를 유발하므로 직접 백엔드를 생성하여 사용한다.
    if getattr(sys, 'frozen', False) and platform.system() == "Windows":
        try:
            from keyring.backends.Windows import WinVaultKeyring
            _backend_cache = WinVaultKeyring()
            return _backend_cache
        except Exception:
            pass
            
    _backend_cache = keyring
    return _backend_cache


def _scoped_key_name(raw_key_name: str, client_key: str | None = None) -> str:
    key = client_key or get_client_key()
    return f"{raw_key_name}::{key}"


def get_secret(raw_key_name: str, client_key: str | None = None) -> str | None:
    return _get_backend().get_password(KEYRING_SERVICE_NAME, _scoped_key_name(raw_key_name, client_key))


def set_secret(raw_key_name: str, value: str, client_key: str | None = None) -> None:
    _get_backend().set_password(KEYRING_SERVICE_NAME, _scoped_key_name(raw_key_name, client_key), value)


def delete_secret(raw_key_name: str, client_key: str | None = None) -> None:
    _get_backend().delete_password(KEYRING_SERVICE_NAME, _scoped_key_name(raw_key_name, client_key))

