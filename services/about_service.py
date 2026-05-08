"""About window metadata and repository link helpers."""

from __future__ import annotations

import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

from utils import app_build_info

APP_TITLE = app_build_info.APP_TITLE
APP_VERSION = app_build_info.APP_VERSION
APP_LICENSE = "GNU GPL v3.0"
DEFAULT_REPOSITORY_URL = "https://github.com/doldamul/ArcaeaNap"

OPEN_SOURCE_ITEMS = [
    {
        "name": "PyQt6",
        "url": "https://www.riverbankcomputing.com/software/pyqt/",
        "license": "GPL-3.0",
        "copyright": "Riverbank Computing Limited and contributors",
        "license_file": "gpl-3.0.txt",
    },
    {
        "name": "Playwright",
        "url": "https://playwright.dev/python/",
        "license": "Apache-2.0",
        "copyright": "Microsoft Corporation",
        "license_file": "apache-2.0.txt",
    },
    {
        "name": "requests",
        "url": "https://requests.readthedocs.io/",
        "license": "Apache-2.0",
        "copyright": "Kenneth Reitz and contributors",
        "license_file": "apache-2.0.txt",
    },
    {
        "name": "Beautiful Soup 4",
        "url": "https://www.crummy.com/software/BeautifulSoup/bs4/doc/",
        "license": "MIT",
        "copyright": "Leonard Richardson",
        "license_file": "mit.txt",
    },
    {
        "name": "gspread",
        "url": "https://github.com/burnash/gspread",
        "license": "MIT",
        "copyright": "Anton Burnash and contributors",
        "license_file": "mit.txt",
    },
    {
        "name": "google-auth",
        "url": "https://github.com/googleapis/google-auth-library-python",
        "license": "Apache-2.0",
        "copyright": "Google LLC",
        "license_file": "apache-2.0.txt",
    },
    {
        "name": "google-auth-oauthlib",
        "url": "https://github.com/googleapis/google-auth-library-python-oauthlib",
        "license": "Apache-2.0",
        "copyright": "Google LLC",
        "license_file": "apache-2.0.txt",
    },
    {
        "name": "google-api-python-client",
        "url": "https://github.com/googleapis/google-api-python-client",
        "license": "Apache-2.0",
        "copyright": "Google LLC",
        "license_file": "apache-2.0.txt",
    },
    {
        "name": "keyring",
        "url": "https://github.com/jaraco/keyring",
        "license": "MIT",
        "copyright": "Jason R. Coombs and contributors",
        "license_file": "mit.txt",
    },
    {
        "name": "win32ctypes",
        "url": "https://github.com/enthought/pywin32-ctypes",
        "license": "BSD-3-Clause",
        "copyright": "Enthought, Inc.",
        "license_file": "win32ctypes.txt",
    },
]


def _find_license_file(filename: str, roots: list[Path] | None = None) -> Path:
    if roots is None:
        roots = [
            Path(__file__).resolve().parents[1],
            Path(sys.executable).resolve().parent,
            Path.cwd(),
        ]

    for root in roots:
        base = Path(root).resolve()
        for candidate_root in [base, *base.parents]:
            candidate = candidate_root / "resources" / "licenses" / filename
            if candidate.is_file():
                return candidate

    raise FileNotFoundError(f"Missing license text file: {roots[0] / 'resources' / 'licenses' / filename}")


def _read_license_text(filename: str, copyright_owner: str) -> str:
    path = _find_license_file(filename)
    text = path.read_text(encoding="utf-8").strip()

    # Placeholder replacement (Year 2026 based on session context)
    replacements = {
        "<year>": "2026",
        "[yyyy]": "2026",
        "<owner>": copyright_owner,
        "<copyright holders>": copyright_owner,
        "[name of copyright owner]": copyright_owner,
    }
    for old, new in replacements.items():
        text = text.replace(old, new)
    return text


def _build_open_source_items() -> list[dict[str, str]]:
    items: list[dict[str, str]] = []
    for item in OPEN_SOURCE_ITEMS:
        license_text = _read_license_text(item["license_file"], item["copyright"])
        mapped = dict(item)
        mapped["license_text"] = license_text
        items.append(mapped)
    return items


def normalize_repository_url(raw_url: str) -> str:
    value = (raw_url or "").strip()
    if not value:
        return ""

    if value.startswith("git@github.com:"):
        repo = value[len("git@github.com:") :]
        if repo.endswith(".git"):
            repo = repo[:-4]
        return f"https://github.com/{repo}"

    if value.startswith("https://") or value.startswith("http://"):
        return value[:-4] if value.endswith(".git") else value

    return value


def _read_remote_origin_url(repo_root: str) -> str:
    result = subprocess.run(
        ["git", "--no-pager", "config", "--get", "remote.origin.url"],
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
    )
    return result.stdout.strip()


def resolve_repository_url(repo_root: str, default_url: str = DEFAULT_REPOSITORY_URL) -> str:
    try:
        remote_url = _read_remote_origin_url(repo_root)
    except Exception:
        remote_url = ""

    normalized = normalize_repository_url(remote_url)
    return normalized or default_url


def _get_build_date() -> str:
    if not getattr(sys, "frozen", False):
        return datetime.now().strftime("%Y-%m-%d %H:%M:%S") + " (debug)"

    # Frozen mode: use stored build timestamp
    if app_build_info.BUILD_TIMESTAMP > 0:
        return datetime.fromtimestamp(app_build_info.BUILD_TIMESTAMP).strftime("%Y-%m-%d %H:%M:%S")

    return "Unknown"


def build_about_context(repo_root: str) -> dict[str, Any]:
    safe_repo_root = repo_root if repo_root and os.path.isdir(repo_root) else os.getcwd()
    return {
        "appTitle": APP_TITLE,
        "appVersion": APP_VERSION,
        "appLicense": APP_LICENSE,
        "repositoryUrl": resolve_repository_url(safe_repo_root),
        "websiteUrl": "https://doldamul.github.io/ArcaeaNap",
        "privacyPolicyUrl": "https://doldamul.github.io/ArcaeaNap/privacy_policy",
        "termsOfServiceUrl": "https://doldamul.github.io/ArcaeaNap/terms_of_service",
        "openSourceItems": _build_open_source_items(),
        "buildDate": _get_build_date(),
    }

