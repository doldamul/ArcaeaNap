"""인앱 업데이트 설치 — 순수 로직 (Qt 비의존). 실제 교체는 헬퍼 스크립트가 수행."""
from __future__ import annotations

import datetime
import ntpath
import os
import posixpath
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile


class InstallerError(Exception):
    """설치 준비 단계(해제/페이로드 탐색 등) 실패."""


def diag_log(msg: str) -> None:
    """진단 로그(베스트에포트). %TEMP%(또는 OS temp)/arcaeanap-update.log 에 append.
    설치는 앱 종료 후 외부에서 일어나 UI 메시지가 없으므로, 실패 원인 추적용."""
    try:
        path = os.path.join(tempfile.gettempdir(), "arcaeanap-update.log")
        stamp = datetime.datetime.now().isoformat(timespec="seconds")
        with open(path, "a", encoding="utf-8") as f:
            f.write(f"[{stamp}] [py] {msg}\n")
    except Exception:
        pass


def extract_zip(zip_path: str, staging_dir: str) -> None:
    """zip을 staging_dir(설치 폴더 밖)에 해제. 기존 staging은 정리 후 재생성.

    macOS는 반드시 `ditto -x -k`로 해제한다. Python zipfile은 .app 번들의
    심볼릭 링크와 실행 권한(및 xattr/ad-hoc 서명)을 보존하지 못해 번들이 깨진다
    ("응용 프로그램을 열 수 없습니다"). Windows/기타는 zipfile로 충분(심링크·exec 비트 무관)."""
    if os.path.isdir(staging_dir):
        shutil.rmtree(staging_dir, ignore_errors=True)
    os.makedirs(staging_dir, exist_ok=True)
    if sys.platform == "darwin":
        try:
            subprocess.run(["ditto", "-x", "-k", zip_path, staging_dir], check=True)
        except (subprocess.CalledProcessError, OSError) as e:
            raise InstallerError(f"ditto extraction failed: {e}") from e
    else:
        with zipfile.ZipFile(zip_path) as z:
            z.extractall(staging_dir)


def find_payload_root(staging_dir: str) -> str:
    """해제물에서 설치 페이로드 루트를 찾는다.
    - macOS: 'ArcaeaNap.app' 번들 경로.
    - Windows/기타: 'ArcaeaNap.exe'가 있는 폴더."""
    for root, dirs, files in os.walk(staging_dir):
        for d in dirs:
            if d == "ArcaeaNap.app":
                return os.path.join(root, d)
        if "ArcaeaNap.exe" in files:
            return root
    raise InstallerError(f"payload (ArcaeaNap.app / ArcaeaNap.exe) not found under {staging_dir}")


def current_install_target() -> str:
    """교체 대상 경로.
    - macOS: .app 번들 (sys.executable = .app/Contents/MacOS/ArcaeaNap → 3단계 상위).
    - Windows/기타: dirname(sys.executable)."""
    exe = sys.executable
    if sys.platform == "darwin":
        d = posixpath.dirname(posixpath.dirname(posixpath.dirname(exe)))
        return posixpath.normpath(d)
    return ntpath.normpath(ntpath.dirname(exe))


def is_writable(path: str) -> bool:
    return os.access(path, os.W_OK)


def _is_within(parent: str, child: str) -> bool:
    try:
        abs_parent = os.path.abspath(parent)
        abs_child = os.path.abspath(child)
        return os.path.commonpath([abs_parent, abs_child]) == abs_parent
    except ValueError:
        return False


def paths_inside(install_target: str, candidates: list[str]) -> list[str]:
    """candidates 중 install_target 내부에 있고 실제 존재하는 절대경로만 반환."""
    out = []
    for c in candidates:
        if c and os.path.exists(c) and _is_within(install_target, c):
            out.append(os.path.abspath(c))
    return out


