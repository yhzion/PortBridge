# PortBridge

macOS SwiftUI 기반 SSH 포트 포워딩 GUI.

`~/.ssh/config` 에 등록된 호스트의 리스닝 포트를 스캔하고, 선택한 포트를 로컬로 `ssh -L` 포워딩하는 간단한 도구.

## 설치 (본인용)

```bash
./install.sh
```

- Release 빌드 → `/Applications/PortBridge.app` 으로 복사
- Launchpad / Spotlight / Dock 에서 일반 앱처럼 실행 가능
- 코드를 수정한 뒤 다시 한 번 `./install.sh` 만 실행하면 갱신됨

### 첫 실행 시 Gatekeeper

ad-hoc 서명만 되어 있어 macOS가 "확인되지 않은 개발자" 경고를 띄울 수 있다.

- Finder → `/Applications/PortBridge.app` 우클릭 → **열기** → 다이얼로그에서 **열기** 한 번이면 이후 일반 실행 가능
- 또는 시스템 설정 → 개인정보 보호 및 보안 → "확인 없이 열기"

## 요구사항

- macOS 14 (Sonoma) 이상
- `~/.ssh/config` 에 SSH 키 인증으로 접근 가능한 호스트 등록
- 리모트가 Linux 인 경우 `ss` 또는 `lsof` 사용 가능

## 문서

- 설계: [docs/superpowers/specs/2026-05-11-portbridge-design.md](docs/superpowers/specs/2026-05-11-portbridge-design.md)
- 구현 계획: [docs/superpowers/plans/2026-05-11-portbridge-implementation.md](docs/superpowers/plans/2026-05-11-portbridge-implementation.md)
