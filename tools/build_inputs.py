from __future__ import annotations

from contextlib import contextmanager
import json
from pathlib import Path
import os
import re
import tempfile
from typing import Iterator


def load_client_values(client_secret_path: Path) -> list[str]:
    try:
        with client_secret_path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except FileNotFoundError as exc:
        raise RuntimeError(
            f"Build requires {client_secret_path}. Provide a real client_secret.json before building."
        ) from exc
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Build requires valid JSON in {client_secret_path}.") from exc
    except OSError as exc:
        raise RuntimeError(f"Build cannot read {client_secret_path}: {exc}") from exc

    if not isinstance(data, dict):
        raise RuntimeError(f"Build requires a JSON object in {client_secret_path}.")

    installed = data.get("installed", data.get("web", {}))
    if not isinstance(installed, dict):
        raise RuntimeError("Build requires installed/web object in client_secret.json.")

    values = [
        str(installed.get("api_key", data.get("api_key", ""))).strip(),
        str(installed.get("client_id", "")).strip(),
        str(installed.get("client_secret", "")).strip(),
    ]
    if not all(values):
        raise RuntimeError(
            "Build requires non-empty api_key/client_id/client_secret values in client_secret.json."
        )
    return values


def _atomic_write(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, path)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)


@contextmanager
def prepared_build_inputs(
    *,
    consultant_path: Path,
    build_info_path: Path,
    values: list[str],
    app_title: str,
    app_version: str,
    timestamp: float,
) -> Iterator[None]:
    original_consultant = consultant_path.read_bytes()
    original_build_info = build_info_path.read_bytes()
    try:
        consultant_text = original_consultant.decode("utf-8")
        block = (
            "# CLIENT_CONST_BEGIN\n"
            f"CLIENT = {json.dumps(values, ensure_ascii=False)}  # [0]: key, [1]: id, [2]: sec\n"
            "# CLIENT_CONST_END"
        )
        patched = re.sub(
            r"# CLIENT_CONST_BEGIN\r?\n.*?\r?\n# CLIENT_CONST_END",
            block,
            consultant_text,
            count=1,
            flags=re.DOTALL,
        )
        if patched == consultant_text:
            raise RuntimeError("CLIENT constant block not found in utils/web_consultantsheet.py.")

        build_info = (
            '"""Auto-generated build information. Do not edit manually."""\n\n'
            f'APP_TITLE = "{app_title}"\n'
            f'APP_VERSION = "{app_version}"\n'
            f"BUILD_TIMESTAMP = {timestamp}\n"
        )
        _atomic_write(consultant_path, patched.encode("utf-8"))
        _atomic_write(build_info_path, build_info.encode("utf-8"))
        yield
    finally:
        _atomic_write(consultant_path, original_consultant)
        _atomic_write(build_info_path, original_build_info)
