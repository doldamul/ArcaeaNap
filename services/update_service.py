"""GitHub Releases 기반 업데이트 확인 — 순수 로직 (Qt 비의존)."""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import os
import sys
import time

import requests

from utils import app_build_info
from utils.user_paths import get_user_data_dir

GITHUB_OWNER = "doldamul"
GITHUB_REPO = "ArcaeaNap"
LATEST_RELEASE_API = (
    f"https://api.github.com/repos/{GITHUB_OWNER}/{GITHUB_REPO}/releases/latest"
)
RELEASES_PAGE_URL = f"https://github.com/{GITHUB_OWNER}/{GITHUB_REPO}/releases/latest"
REQUEST_TIMEOUT = (5, 10)  # (connect, read) seconds


def _parse_version(text: str) -> tuple[int, ...]:
    """'v1.2.0' / '1.2' → (1,2,0). pre-release 접미사는 무시(정식만 다룸)."""
    core = text.strip().lstrip("vV").split("-")[0].split("+")[0]
    parts: list[int] = []
    for chunk in core.split("."):
        digits = "".join(ch for ch in chunk if ch.isdigit())
        parts.append(int(digits) if digits else 0)
    return tuple(parts) or (0,)


def compare_versions(current: str, latest: str) -> int:
    """current<latest → -1, 같음 0, current>latest → 1 (길이 차는 0 패딩)."""
    a, b = _parse_version(current), _parse_version(latest)
    n = max(len(a), len(b))
    a += (0,) * (n - len(a))
    b += (0,) * (n - len(b))
    return (a > b) - (a < b)


@dataclass(frozen=True)
class ReleaseAsset:
    name: str
    browser_download_url: str
    size: int
    digest: str | None        # 예: "sha256:abc..." (GitHub 서버 계산). 없을 수 있음.


@dataclass(frozen=True)
class LatestRelease:
    version: str          # 정규화된 X.Y.Z (선행 'v' 제거)
    tag_name: str         # 원본 태그 (예: "v1.2.0")
    name: str | None      # 릴리스 제목
    html_url: str         # 릴리스 페이지 URL
    body: str | None      # 릴리스 노트(markdown)
    published_at: str | None
    assets: tuple[ReleaseAsset, ...] = ()


@dataclass(frozen=True)
class UpdateCheckResult:
    phase: str                    # "available" | "not-available" | "error"
    current_version: str
    latest: LatestRelease | None
    message: str
    release_url: str              # 에러 시에도 RELEASES_PAGE_URL로 폴백


def humanize_error(exc: Exception, status: int | None = None) -> str:
    if status == 403:
        return "GitHub rate limit reached. Please try again shortly."
    if status == 404:
        return "Release not found. Make sure a public release is published."
    if isinstance(exc, requests.Timeout):
        return "Update check timed out. Check your network and try again."
    if isinstance(exc, requests.ConnectionError):
        return "Couldn't reach GitHub. Check your network connection."
    return f"Error while checking for updates: {exc}"


def _parse_release(data: dict) -> LatestRelease:
    tag = data.get("tag_name", "")
    assets = tuple(
        ReleaseAsset(
            name=a.get("name", ""),
            browser_download_url=a.get("browser_download_url", ""),
            size=int(a.get("size", 0) or 0),
            digest=a.get("digest"),
        )
        for a in data.get("assets", []) or []
    )
    return LatestRelease(
        version=tag.lstrip("vV"),
        tag_name=tag,
        name=data.get("name"),
        html_url=data.get("html_url") or RELEASES_PAGE_URL,
        body=data.get("body"),
        published_at=data.get("published_at"),
        assets=assets,
    )


def fetch_latest_release() -> LatestRelease:
    headers = {
        "User-Agent": f"ArcaeaNap/{app_build_info.APP_VERSION}",
        "Accept": "application/vnd.github+json",
    }
    resp = requests.get(LATEST_RELEASE_API, headers=headers, timeout=REQUEST_TIMEOUT)
    resp.raise_for_status()
    return _parse_release(resp.json())


class NoCompatibleAsset(Exception):
    """frozen 빌드인데 현재 플랫폼용 릴리스 자산이 없음."""


@dataclass(frozen=True)
class DownloadTarget:
    url: str
    filename: str
    expected_sha256: str | None   # digest에서 'sha256:' 제거한 hex. dev 소스면 None.
    is_source: bool


def _digest_to_hex(digest: str | None) -> str | None:
    if digest and digest.lower().startswith("sha256:"):
        return digest.split(":", 1)[1].strip().lower()
    return None


