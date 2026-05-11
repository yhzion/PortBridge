#!/usr/bin/env bash
# Release 빌드 후 /Applications 에 설치한다.
# 사용: ./install.sh
set -euo pipefail

cd "$(dirname "$0")"

echo "▶ Release 빌드…"
xcodebuild \
  -project PortBridge.xcodeproj \
  -scheme PortBridge \
  -configuration Release \
  -derivedDataPath build \
  clean build \
  > /tmp/portbridge-build.log 2>&1 \
  || { echo "✘ 빌드 실패. /tmp/portbridge-build.log 확인"; exit 1; }

APP_SOURCE="build/Build/Products/Release/PortBridge.app"
APP_TARGET="/Applications/PortBridge.app"

if [ ! -d "$APP_SOURCE" ]; then
  echo "✘ 빌드 산출물을 찾을 수 없음: $APP_SOURCE"
  exit 1
fi

echo "▶ 기존 설치 제거…"
rm -rf "$APP_TARGET"

echo "▶ /Applications 에 복사…"
cp -R "$APP_SOURCE" "$APP_TARGET"

echo "✓ 설치 완료: $APP_TARGET"
echo ""
echo "처음 실행 시 macOS Gatekeeper 경고가 뜨면:"
echo "  Finder에서 /Applications/PortBridge.app 우클릭 → 열기 → '열기' 한 번이면 이후엔 일반 실행 가능."
echo "또는 시스템 설정 → 개인정보 보호 및 보안 → '확인 없이 열기'."
