# Playwright 브라우저 바이너리 런타임 설치 구현 계획서

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** 앱 빌드에 포함된 playwright 패키지를 사용하여, 브라우저 바이너리만 런타임에 설치하는 구조를 구현한다.

**Architecture:** `services/browser_bootstrap.py`에 브라우저 감지/설치 로직을 순수 Python으로 구현하고, `SettingsHandler`가 이를 QML에 노출한다. 분석 시작 시 `AnalysisHandler`가 브라우저 존재 여부를 확인하여 미설치 시 UI로 안내한다.

**Tech Stack:** Python, Playwright CLI (`python -m playwright install`), subprocess, cx_Freeze

---

## 현재 상태 분석

### 이미 되어 있는 것
- `setup.py`의 `packages`에 `"playwright"` 포함 → cx_Freeze 빌드에 패키지 번들링 완료
- `utils/browser_utils.py`의 `get_browser()`가 chromium > firefox > webkit 순으로 시도 후 실패 시 `RuntimeError` 발생
- `web_arcaeaonline.py`와 `settings_handler.py`에서 `get_browser()` 호출하여 브라우저 실행

### 해결해야 할 문제
1. 사용자가 브라우저 바이너리를 별도로 `playwright install` 해야 하는데, 이에 대한 UI 안내가 없음
2. frozen exe 환경에서 `sys.executable -m playwright install`이 동작하지 않을 수 있음 → **번들된 playwright CLI 엔트리포인트를 직접 호출하는 방식** 필요
3. 브라우저 미설치 시 분석 시작하면 `RuntimeError`로 크래시 — 사전 감지 및 안내 필요

### frozen exe에서의 playwright install 전략

cx_Freeze frozen 환경에서는 `sys.executable`이 앱 exe를 가리키므로 `sys.executable -m playwright install`이 동작하지 않는다. 대신 playwright 패키지가 번들에 포함되어 있으므로, **playwright의 내부 CLI 함수를 직접 Python 코드에서 호출**한다:

```python
from playwright._impl._driver import compute_driver_executable, get_driver_env

def install_browser(browser: str = "chromium"):
    driver_executable = compute_driver_executable()
    env = get_driver_env()
    subprocess.run([str(driver_executable), "install", browser], env=env, ...)
```

> **중요:** 이 내부 API는 playwright 버전에 따라 변경될 수 있다. 빌드 시 playwright 버전을 고정하고, 업그레이드 시 이 함수의 호환성을 확인해야 한다. Task 1 구현 시 실제 설치된 playwright 버전의 내부 구조를 먼저 확인한다.

---

## 브랜치 전략

모든 작업은 `executable` 브랜치에서 진행한다. Task 0에서 브랜치를 생성하고 기존 미커밋 변경사항을 먼저 정리한 뒤, 이후 Task들의 커밋도 모두 이 브랜치에서 수행한다.

---

### Task 0: `executable` 브랜치 생성 및 기존 미커밋 변경사항 커밋

현재 `main` 브랜치에 커밋되지 않은 변경사항이 있다 (cx_Freeze 빌드 설정, 리소스 경로 정비 등). 이를 새 브랜치에서 정리한다.

**미커밋 변경사항 목록:**
- `M` `.gitignore` — 빌드 관련 규칙 추가
- `A` `fonts/NotoSansJP-VariableFont_wght.ttf`, `fonts/OFL.txt` — 임베디드 폰트 파일
- `M` `handlers/settings_handler.py` — 캐시 마이그레이션 계약 변경 반영
- `M` `main.py` — QML 로드 경로 변경, 폰트 컨텍스트 주입
- `A` `setup.py` — cx_Freeze 빌드 설정 신규
- `R` `arcaea_nap_data/ui/*.qml` → `ui/*.qml` — UI 파일 루트 이동 (10개 파일)
- `M` `utils/app_fonts.py` — `get_app_root()` 추가, 폰트 경로 정규화
- `??` `docs/` — 계획서 디렉토리 (미추적)

**Step 1: 브랜치 생성**

```bash
git checkout -b executable
```

**Step 2: 기존 변경사항 스테이징 및 커밋**

```bash
git add .gitignore fonts/ handlers/settings_handler.py main.py setup.py ui/ utils/app_fonts.py
git commit -m "chore: cx_Freeze build setup and resource path restructuring

- Add setup.py with cx_Freeze configuration
- Move UI files from arcaea_nap_data/ui/ to ui/
- Add embedded fonts directory
- Update app_fonts.py with get_app_root() for frozen exe support
- Update main.py QML load path to use app root
- Update .gitignore for build artifacts"
```

**Step 3: 계획서 추가 커밋**

