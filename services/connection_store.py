"""Client-scoped account connection store."""
from __future__ import annotations

import copy
import json
import os
import uuid
from typing import Any

from utils.configuration import config
from services.client_identity import get_client_key

STORE_FILENAME = "account_connections.json"
STORE_VERSION = 2


def _store_path() -> str:
    return os.path.join(config["general"]["cache_path"], STORE_FILENAME)


def _empty_store() -> dict[str, Any]:
    return {
        "version": STORE_VERSION,
        "clients": {},
    }


def _validate_store_structure(store: dict[str, Any]) -> None:
    if not isinstance(store, dict):
        raise RuntimeError("account_connections.json must contain a JSON object")

    version = store.get("version")
    clients = store.get("clients")

    if version != STORE_VERSION:
        raise RuntimeError(
            f"Unsupported account_connections.json version: {version} (expected {STORE_VERSION}). "
            "Delete the file and restart to initialize a new store."
        )
    if not isinstance(clients, dict):
        raise RuntimeError("account_connections.json 'clients' must be an object")


def _atomic_write_json(path: str, payload: dict[str, Any]) -> None:
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    tmp_path = f"{path}.{os.getpid()}.{uuid.uuid4().hex}.tmp"

    try:
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
            f.flush()
            os.fsync(f.fileno())

        os.replace(tmp_path, path)
    finally:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass


def load_store() -> dict[str, Any]:
    path = _store_path()
    if not os.path.exists(path):
        return _empty_store()

    try:
        with open(path, "r", encoding="utf-8") as f:
            payload = json.load(f)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"Invalid JSON in account connection store: {e}") from e

    _validate_store_structure(payload)
    return payload


def save_store(store: dict[str, Any]) -> None:
    _validate_store_structure(store)
    _atomic_write_json(_store_path(), store)


def load_client_connections(client_key: str | None = None) -> dict[str, Any]:
    key = client_key or get_client_key()
    store = load_store()

    connections = store["clients"].get(key, {})
    if not isinstance(connections, dict):
        return {}
    return copy.deepcopy(connections)


def save_client_connections(connections: dict[str, Any], client_key: str | None = None) -> None:
    if not isinstance(connections, dict):
        raise TypeError("connections must be a dict")

    key = client_key or get_client_key()
    store = load_store()
    store["clients"][key] = copy.deepcopy(connections)
    save_store(store)


def get_provider(provider: str, client_key: str | None = None) -> dict[str, Any]:
    connections = load_client_connections(client_key)
    provider_data = connections.get(provider, {})
    if not isinstance(provider_data, dict):
        return {}
    return copy.deepcopy(provider_data)


def set_provider(provider: str, provider_data: dict[str, Any], client_key: str | None = None) -> None:
    if not isinstance(provider_data, dict):
        raise TypeError("provider_data must be a dict")

    connections = load_client_connections(client_key)
    connections[provider] = copy.deepcopy(provider_data)
    save_client_connections(connections, client_key)


def remove_provider(provider: str, client_key: str | None = None) -> None:
    connections = load_client_connections(client_key)
    if provider in connections:
        del connections[provider]
        save_client_connections(connections, client_key)

