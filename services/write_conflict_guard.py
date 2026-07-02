"""Best-effort write conflict detection for shared cache usage."""
from __future__ import annotations

import json
import os
import socket
import time
import uuid
from dataclasses import dataclass

from utils.configuration import config, get_cache_dir
from services.client_identity import get_client_key

SESSION_ID = uuid.uuid4().hex
DEFAULT_ACTIVE_WINDOW_SECONDS = 120


@dataclass(frozen=True)
class WriteConflictInfo:
    target: str
    operation: str
    client_key: str
    hostname: str
    updated_at: int
    age_seconds: float


def _marker_path(target: str) -> str:
    safe_target = "".join(ch if ch.isalnum() or ch in ("-", "_") else "_" for ch in target)
    filename = f".write_activity_{safe_target}.json"
    return os.path.join(get_cache_dir(), filename)


def _marker_candidates(target: str) -> list[str]:
    directory = get_cache_dir()
    safe_target = "".join(ch if ch.isalnum() or ch in ("-", "_") else "_" for ch in target)
    marker_basename = f".write_activity_{safe_target}"

    try:
        entries = os.listdir(directory)
    except OSError:
        return []

    candidates: list[str] = []
    for entry in entries:
        if marker_basename not in entry:
            continue

        path = os.path.join(directory, entry)
        if os.path.isfile(path):
            candidates.append(path)
    return candidates


def _atomic_write_json(path: str, payload: dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp_path = f"{path}.{os.getpid()}.tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
        f.flush()
        os.fsync(f.fileno())
    # Retry os.replace with backoff (Dropbox/OneDrive may lock the target)
    for attempt in range(3):
        try:
            os.replace(tmp_path, path)
            return
        except OSError:
            if attempt < 2:
                time.sleep(0.1 * (attempt + 1))
    # Final fallback: direct write (non-atomic but functional)
    try:
        os.remove(tmp_path)
    except OSError:
        pass
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)


def _log_marker_io_failure(action: str, target: str, error: Exception) -> None:
    print(f"[write_conflict_guard] {action} failed for '{target}': {error}")


def mark_write_activity(target: str, operation: str) -> None:
    try:
        now = int(time.time())
        payload = {
            "target": target,
            "operation": operation,
            "client_key": get_client_key(),
            "session_id": SESSION_ID,
            "hostname": socket.gethostname(),
            "updated_at": now,
        }
        _atomic_write_json(_marker_path(target), payload)
    except Exception as e:
        _log_marker_io_failure("mark_write_activity", target, e)


def clear_write_activity(target: str) -> None:
    try:
        canonical_path = _marker_path(target)
        for path in _marker_candidates(target):
            if path == canonical_path:
                try:
                    with open(path, "r", encoding="utf-8") as f:
                        payload = json.load(f)
                except Exception:
                    continue

                if (
                    payload.get("client_key") == get_client_key()
                    and payload.get("session_id") == SESSION_ID
                ):
                    try:
                        os.remove(path)
                    except OSError:
                        pass
                continue

            try:
                os.remove(path)
            except OSError:
                pass
    except Exception as e:
        _log_marker_io_failure("clear_write_activity", target, e)
        return


def detect_recent_external_activity(
    target: str,
    active_window_seconds: int = DEFAULT_ACTIVE_WINDOW_SECONDS,
) -> WriteConflictInfo | None:
    try:
        path = _marker_path(target)
        if not os.path.exists(path):
            return None

        try:
            with open(path, "r", encoding="utf-8") as f:
                payload = json.load(f)
        except Exception:
            return None

        updated_at = payload.get("updated_at")
        client_key = payload.get("client_key")
        session_id = payload.get("session_id")
        operation = payload.get("operation", "")

        if not isinstance(updated_at, int) or not isinstance(client_key, str):
            return None

        if client_key == get_client_key() and session_id == SESSION_ID:
            return None

        age_seconds = time.time() - updated_at
        if age_seconds < 0 or age_seconds > active_window_seconds:
            return None

        return WriteConflictInfo(
            target=target,
            operation=str(operation),
            client_key=client_key,
            hostname=str(payload.get("hostname", "unknown")),
            updated_at=updated_at,
            age_seconds=age_seconds,
        )
    except Exception as e:
        _log_marker_io_failure("detect_recent_external_activity", target, e)
        return None