```bash
git add docs/
git commit -m "docs: add playwright browser bootstrap implementation plan"
```

---

### Task 1: `services/browser_bootstrap.py` — 브라우저 감지/설치 서비스

**Files:**
- Create: `services/browser_bootstrap.py`

**Step 1: playwright 내부 CLI 구조 확인**

Run: `python -c "from playwright._impl._driver import compute_driver_executable, get_driver_env; print(compute_driver_executable())"`

이 명령이 실패하면 현재 설치된 playwright 버전의 내부 구조를 탐색한다:

Run: `python -c "import playwright._impl._driver; print(dir(playwright._impl._driver))"`

결과에 따라 아래 구현의 import 경로를 조정한다.

**Step 2: 모듈 구현**

```python
# services/browser_bootstrap.py
"""Playwright 브라우저 바이너리 감지 및 설치 유틸리티."""
from __future__ import annotations

import subprocess
from typing import Optional


def _get_driver_command() -> list[str]:
    """Playwright driver 실행 경로를 반환한다.

    frozen exe 환경에서도 동작하도록 playwright 내부 API를 사용한다.
    """
    from playwright._impl._driver import compute_driver_executable, get_driver_env
    return [str(compute_driver_executable())], get_driver_env()


def is_browser_installed(browser: str = "chromium") -> bool:
    """지정된 브라우저 바이너리가 설치되어 있는지 확인한다.

    playwright의 내부 driver를 사용하여 확인하므로 frozen 환경에서도 동작한다.
    launch 시도 방식 대신 가벼운 경로 확인을 사용한다.
    """
    try:
        from playwright.sync_api import sync_playwright
        with sync_playwright() as p:
            browser_type = getattr(p, browser, None)
            if browser_type is None:
                return False
            # executable_path가 존재하고 파일이 있으면 설치된 것
            import os
            exec_path = browser_type.executable_path
            return bool(exec_path and os.path.isfile(exec_path))
    except Exception:
        return False


def install_browser(
    browser: str = "chromium",
    on_output: Optional[callable] = None,
) -> tuple[bool, str]:
    """Playwright 브라우저 바이너리를 설치한다.

    Args:
        browser: 설치할 브라우저 이름 ("chromium", "firefox", "webkit")
        on_output: 설치 과정의 stdout/stderr 라인을 받을 콜백

    Returns:
        (success, message) 튜플
    """
    try:
        driver_cmd, driver_env = _get_driver_command()
        cmd = driver_cmd + ["install", browser]

        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=driver_env,
        )

        output_lines = []
        for line in proc.stdout:
            line = line.rstrip()
            output_lines.append(line)
            if on_output:
                on_output(line)

        proc.wait()

        if proc.returncode == 0:
            return True, "Browser installed successfully."
        else:
            return False, f"Install failed (exit {proc.returncode}):\n" + "\n".join(output_lines[-5:])

    except FileNotFoundError:
        return False, "Playwright driver not found. The application may be corrupted."
    except Exception as e:
        return False, f"Unexpected error: {e}"
```

> **참고:** `is_browser_installed()`의 구현은 Step 1에서 확인한 playwright 내부 API에 따라 조정해야 할 수 있다. `executable_path` 속성이 없는 버전이면 `launch()` 시도 → catch 방식으로 폴백한다.

**Step 3: 커밋**

```bash
git add services/browser_bootstrap.py
git commit -m "feat: add browser bootstrap service for runtime browser installation"
```

---

### Task 2: `SettingsHandler`에 브라우저 설치 슬롯/시그널 추가

**Files:**
- Modify: `handlers/settings_handler.py`

**Step 1: 시그널/상태/슬롯 추가**

시그널 (클래스 변수 영역, 기존 시그널들 아래):
```python
# Browser setup signals
browserInstallStatusChanged = pyqtSignal()
browserInstallLogAdded = pyqtSignal(str, arguments=['message'])
```

`__init__`에 상태 변수 추가:
```python
self._is_installing_browser = False
self._browser_installed = None  # None = unchecked, True/False
```

