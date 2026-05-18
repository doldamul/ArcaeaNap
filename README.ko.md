<div align="center">

<img width="80%" src="https://github.com/doldamul/ArcaeaNap/blob/main/docs/assets/screenshots/1.png">

<h1>
  <img width="3%" src="https://github.com/doldamul/ArcaeaNap/blob/main/docs/assets/logo.png">
  ArcaeaNap
</h1>

<h3>
Arcaea Online 기반 플레이 기록 뷰어
</h3>

[Website](https://doldamul.github.io/ArcaeaNap/ko/) &nbsp;&nbsp;&nbsp; [개인정보처리방침](https://doldamul.github.io/ArcaeaNap/ko/privacy_policy/) &nbsp;&nbsp;&nbsp; [서비스 약관](https://doldamul.github.io/ArcaeaNap/ko/terms_of_service/)

[English](./README.md) · 한국어

</div>

ArcaeaNap은 빠르고 편리한 Arcaea 플레이 기록 뷰어입니다. Arcaea Online의 데이터를 로컬 PC에 저장하여, 총 플레이 시간 및 곡별 재생 횟수 등 다양한 플레이 기록을 직관적인 UI로 제공합니다.

**주의사항 및 사용 조건:**

- 플레이 기록 저장을 위해 구독이 활성화된 **Arcaea Online 계정**이 필요합니다.
- 곡 정보 데이터베이스 생성을 위해 **구글 계정**이 필요합니다.
- 곡 썸네일 및 playwright 브라우저를 위해 **1GB 이상의 여유 디스크 공간**이 필요합니다.
- 현재는 Windows 10, 11 환경만 지원합니다.

## 주요 기능

- `플레이 통계`: 플레이 시간 및 최다 플레이 순위를 한눈에 볼 수 있습니다.
- `기록 탐색`: PC에 저장된 기록들을 필터링, 정렬, 검색 기능을 통해 빠르게 탐색할 수 있습니다.
- `Arcaea 컨설턴트 시트로 기록 전송`: PC에 저장된 기록들을 Arcaea 컨설턴트 시트로 간편하게 일괄 전송할 수 있습니다.

## 사용 방법

1. [Releases](https://github.com/doldamul/ArcaeaNap/releases) 페이지에서 프로그램 압축 파일을 다운받습니다.
2. 압축을 풀고 프로그램 디렉토리 내 ArcaeaNap.exe 파일을 실행합니다.
3. 구글 계정에 로그인하고 곡 정보 데이터베이스를 생성합니다.
4. 설정에서 데이터 분석용 브라우저를 다운받습니다.
5. 설정에서 Arcaea Online에 로그인하고 구독이 활성화되어 있는지 확인합니다.
6. Analyze 탭에서 Start Analysis 버튼을 눌러 Arcaea Online에 접속합니다.
7. 플레이 기록 페이지에서 잠시 대기합니다. 브라우저에서 플레이 기록 및 곡 자켓 이미지를 자동 감지하여 로컬 PC에 저장합니다.
8. 난이도별로 모든 페이지를 방문합니다. 이때 도중에 Arcaea로부터 신규 기록이 등록되지 않도록 주의합니다.
9. Home 및 Statistics 탭에서 플레이 기록을 탐색합니다.

최초 세팅 이후에는 최신 플레이 기록들에 대해서만 페이지를 방문하면 됩니다.
기존 저장되어있던 최신 기록 이후의 모든 최신사항이 조회된 경우, Analyze 탭의 Synchonization Status가 업데이트됩니다.

## 빌드

- Python 3.13 이상
- 필수 패키지 설치:
  ```bash
  pip install PyQt6 playwright requests beautifulsoup4 google-auth google-auth-oauthlib google-api-python-client gspread keyring pywin32-ctypes cx_Freeze
  playwright install chromium
  ```

소스 코드로 실행할 때는 main.py로 접근합니다:

```bash
python main.py
```

이 프로젝트는 `cx_Freeze`를 사용하여 독립 실행 파일을 빌드합니다:

```bash
python setup.py build
```

실행 및 빌드시 프로젝트 루트 디렉토리에 유효한 `client_secret.json` (Google Cloud API 인증 정보) 파일이 필요합니다.
client_secret.json 파일 생성 절차는 다음과 같습니다:

1. [Google Cloud Console](https://console.cloud.google.com)에서 새 프로젝트를 만듭니다.
2. 사이드바를 열고 `API 및 서비스 > 사용자 인증 정보`로 이동합니다.
3. OAuth 클라이언트 ID를 `데스크톱 앱` 유형으로 생성합니다.
4. Add secret 버튼을 눌러 클라이언트 보안 비밀번호를 생성하고 JSON 다운로드 버튼을 눌러 다운로드합니다.
5. 다운받은 JSON 파일명을 client_secret.json으로 변경합니다.
6. API 키를 API 제한사항으로 Google Picker API 및 Google Sheets API 선택하여 생성합니다.
7. 키 표시 버튼을 눌러 API 키를 복사한 후, client_secret.json에 다음 파라미터를 추가합니다:

```json
{
  "installed": {
    ...
    "api_key": "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
  }
}
```

## 라이선스 및 저작권

- 이 프로젝트는 [GNU GPL v3.0](./LICENSE) 라이선스를 따릅니다.
- Arcaea 및 관련 에셋의 모든 권리는 lowiro에 있습니다.
