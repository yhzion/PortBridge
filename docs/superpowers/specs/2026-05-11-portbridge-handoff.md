# PortBridge - macOS SSH Port Forwarding GUI App

## 프로젝트 위치
`~/datamaker/PortBridge`

## 목표
macOS Swift(SwiftUI) 기반 GUI 앱으로, 리모트 서버의 열려있는 포트를 조회하고 선택적으로 로컬로 포트 포워딩할 수 있는 도구.

## 요구사항

### 리모트 서버 연결
- `~/.ssh/config`에 등록된 호스트 목록에서 선택
- SSH 키 기반 인증 (비밀번호 입력 불필요)

### 포트 스캔
- 리모트 서버의 1000~65535 범위 TCP 리스닝 포트 조회
- `ssh`를 통해 `ss -tlnp` 또는 `lsof -iTCP -sTCP:LISTEN` 실행
- 포트 번호, 프로세스 이름, 상태 등 표시

### 포트 검색
- 텍스트 필드로 포트 목록 필터링
- 포트 번호, 프로세스 이름 기준 검색

### 포트 포워딩 관리
- 목록에서 포트를 선택하여 포워딩 활성화 (`ssh -L PORT:localhost:PORT user@host`)
- 활성화된 포워딩은 "포워딩 중" 상태로 표시
- 해제 시 해당 SSH 프로세스 종료
- 각 포워딩은 독립적인 SSH 프로세스로 관리

### UI 구성
- SwiftUI 기반 macOS 네이티브 앱
- 서버 선택 드롭다운
- "스캔" 버튼
- 포트 목록 (검색 가능)
- 포워딩 토글 (on/off)
- 포워딩 상태 표시

## 기술 스택
- **언어**: Swift
- **UI 프레임워크**: SwiftUI
- **SSH 실행**: `Process` (Foundation) — 별도 라이브러리 없이 시스템 ssh 사용
- **포트 포워딩**: `ssh -N -L` 프로세스 관리
- **최소 타겟**: macOS 13 (Ventura)

## 구현 시 참고사항
- `Process`로 `ssh` 명령어 실행 시 stdout을 파싱해 포트 목록 획득
- SSH 터널 프로세스는 앱이 관리하는 `Process` 객체 배열로 유지
- 앱 종료 시 모든 활성 터널 프로세스 정리 필요
- `~/.ssh/config` 파싱은 직접 구현하거나 `ssh -G` 활용
- SwiftUI `@State`, `@Observable` 로 상태 관리

## 사용자 환경
- 로컬: macOS (Apple Silicon)
- 리모트: Ubuntu 서버, SSH config에 이미 호스트 등록됨