슬롯 메서드 추가 (파일 하단, 기존 메서드들 아래):
```python
# --- Browser Setup ---
@pyqtSlot(result=bool)
def isBrowserInstalled(self):
    """Check if Playwright browser is installed."""
    if self._browser_installed is None:
        from services.browser_bootstrap import is_browser_installed
        self._browser_installed = is_browser_installed()
    return self._browser_installed

@pyqtSlot(result=bool)
def isInstallingBrowser(self):
    return self._is_installing_browser

@pyqtSlot()
def installBrowser(self):
    """Install Playwright Chromium browser in background thread."""
    if self._is_installing_browser:
        return

    self._is_installing_browser = True
    self.browserInstallStatusChanged.emit()

    def worker():
        from services.browser_bootstrap import install_browser
        try:
            success, message = install_browser(
                browser="chromium",
                on_output=lambda line: self.browserInstallLogAdded.emit(line),
            )
            self._browser_installed = success
            if not success:
                self.browserInstallLogAdded.emit(f"Error: {message}")
        except Exception as e:
            self._browser_installed = False
            self.browserInstallLogAdded.emit(f"Error: {e}")
        finally:
            self._is_installing_browser = False
            self.browserInstallStatusChanged.emit()

    threading.Thread(target=worker, daemon=True).start()

@pyqtSlot()
def recheckBrowser(self):
    """Force re-check browser installation status."""
    self._browser_installed = None
    self.browserInstallStatusChanged.emit()
```

**Step 2: 커밋**

```bash
git add handlers/settings_handler.py
git commit -m "feat: add browser install slots to SettingsHandler"
```

---

### Task 3: `settings_ui.qml`에 Browser Setup 섹션 추가

**Files:**
- Modify: `ui/settings_ui.qml`

**Step 1: General 섹션 내 Song Database와 Analyze Mode Toggle 사이에 Browser Setup UI 추가**

`settings_ui.qml`의 General 섹션에서 Song Database 카드(line ~911) 아래, `Rectangle { ... height: 1; color: "#EEEEEE" }` 구분선(line 913) 다음, Analyze Mode Toggle(line 916) 이전 위치에 삽입한다.

```qml
// Browser Setup
Text { text: "Browser"; font.bold: true; color: "#333" }

Rectangle {
    id: browserSetupCard
    Layout.fillWidth: true
    Layout.preferredHeight: browserSetupLayout.implicitHeight + 30
    radius: 10
    color: browserSetupCard.installed ? "#E8F5E9" : "#FFF3E0"
    border.color: browserSetupCard.installed ? "#A5D6A7" : "#FFCC80"
    border.width: 1

    property bool installed: settingsHandler ? settingsHandler.isBrowserInstalled() : false
    property bool installing: settingsHandler ? settingsHandler.isInstallingBrowser() : false

    Connections {
        target: settingsHandler
        function onBrowserInstallStatusChanged() {
            browserSetupCard.installed = settingsHandler.isBrowserInstalled()
            browserSetupCard.installing = settingsHandler.isInstallingBrowser()
        }
    }

    ColumnLayout {
        id: browserSetupLayout
        anchors.fill: parent
        anchors.margins: 15
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Column {
                spacing: 2
                Text {
                    text: browserSetupCard.installed ? "Chromium Installed" : "Chromium Not Installed"
                    font.bold: true
                    color: browserSetupCard.installed ? "#2E7D32" : "#E65100"
                }
                Text {
                    text: browserSetupCard.installed
                        ? "Browser is ready for analysis"
                        : "Required for Arcaea Online analysis"
                    font.pixelSize: 11
                    color: browserSetupCard.installed ? "#4CAF50" : "#FF9800"
                }
            }

            Item { Layout.fillWidth: true }

            Basic.Button {
                id: installBrowserBtn
                text: {
                    if (browserSetupCard.installing) return "Installing..."
                    return browserSetupCard.installed ? "Reinstall" : "Install"
                }
                enabled: !browserSetupCard.installing
                onClicked: if (settingsHandler) settingsHandler.installBrowser()
                background: Rectangle {
                    color: {
                        if (!installBrowserBtn.enabled) return "#B0BEC5"
                        return installBrowserBtn.down ? "#E65100" : "#FF9800"
                    }
                    radius: 6
                }
                contentItem: Text {
                    text: installBrowserBtn.text
                    color: "white"
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
```

**Step 2: 커밋**

```bash
git add ui/settings_ui.qml
git commit -m "feat: add Browser Setup section to settings UI"
```

---

### Task 4: `AnalysisHandler`에서 분석 시작 전 브라우저 확인

**Files:**
- Modify: `handlers/analysis_handler.py`
- Modify: `ui/analyze_ui.qml`

**Step 1: 시그널 추가 및 startAnalysis 수정**

시그널 추가 (클래스 변수):
```python
browserNotInstalled = pyqtSignal()  # Emitted when browser is not found
```

`startAnalysis()` 메서드에서 기존 충돌 감지 로직(line 54) 직전에 브라우저 확인을 추가:
```python
@pyqtSlot()
def startAnalysis(self):
    if self.thread and self.thread.is_alive():
        print("Analysis already running, bringing browser to front...")
        if self.analyzer:
            self.analyzer.bring_to_front()
        return

    # Check browser installation before starting
    from services.browser_bootstrap import is_browser_installed
    if not is_browser_installed():
        self.browserNotInstalled.emit()
        return

    # ... existing conflict detection code continues unchanged ...
```