def _windows_script(*, payload_root, install_target, preserve, parent_pid, staging_dir,
                    need_elevation=False) -> str:
    exe = os.path.join(install_target, "ArcaeaNap.exe")
    updates_dir = os.path.join(install_target, "updates")
    # 보존 항목을 robocopy 제외 인자로 분리(파일=/XF, 디렉터리=/XD). 생성은 실제 대상 머신에서
    # 일어나므로 isdir 판정이 유효. updates 폴더(다운로드 위치)도 삭제/복사에서 제외.
    xf = [p for p in preserve if not os.path.isdir(p)]
    xd = [p for p in preserve if os.path.isdir(p)] + [updates_dir]
    xf_clause = ("/XF " + " ".join(f"'{p}'" for p in xf)) if xf else ""
    xd_clause = "/XD " + " ".join(f"'{p}'" for p in xd)
    # 재실행: 비승격이면 올바른 작업 디렉터리(설치 폴더)로 직접 실행 — config.ini 등이 CWD 상대이므로
    # CWD가 설치 폴더가 아니면 앱이 시작 시 config.ini 쓰기에 실패한다. 승격이었으면 explorer로 de-elevate.
    if need_elevation:
        relaunch = "Start-Process explorer.exe -ArgumentList $Exe"
    else:
        relaunch = "Start-Process -FilePath $Exe -WorkingDirectory $Install"
    return f"""$ParentPid = {parent_pid}
$Payload = '{payload_root}'
$Install = '{install_target}'
$Exe     = '{exe}'
$Log     = Join-Path $env:TEMP 'arcaeanap-update.log'
function Log($m) {{ ("[{{0}}] {{1}}" -f (Get-Date -Format o), $m) | Out-File -FilePath $Log -Append -Encoding utf8 }}
Log "=== update start pid=$ParentPid cwd=$((Get-Location).Path) install=$Install payload=$Payload ==="
Set-Location -LiteralPath $env:TEMP
try {{ Wait-Process -Id $ParentPid -ErrorAction SilentlyContinue }} catch {{}}
Start-Sleep -Milliseconds 500
# 디렉터리 이름 변경(rename)은 폴더 감시자(Dropbox/검색 인덱서/탐색기 창)가 디렉터리 핸들을 잡고
# 있으면 'used by another process'로 실패한다(실측). 그래서 디렉터리를 옮기지 않고 robocopy로
# '내용'을 제자리 갱신한다(감시자는 폴더 내부 쓰기를 막지 않고, 파일별 재시도로 일시 잠금도 견딤).
# ⚠️ 미러(삭제 포함) 방식 대신 /E(복사만, 여분 삭제 안 함)를 쓴다: 미러는 새 빌드에 없는 런타임
# 생성물(playwright 브라우저 .local-browsers, 캐시/유저데이터, 로그)을 전부 지워버렸다.
# /E는 앱 파일만 덮어쓰고 그 외 기존 파일은 보존한다. 사용자 config.ini는 빌드 기본값으로 덮지 않게 제외.
Log "update app files (robocopy /E, no purge)"
robocopy "$Payload" "$Install" /E /R:10 /W:2 /NFL /NDL /NP /NJH {xf_clause} {xd_clause}
$rc = $LASTEXITCODE
if ($rc -ge 8) {{
  Log "update FAILED (robocopy rc=$rc)"
}} else {{
  Log "swap OK (robocopy rc=$rc); cleaning download cache"
  Remove-Item -LiteralPath (Join-Path $Install 'updates') -Recurse -Force -ErrorAction SilentlyContinue
}}
Log "relaunch $Exe"
{relaunch}
Remove-Item -LiteralPath '{staging_dir}' -Recurse -Force -ErrorAction SilentlyContinue
Log "=== update end ==="
"""


def _macos_script(*, payload_root, install_target, parent_pid, backup_path, staging_dir, need_elevation) -> str:
    app = payload_root if payload_root.endswith(".app") else os.path.join(payload_root, "ArcaeaNap.app")
    full = (
        f"rm -rf '{backup_path}'; "
        f"mv '{install_target}' '{backup_path}' && "
        f"ditto '{app}' '{install_target}' && "
        f"rm -rf '{backup_path}' "
        f"|| {{ rm -rf '{install_target}'; [ -d '{backup_path}' ] && mv '{backup_path}' '{install_target}'; }}"
    )
    if need_elevation:
        run = f'osascript -e "do shell script \\"{full}\\" with administrator privileges"'
    else:
        run = f'sh -c "{full}"'
    return f"""#!/bin/sh
PARENT_PID={parent_pid}
while kill -0 "$PARENT_PID" 2>/dev/null; do sleep 0.2; done
{run}
open '{install_target}'
rm -rf '{staging_dir}'
"""


