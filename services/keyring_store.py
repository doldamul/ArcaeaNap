"""Client-scoped keyring helpers."""
from __future__ import annotations

import keyring

from services.client_identity import get_client_key

KEYRING_SERVICE_NAME = "ArcaeaNap"


def _scoped_key_name(raw_key_name: str, client_key: str | None = None) -> str:
    key = client_key or get_client_key()
    return f"{raw_key_name}::{key}"


def get_secret(raw_key_name: str, client_key: str | None = None) -> str | None:
    return keyring.get_password(KEYRING_SERVICE_NAME, _scoped_key_name(raw_key_name, client_key))


def set_secret(raw_key_name: str, value: str, client_key: str | None = None) -> None:
    keyring.set_password(KEYRING_SERVICE_NAME, _scoped_key_name(raw_key_name, client_key), value)


def delete_secret(raw_key_name: str, client_key: str | None = None) -> None:
    keyring.delete_password(KEYRING_SERVICE_NAME, _scoped_key_name(raw_key_name, client_key))

