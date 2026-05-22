#!/usr/bin/env bash
# Release 빌드 후 ad-hoc 서명하여 /Applications 에 설치한다.
#
# LSD-safe 흐름:
#   - 표준 DerivedData 사용 (별도 `build/` path는 LSD entry 누적의 원인)
#   - 기존 /Applications 앱은 lsregister -u로 unregister 후 제거
#   - 새 경로만 명시 등록 → PortBridge bundle id가 LSD에 1~2 entry로 유지
#
# 사용: ./install.sh
set -euo pipefail

cd "$(dirname "$0")"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
APP_TARGET="/Applications/PortBridge.app"

echo "▶ Release 빌드…"
xcodebuild \
  -project PortBridge.xcodeproj \
  -scheme PortBridge \
  -configuration Release \
  CODE_SIGNING_ALLOWED=NO \
  clean build \
  > /tmp/portbridge-build.log 2>&1 \
  || { echo "✘ 빌드 실패. /tmp/portbridge-build.log 확인"; exit 1; }

echo "▶ 빌드 산출물 경로 조회…"
BUILT_PRODUCTS_DIR=$(xcodebuild \
  -project PortBridge.xcodeproj \
  -scheme PortBridge \
  -configuration Release \
  -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/^[[:space:]]+BUILT_PRODUCTS_DIR / {print $2; exit}')
APP_SOURCE="$BUILT_PRODUCTS_DIR/PortBridge.app"

if [ ! -d "$APP_SOURCE" ]; then
  echo "✘ 빌드 산출물을 찾을 수 없음: $APP_SOURCE"
  exit 1
fi

echo "▶ ad-hoc 서명…"
codesign --force --deep --options runtime --sign - "$APP_SOURCE"
codesign --verify --deep --strict "$APP_SOURCE"

if [ -d "$APP_TARGET" ]; then
  echo "▶ 기존 설치 LSD에서 unregister 후 제거…"
  "$LSREGISTER" -u "$APP_TARGET" 2>/dev/null || true
  rm -rf "$APP_TARGET"
fi

echo "▶ /Applications 에 복사…"
cp -R "$APP_SOURCE" "$APP_TARGET"

echo "▶ Gatekeeper quarantine 속성 제거…"
xattr -dr com.apple.quarantine "$APP_TARGET" 2>/dev/null || true

echo "▶ LSD에 새 경로 명시 등록…"
"$LSREGISTER" -f "$APP_TARGET"

echo "✓ 설치 완료: $APP_TARGET"
echo ""
echo "처음 실행 시 macOS Gatekeeper 경고가 뜨면:"
echo "  Finder에서 /Applications/PortBridge.app 우클릭 → 열기 → '열기' 한 번이면 이후엔 일반 실행 가능."
echo "또는 시스템 설정 → 개인정보 보호 및 보안 → '확인 없이 열기'."