def build_installer_script(*, platform, payload_root, install_target, preserve,
                           parent_pid, backup_path, staging_dir, need_elevation) -> str:
    if platform == "darwin":
        return _macos_script(payload_root=payload_root, install_target=install_target,
                             parent_pid=parent_pid, backup_path=backup_path,
                             staging_dir=staging_dir, need_elevation=need_elevation)
    return _windows_script(payload_root=payload_root, install_target=install_target,
                           preserve=preserve, parent_pid=parent_pid,
                           staging_dir=staging_dir, need_elevation=need_elevation)


def _spawn_detached(cmd, **popen_kwargs):
    """Windows에서 백그라운드로 헬퍼(powershell)를 기동하고 부모(앱) 종료 후에도 유지.

    ⚠️ DETACHED_PROCESS(0x8)는 쓰지 않는다: 콘솔이 없는 frozen GUI 앱에서 이 플래그로
    powershell을 띄우면 자식이 콘솔을 못 얻어 명령을 아예 실행하지 못한다(부모 생존 중에도
    미실행 — 실측 확인). 대신 CREATE_NO_WINDOW(0x08000000)로 '자기 콘솔(숨김)'을 갖게 한다.
    CREATE_BREAKAWAY_FROM_JOB은 kill-on-close job 안일 때 앱 종료 후 생존을 위해 유지하되,
    job이 불허하면 CreateProcess가 실패하므로 그 플래그 없이 폴백한다."""
    NO_WINDOW = 0x08000000       # CREATE_NO_WINDOW (자기 콘솔, 숨김)
    NEW_GROUP = 0x00000200       # CREATE_NEW_PROCESS_GROUP
    BREAKAWAY = 0x01000000       # CREATE_BREAKAWAY_FROM_JOB
    try:
        proc = subprocess.Popen(cmd, creationflags=NO_WINDOW | NEW_GROUP | BREAKAWAY, **popen_kwargs)
        diag_log("spawn: no-window+breakaway")
        return proc
    except OSError as e:
        diag_log(f"spawn: breakaway failed ({e!r}); no-window only")
        return subprocess.Popen(cmd, creationflags=NO_WINDOW | NEW_GROUP, **popen_kwargs)


def write_and_launch(script_text: str, script_dir: str, *, platform: str, need_elevation: bool) -> None:
    """헬퍼 스크립트를 파일로 쓰고 분리 프로세스로 기동."""
    os.makedirs(script_dir, exist_ok=True)
    if platform == "darwin":
        path = os.path.join(script_dir, "arcaeanap-install.sh")
        with open(path, "w", encoding="utf-8") as f:
            f.write(script_text)
        os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)
        diag_log(f"launch sh path={path} elev={need_elevation}")
        proc = subprocess.Popen(["/bin/sh", path], start_new_session=True)
        diag_log(f"launched pid={proc.pid}")
    else:
        path = os.path.join(script_dir, "arcaeanap-install.ps1")
        with open(path, "w", encoding="utf-8") as f:
            f.write(script_text)
        if need_elevation:
            inner = "'-NoProfile','-ExecutionPolicy','Bypass','-File','" + path + "'"
            cmd = ["powershell", "-NoProfile", "-Command",
                   f"Start-Process powershell -Verb RunAs -ArgumentList {inner}"]
            diag_log(f"launch elevated ps: {cmd}")
            proc = _spawn_detached(cmd)
        else:
            cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path]
            ps_out = os.path.join(tempfile.gettempdir(), "arcaeanap-ps-output.log")
            diag_log(f"launch ps: {cmd} (ps stdout/stderr -> {ps_out})")
            _out = open(ps_out, "a", encoding="utf-8")  # noqa: SIM115 (child owns it)
            proc = _spawn_detached(cmd, stdin=subprocess.DEVNULL, stdout=_out, stderr=_out)
        diag_log(f"launched pid={proc.pid} script={path}")
