#!/usr/bin/env bash
# 한 번 실행하면 lint/format/dead-code 도구 설치 + git hook 연결 완료.
# 신규 클론 후 1회 실행하면 됩니다.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if ! command -v brew >/dev/null 2>&1; then
    echo "❌ Homebrew 가 필요합니다. https://brew.sh"
    exit 1
fi

echo "→ 도구 설치 확인"
for formula in swiftformat swiftlint; do
    if brew list "$formula" >/dev/null 2>&1; then
        echo "  ✓ $formula 이미 설치됨"
    else
        echo "  → brew install $formula"
        brew install "$formula"
    fi
done

if brew list periphery >/dev/null 2>&1; then
    echo "  ✓ periphery 이미 설치됨"
else
    echo "  → brew install peripheryapp/periphery/periphery"
    brew install peripheryapp/periphery/periphery
fi

echo "→ git hook 경로 설정 (.githooks/)"
git config core.hooksPath .githooks

echo "→ 실행 권한 부여"
chmod +x .githooks/pre-commit .githooks/pre-push scripts/check-deadcode.sh

cat <<'EOF'

✓ 설정 완료.

  pre-commit  : swiftformat (auto-fix) → swiftlint
  pre-push    : swiftformat --lint → swiftlint (warnings 허용)
  수동 검사    : ./scripts/check-deadcode.sh   (periphery dead code)
  CI          : .github/workflows/lint.yml 가 PR 마다 자동 실행

훅을 일시적으로 우회하려면: git commit --no-verify
EOF