**Step 2: `analyze_ui.qml`에 브라우저 미설치 안내 팝업 추가**

`analyze_ui.qml`의 기존 `Connections { target: analysisHandler }` 블록에 핸들러 추가:
```qml
function onBrowserNotInstalled() {
    browserMissingPopup.open()
}
```

같은 파일에 팝업 정의 추가:
```qml
Popup {
    id: browserMissingPopup
    anchors.centerIn: parent
    width: 380
    height: browserMissingContent.implicitHeight + 40
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: Rectangle {
        color: "#FFFFFF"
        radius: 12
        border.color: "#FF9800"
        border.width: 2
    }

    Column {
        id: browserMissingContent
        anchors.fill: parent
        anchors.margins: 20
        spacing: 12

        Text {
            text: "⚠ Browser Not Installed"
            font.bold: true
            font.pixelSize: 16
            color: "#E65100"
        }

        Text {
            text: "Chromium browser is required for analysis.\nPlease install it from Settings > General > Browser."
            wrapMode: Text.WordWrap
            width: parent.width
            color: "#333"
        }

        Basic.Button {
            text: "OK"
            anchors.right: parent.right
            onClicked: browserMissingPopup.close()
            background: Rectangle { color: "#F0F0F0"; radius: 6 }
        }
    }
}
```

**Step 3: 커밋**

```bash
git add handlers/analysis_handler.py ui/analyze_ui.qml
git commit -m "feat: check browser before analysis and show missing browser popup"
```

---

### Task 5: `setup.py` playwright 서브모듈 명시 및 정리

**Files:**
- Modify: `setup.py`

**Step 1: playwright 서브모듈 추가**

`setup.py`의 `packages` 리스트에 playwright 서브모듈을 명시:

```python
"packages": [
    # ... existing ...
    "playwright",
    "playwright.sync_api",
    "playwright.async_api",
    "playwright._impl",
    # ... existing ...
],
```

> **참고:** cx_Freeze는 보통 최상위 패키지명만으로 서브모듈을 자동 포함하지만, playwright의 `_impl` 패키지는 런타임에 동적으로 참조되는 부분이 있어 명시적으로 포함하는 것이 안전하다. 빌드 후 동작 검증이 반드시 필요하다.

**Step 2: 커밋**

```bash
git add setup.py
git commit -m "chore: explicitly include playwright submodules in cx_Freeze build"
```

---

### Task 6: 통합 검증 (수동)

**Step 1: 개발 환경 검증**

Run: `python -c "from services.browser_bootstrap import is_browser_installed; print(is_browser_installed())"`

**Step 2: 설치 흐름 검증**

앱을 실행하여 Settings > General > Browser 섹션에서:
1. 브라우저 미설치 시 "Chromium Not Installed" 표시 확인
2. "Install" 클릭 시 설치 진행 확인
3. 설치 완료 후 "Chromium Installed" 상태 전환 확인

**Step 3: 분석 흐름 검증**

1. 브라우저 미설치 상태에서 Analyze 탭의 Start Analysis 클릭
2. "Browser Not Installed" 팝업 표시 확인
3. 브라우저 설치 후 Start Analysis 정상 동작 확인

**Step 4: cx_Freeze 빌드 검증**

Run: `python setup.py build_exe`

빌드된 exe에서 위 Step 2~3 반복 검증.

> **주의:** frozen exe에서 `compute_driver_executable()` 경로가 올바른지 반드시 확인한다. 경로가 잘못되면 `_get_driver_command()`의 구현을 조정해야 한다.

**Step 5: 커밋**

```bash
git commit -m "docs: verify playwright browser bootstrap integration"
```

---

## 아키텍처 적합성 체크

| 규칙 | 준수 여부 |
|------|-----------|
| Service는 handlers를 임포트하지 않음 | ✅ `browser_bootstrap.py`는 순수 Python |
| Handler → Service → Repository 의존 방향 | ✅ SettingsHandler → browser_bootstrap |
| SQL은 Repository에서만 | ✅ 해당 없음 |
| Handler 간 직접 임포트 금지 | ✅ AnalysisHandler는 browser_bootstrap 서비스만 직접 호출 |
| 표시값은 백엔드에서 계산 | ✅ 설치 상태는 Python에서 판단 |
| QML↔Python은 QVariant 기준 | ✅ bool 반환 슬롯 사용 |
