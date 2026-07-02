"""업데이트 핸들러: 백그라운드 체크 + QML 상태 노출."""
from __future__ import annotations

import os
import shutil
import sys
import subprocess
import tempfile
import threading
import time

from PyQt6.QtCore import QObject, pyqtSlot, pyqtSignal, pyqtProperty

from services import installer
from services import update_service
from utils import app_build_info


def _quit_app() -> None:
    from PyQt6.QtCore import QCoreApplication
    app = QCoreApplication.instance()
    if app is not None:
        app.quit()


class UpdateHandler(QObject):
    stateChanged = pyqtSignal()  # 모든 프로퍼티 갱신 통지(단일 시그널)

    def __init__(self) -> None:
        super().__init__()
        self._phase = "idle"
        self._latest_version = ""
        self._release_url = update_service.RELEASES_PAGE_URL
        self._message = ""
        self._checking = False
        self._thread: threading.Thread | None = None
        self._latest = None            # update_service.LatestRelease | None
        self._progress_percent = 0
        self._transferred = 0
        self._total = -1
        self._bps = 0
        self._downloaded_path = ""
        self._downloading = False
        self._cancel = threading.Event()
        self._last_emit_pct = -1
        self._last_emit_t = 0.0

    # --- QML 노출 프로퍼티 ---
    @pyqtProperty(str, notify=stateChanged)
    def phase(self) -> str:
        return self._phase

    @pyqtProperty(str, notify=stateChanged)
    def latestVersion(self) -> str:
        return self._latest_version

    @pyqtProperty(str, notify=stateChanged)
    def releaseUrl(self) -> str:
        return self._release_url

    @pyqtProperty(str, notify=stateChanged)
    def message(self) -> str:
        return self._message

    @pyqtProperty(str, constant=True)
    def currentVersion(self) -> str:
        return app_build_info.APP_VERSION

    @pyqtProperty(bool, constant=True)
    def isFrozen(self) -> bool:
        """패키징된(frozen) 빌드 여부. dev(비-frozen)에서는 인앱 설치가 의미 없고
        (설치 대상이 파이썬 인터프리터 위치가 됨) 위험하므로 UI에서 설치를 막는다."""
        return bool(getattr(sys, "frozen", False))

    @pyqtProperty(int, notify=stateChanged)
    def progressPercent(self) -> int:
        return self._progress_percent

    @pyqtProperty(int, notify=stateChanged)
    def transferredBytes(self) -> int:
        return self._transferred

    @pyqtProperty(int, notify=stateChanged)
    def totalBytes(self) -> int:
        return self._total

    @pyqtProperty(int, notify=stateChanged)
    def bytesPerSecond(self) -> int:
        return self._bps

    @pyqtProperty(str, notify=stateChanged)
    def downloadedPath(self) -> str:
        return self._downloaded_path

    # --- 진입점 ---
    @pyqtSlot()
    def checkForUpdates(self) -> None:
        """QML(About '업데이트 확인' 버튼)용 — 실패 시 error 표시."""
        self._start_check(silent=False)

    def check_on_startup(self) -> None:
        """main.py 시작 자동 체크용 — 실패 시 조용히 무시."""
        self._start_check(silent=True)

    @pyqtSlot()
    def downloadUpdate(self) -> None:
        if self._phase != "available" or self._downloading:
            return
        self._cancel.clear()
        self._downloading = True
        self._progress_percent = 0
        self._transferred = 0
        self._total = -1
        self._bps = 0
        self._last_emit_pct = -1
        self._last_emit_t = 0.0
        self._set_state("downloading", message="Downloading…")
        self._thread = threading.Thread(target=self._run_download, daemon=True)
        self._thread.start()

    @pyqtSlot()
    def cancelDownload(self) -> None:
        self._cancel.set()

    @pyqtSlot()
    def revealDownload(self) -> None:
        path = self._downloaded_path
        if not path or not os.path.exists(path):
            return
        if sys.platform == "darwin":
            subprocess.run(["open", "-R", path], check=False)
        elif sys.platform.startswith("win"):
            subprocess.run(["explorer", f"/select,{os.path.normpath(path)}"], check=False)
        else:
            subprocess.run(["xdg-open", os.path.dirname(path)], check=False)

    @pyqtSlot()
    def installUpdate(self) -> None:
        if self._phase != "downloaded" or not self._downloaded_path:
            return
        if not getattr(sys, "frozen", False):
            # dev(비-frozen): 설치 대상이 파이썬 인터프리터 위치가 되어 위험 → 실행 거부.
            self._set_state("downloaded",
                            message="In-app install isn't supported in dev builds (release builds only).")
            return
        try:
            installer.diag_log(f"installUpdate start: platform={sys.platform} zip={self._downloaded_path}")
            staging = tempfile.mkdtemp(prefix="arcaeanap-update-")
            installer.extract_zip(self._downloaded_path, staging)
            payload = installer.find_payload_root(staging)
            target = installer.current_install_target()
            preserve = (installer.paths_inside(target, self._windows_preserve_candidates())
                        if sys.platform.startswith("win") else [])
            parent = os.path.dirname(target) or target
            need_elev = not installer.is_writable(parent)
            backup = os.path.join(parent, os.path.basename(target) + ".bak")
            installer.diag_log(f"installUpdate: target={target} parent_writable={not need_elev} "
                               f"payload={payload} backup={backup} preserve={preserve} pid={os.getpid()}")
            script = installer.build_installer_script(
                platform=sys.platform, payload_root=payload, install_target=target,
                preserve=preserve, parent_pid=os.getpid(), backup_path=backup,
                staging_dir=staging, need_elevation=need_elev)
            installer.write_and_launch(script, staging, platform=sys.platform, need_elevation=need_elev)
            installer.diag_log("installUpdate: helper launched; setting installing + quitting")
            # 헬퍼 기동 성공 → 다운로드 폴더(updates) 정리(용량 회수, 전 플랫폼 공통).
            # macOS 다운로드는 ~/Library/.../ArcaeaNap/updates 라 헬퍼가 건드리지 않으므로 여기서 정리.
            try:
                dl_dir = os.path.dirname(self._downloaded_path)
                if dl_dir and os.path.isdir(dl_dir):
                    shutil.rmtree(dl_dir, ignore_errors=True)
            except OSError:
                pass
        except Exception as e:  # 해제/탐색/기동 실패 (교체 자체는 앱 종료 후 헬퍼 책임)
            installer.diag_log(f"installUpdate FAILED before quit: {e!r}")
            self._set_state("error", message=f"Couldn't start the install: {e}")
            return
        self._set_state("installing", message="Installing… the app will restart shortly.")
        _quit_app()

    def _windows_preserve_candidates(self) -> list[str]:
        """설치 폴더에 있을 수 있는 사용자 데이터 후보(절대경로). paths_inside가 내부만 걸러낸다."""
        try:
            from utils.configuration import config, resolve_cache_path
            cands = [os.path.abspath(config.filename),
                     resolve_cache_path(config["general"]["cache_path"])]
            return [c for c in cands if c]
        except Exception:
            return []

    # --- 내부 ---
    def _start_check(self, *, silent: bool) -> None:
        if self._checking:
            return
        self._checking = True
        self._set_state("checking", message="Checking for updates…")
        self._thread = threading.Thread(target=self._run_check, args=(silent,), daemon=True)
        self._thread.start()

    def _run_check(self, silent: bool) -> None:
        try:
            result = update_service.check_for_update()
            self._apply_result(result, silent=silent)
        finally:
            self._checking = False

    def _apply_result(self, result: update_service.UpdateCheckResult, *, silent: bool) -> None:
        # 시작 자동 체크(silent)의 네트워크 실패는 조용히 무시: error → idle 강등.
        if silent and result.phase == "error":
            self._set_state("idle", message="")
            return
        self._latest = result.latest
        self._latest_version = result.latest.version if result.latest else ""
        self._release_url = result.release_url
        self._set_state(result.phase, message=result.message)

    def _set_state(self, phase: str, *, message: str = "") -> None:
        self._phase = phase
        self._message = message
        self.stateChanged.emit()

    def _on_progress(self, transferred: int, total, bps: float) -> None:
        self._transferred = transferred
        self._total = total if total else -1
        self._bps = int(bps)
        self._progress_percent = int(transferred * 100 / total) if total else 0
        now = time.monotonic()
        if self._progress_percent != self._last_emit_pct or (now - self._last_emit_t) >= 0.2:
            self._last_emit_pct = self._progress_percent
            self._last_emit_t = now
            self.stateChanged.emit()

    def _run_download(self) -> None:
        try:
            latest = self._latest
            if latest is None:
                self._set_state("error", message="Check for updates first.")
                return
            target = update_service.select_download(
                latest, frozen=getattr(sys, "frozen", False), platform=sys.platform)
            dest = os.path.join(update_service.download_dir(), target.filename)
            update_service.download_file(
                target.url, dest,
                progress_cb=self._on_progress, cancel_check=self._cancel.is_set)
            if target.expected_sha256:
                if not update_service.verify_sha256(dest, target.expected_sha256):
                    try:
                        os.remove(dest)
                    except OSError:
                        pass
                    self._set_state("error", message="Downloaded file failed integrity verification.")
                    return
                note = ""
            elif target.is_source:
                note = " (dev build: integrity check skipped)"
            else:
                # frozen 자산인데 체크섬(digest)이 없으면 검증 불가 → 조용히 통과시키지 않고 실패 처리.
                try:
                    os.remove(dest)
                except OSError:
                    pass
                self._set_state("error", message="Couldn't verify the download's checksum.")
                return
            self._downloaded_path = dest
            self._set_state("downloaded", message=f"ArcaeaNap {latest.version} downloaded.{note}")
        except update_service.DownloadCancelled:
            self._set_state("available", message="Download canceled.")
        except update_service.NoCompatibleAsset:
            self._set_state("error", message="No download available for this platform.")
        except Exception as e:
            self._set_state("error", message=update_service.humanize_error(e))
        finally:
            self._downloading = False