def _match_asset(latest: LatestRelease, platform: str) -> ReleaseAsset | None:
    for a in latest.assets:
        name = a.name.lower()
        if not name.endswith(".zip"):
            continue
        if platform.startswith("win") and "win64" in name:
            return a
        if platform == "darwin" and "macos" in name and "arm64" in name:
            return a
    return None


def select_download(latest: LatestRelease, *, frozen: bool, platform: str) -> DownloadTarget:
    if not frozen:
        # dev: 소스 zip(릴리스 자산 아님 → digest 없음 → 검증 생략)
        url = (f"https://github.com/{GITHUB_OWNER}/{GITHUB_REPO}"
               f"/archive/refs/tags/{latest.tag_name}.zip")
        return DownloadTarget(url=url,
                              filename=f"{GITHUB_REPO}-{latest.tag_name}-source.zip",
                              expected_sha256=None, is_source=True)
    asset = _match_asset(latest, platform)
    if asset is None:
        raise NoCompatibleAsset(f"No release asset for platform {platform!r}")
    return DownloadTarget(url=asset.browser_download_url, filename=asset.name,
                          expected_sha256=_digest_to_hex(asset.digest), is_source=False)


def check_for_update(current_version: str | None = None) -> UpdateCheckResult:
    current = current_version or app_build_info.APP_VERSION
    try:
        latest = fetch_latest_release()
    except requests.HTTPError as e:
        status = e.response.status_code if e.response is not None else None
        return UpdateCheckResult("error", current, None, humanize_error(e, status), RELEASES_PAGE_URL)
    except Exception as e:  # Timeout / ConnectionError / JSON 등
        return UpdateCheckResult("error", current, None, humanize_error(e), RELEASES_PAGE_URL)

    if compare_versions(current, latest.version) < 0:
        return UpdateCheckResult(
            "available", current, latest,
            f"Version v{latest.version} is available.", latest.html_url)
    return UpdateCheckResult(
        "not-available", current, latest,
        f"You're up to date (v{current}).", latest.html_url)


class DownloadCancelled(Exception):
    """사용자가 다운로드를 취소함."""


def download_file(url, dest_path, *, progress_cb=None, cancel_check=None,
                  chunk_size=65536) -> None:
    """url을 dest_path+'.part'에 스트리밍 저장 후 dest_path로 rename.
    progress_cb(transferred:int, total:int|None, bps:float) 청크마다 호출.
    cancel_check()가 True면 .part 삭제 후 DownloadCancelled. 예외 시 .part 정리."""
    headers = {"User-Agent": f"ArcaeaNap/{app_build_info.APP_VERSION}"}
    part = dest_path + ".part"
    os.makedirs(os.path.dirname(dest_path) or ".", exist_ok=True)
    transferred = 0
    started = time.monotonic()
    try:
        with requests.get(url, headers=headers, timeout=REQUEST_TIMEOUT, stream=True) as resp:
            resp.raise_for_status()
            cl = resp.headers.get("Content-Length")
            total = int(cl) if cl else None
            with open(part, "wb") as f:
                for chunk in resp.iter_content(chunk_size=chunk_size):
                    if cancel_check is not None and cancel_check():
                        raise DownloadCancelled()
                    if not chunk:
                        continue
                    f.write(chunk)
                    transferred += len(chunk)
                    if progress_cb is not None:
                        elapsed = max(time.monotonic() - started, 1e-6)
                        progress_cb(transferred, total, transferred / elapsed)
        os.replace(part, dest_path)
    except BaseException:
        try:
            if os.path.exists(part):
                os.remove(part)
        except OSError:
            pass
        raise


def verify_sha256(path: str, expected_hex: str) -> bool:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest().lower() == expected_hex.strip().lower()


def _app_base_dir() -> str:
    """get_app_root()와 동일 규칙. update_service는 Qt-free여야 하므로
    PyQt를 import하는 utils.app_fonts.get_app_root 대신 같은 로직을 로컬에 둔다."""
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # services/ 부모 = 리포 루트


def download_dir() -> str:
    """다운로드 저장 폴더(없으면 생성).
    - frozen + macOS: get_user_data_dir()/updates  (.app 번들 내부 쓰기 금지)
    - 그 외(frozen Windows=exe 옆, dev=리포 루트): _app_base_dir()/updates
    앱 베이스가 쓰기 불가면 user data dir로 폴백."""
    if getattr(sys, "frozen", False) and sys.platform == "darwin":
        base = get_user_data_dir() or _app_base_dir()
    else:
        base = _app_base_dir()
    target = os.path.join(base, "updates")
    try:
        os.makedirs(target, exist_ok=True)
        return target
    except OSError:
        fallback = os.path.join(get_user_data_dir() or os.getcwd(), "updates")
        os.makedirs(fallback, exist_ok=True)
        return fallback
