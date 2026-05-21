#!/usr/bin/env bash
# GitHub Releases의 최신 ad-hoc 서명 ZIP을 /Applications에 설치한다.
# 사용: curl -fsSL https://raw.githubusercontent.com/yhzion/PortBridge/main/install-release.sh | bash
set -euo pipefail

REPO="${PORTBRIDGE_REPO:-yhzion/PortBridge}"
INSTALL_DIR="${PORTBRIDGE_INSTALL_DIR:-/Applications}"
APP_NAME="PortBridge.app"
ZIP_URL="https://github.com/${REPO}/releases/latest/download/PortBridge.zip"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "✘ 필요한 명령을 찾을 수 없음: $1" >&2
    exit 1
  fi
}

run_privileged() {
  if [ -w "$INSTALL_DIR" ]; then
    "$@"
  else
    sudo "$@"
  fi
}

require_command curl
require_command ditto
require_command xattr

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/portbridge-install.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "▶ PortBridge 다운로드: ${ZIP_URL}"
curl -fL "$ZIP_URL" -o "$WORK_DIR/PortBridge.zip"

echo "▶ 압축 해제"
ditto -x -k "$WORK_DIR/PortBridge.zip" "$WORK_DIR"

APP_SOURCE="$WORK_DIR/$APP_NAME"
APP_TARGET="$INSTALL_DIR/$APP_NAME"

if [ ! -d "$APP_SOURCE" ]; then
  echo "✘ ZIP 안에서 ${APP_NAME}을 찾을 수 없음" >&2
  exit 1
fi

echo "▶ ${APP_TARGET} 설치"
run_privileged rm -rf "$APP_TARGET"
run_privileged ditto "$APP_SOURCE" "$APP_TARGET"

echo "▶ Gatekeeper quarantine 속성 제거"
run_privileged xattr -dr com.apple.quarantine "$APP_TARGET" 2>/dev/null || true

echo "✓ 설치 완료: ${APP_TARGET}"
echo "  실행이 차단되면 Finder에서 앱을 우클릭한 뒤 '열기'를 선택하세요."
