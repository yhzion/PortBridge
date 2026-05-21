#!/usr/bin/env bash
# Periphery 로 사용되지 않는(dead) 코드 검사.
# 첫 실행 시 Xcode 인덱싱 때문에 수 분 소요될 수 있습니다.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if ! command -v periphery >/dev/null 2>&1; then
    echo "❌ periphery 가 설치되어 있지 않습니다. ./scripts/setup-hooks.sh 실행 필요."
    exit 1
fi

echo "→ Periphery scan (.periphery.yml 사용)"
periphery scan
