#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

VERSION="$(python -c 'from utils.app_build_info import APP_VERSION; print(APP_VERSION)')"
if [[ -z "$VERSION" ]]; then
    echo "[package] APP_VERSION is empty in utils/app_build_info.py" >&2
    exit 1
fi

APP="$PROJECT_ROOT/build/ArcaeaNap.app"
ZIP="$PROJECT_ROOT/build/ArcaeaNap-${VERSION}-macos-arm64.zip"

if [[ ! -d "$APP" ]]; then
    echo "[package] macOS app bundle not found: $APP" >&2
    exit 1
fi

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "[package] macOS ZIP ready: $ZIP"
