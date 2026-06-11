# PortBridge UI/UX 리뷰 — 50인 전문가 패널 종합 보고서

> 본 보고서의 50인 전문가 페르소나는 각 분야의 관점을 빌린 비평 렌즈이며, 실제 인물의 발언이 아닙니다.

## 총평

PortBridge는 인디 macOS 유틸리티 평균을 분명히 상회하는 기본기를 갖췄다. 복사 가능한 복구 명령(AuthFailedView), 포트 충돌 인라인 해결, WCAG 근거를 주석으로 남긴 디자인 토큰, 직접 그린 템플릿 메뉴바 아이콘은 10개 분야 전반에서 모범 사례로 인용됐다. 그러나 50인의 진단은 하나로 수렴한다. **이 앱의 가장 강력한 기능들이 시그니파이어 없는 우연한 발견에 의존하고, 가장 위험한 동작이 가장 보호받지 못한다.** 메뉴바 우클릭이 확인·피드백·실행취소 없이 모든 즐겨찾기 SSH 터널을 일괄 토글하는 설계는 8개 분야 36인이 지적한 최대 합의 이슈이며, 메인 윈도우(한국어)와 메뉴바(영어)의 언어 분열, 에러 원인의 hover 툴팁 격리, 행 토글의 어포던스 부재(죽은 `isRowHovering` 코드)가 그 뒤를 잇는다. 종합하면 "행복 경로"의 품질은 수준급이지만 실패 경로·비시각 채널·메뉴바 표면의 품질이 메인 윈도우의 절반에 머물러 있으며, 새 기능보다 **가장 빈번한 표면(메뉴바·목록 행)에서의 예측가능성·일관성·가역성 회복**이 시급하다.

---

## 심각도별 통합 이슈

### Critical

- **메뉴바 아이콘 우클릭 = 모든 즐겨찾기 터널 일괄 토글 — 발견 불가능·무확인·무피드백** (메뉴바 아이콘, `MenuBarController.swift:40-50`) — macOS 관습상 우클릭은 '메뉴 보기'라는 안전한 탐색 행위인데, 이 앱은 그 기대를 깨고 살아있는 SSH 터널 N개(DB 세션, 디버깅, VNC)를 즉시 끊거나 켠다. UI 어디에도 안내가 없고(코드 주석의 'Amphetamine 패턴'뿐), 확인·실행취소·결과 피드백이 없으며, VoiceOver·키보드 사용자는 이 기능에 접근할 경로 자체가 없다. Amphetamine의 우클릭은 무해한 로컬 상태 1개의 옵트인 토글이라 비교가 성립하지 않는다. **개선안:** 우클릭도 좌클릭과 같은 메뉴를 띄우고, 일괄 토글은 메뉴 안 '모든 즐겨찾기 켜기/끄기 (N개 활성)' 항목으로 옮겨 가시화하라. 제스처를 유지하려면 ⌥클릭 옵트인으로 강등하고, 끄는 방향일 때 확인 또는 '즐겨찾기 N개 중지됨 — 실행 취소' 피드백을 제공하라. _지적: Don Norman, Jakob Nielsen, Ben Shneiderman, Bruce Tognazzini, Bill Buxton, Steve Krug, Jared Spool, Indi Young, Susan Weinschenk, Raluca Budiu, Susan Kare, Alan Dye, Mike Stern, John Siracusa, Jason Snell, Cabel Sasser, Marc Edwards, Sindre Sorhus, Daniel Jalkut, Gus Mueller, Mitchell Hashimoto, Karri Saarinen, Julia Evans, Zach Lloyd, Paul Hudson, Alan Cooper, Julie Zhuo, Ryan Singer, Jason Fried, Léonie Watson, Marcy Sutton, Haben Girma, Karl Groves, Sarah Herrlinger, Lorrie Cranor, Angela Sasse **(36인, 8개 분야)**_

- **메인 윈도우(한국어)와 메뉴바·업데이트 다이얼로그(영어)의 언어 분열** (전역 일관성 / 현지화, `MenuBarController.swift:81-201`, `UpdatePresenter.swift`) — 메인 윈도우는 전부 한국어인데 메뉴바는 'Favorites / Open Main Window / Launch at Login / Quit PortBridge', 업데이트 다이얼로그는 'Remind Me Later'로 영어다. 같은 메뉴 안에서조차 빈 즐겨찾기 힌트(88행)는 한국어, 에러 카운트는 영어 복수형(`\(count) error(s)`, 132행)으로 혼재한다. 사용자는 '즐겨찾기'와 'Favorites'가 같은 개념임을 스스로 매핑해야 하고, 한 제품이 두 목소리로 말해 단일 시스템 이미지 형성이 불가능하다. **개선안:** 1차로 메뉴바·업데이트 문자열을 메인 윈도우와 같은 한국어로 통일하고('즐겨찾기', '메인 창 열기', '로그인 시 시작', 'PortBridge 종료', '오류 N개'), 장기적으로 String Catalog(.xcstrings)를 도입해 어휘 분기를 구조적으로 차단하라. _지적: Norman, Nielsen, Shneiderman, Tognazzini, Krug, Spool, Young, Weinschenk, Budiu, Kare, Dye, Stern, Siracusa, Snell, Sasser, Edwards, Sorhus, Jalkut, Mueller, Saarinen, Evans, Hudson, Cooper, Zhuo, Singer, Spiekermann, Vinh, Andersson, Hische, Chimero, Podmajersky, Covert, Yifrah, Halvorson, Winters, Mounter **(36인, 9개 분야)**_

- **에러 원인이 hover 전용 툴팁과 raw stderr에 갇혀 있고, 토스트는 5초 만에 증발** (에러 처리, `ForwardingRowView.swift:115-119`, `PortBridgeError.swift:14-18`, `AppViewModel.swift:38-48`) — 실패 사유가 info.circle 아이콘의 `.help()` 툴팁에만 노출돼 1초 이상 정지 호버를 요구하고, 키보드·VoiceOver로는 도달 불가능하며(WCAG 1.4.13/2.1.1 위반) 복사도 안 된다. 행에는 '클릭해 다시 시도'만 보여 인증 실패처럼 재시도가 답이 아닌 경우에도 무의미한 재시도 루프를 유도한다. `forwardingDiedEarly`는 raw stderr를 그대로 노출하는 반면 `serverUnreachable`은 reason을 버려 진단 정보가 비대칭이고, 행동이 필요한 실패조차 5초 자동 소멸 토스트로 사라진다. **개선안:** 에러 요약을 행의 인라인 보조 텍스트로 직접 노출하고('포워딩 실패: 연결 거부됨 — 클릭해 다시 시도'), 흔한 stderr 패턴(Permission denied, Address already in use, Connection refused)을 사람 말+권장 조치로 매핑하되 원문은 '자세히' 펼침으로 격하하라. 행동이 필요한 실패는 토스트가 아닌 영구 인라인 .error 상태로 유지하고 에러 히스토리를 보관하라. AuthFailedView가 이미 좋은 본보기다. _지적: Norman, Nielsen, Shneiderman, Tognazzini, Spool, Weinschenk, Hashimoto, Evans, Cooper, Wroblewski, Zhuo, Watson, Sutton, Girma, Groves, Herrlinger, Podmajersky, Yifrah, Halvorson, Winters, Cranor, Sasse **(22인, 7개 분야)**_

- **상태 변화·토스트에 대한 VoiceOver 공지가 코드베이스에 전무** (접근성 / 상태 공지) — `AccessibilityNotification.Announcement` 호출이 0건이라 포워딩이 starting→active/error로 전이되거나 에러 토스트가 나타나도 보조기술에 아무 통지가 가지 않는다(WCAG 4.1.3 위반). VoiceOver 사용자는 토글 후 성공/실패를 알 수 없어 실패한 포워딩으로 localhost 접속을 시도하게 된다. **개선안:** AppViewModel의 상태 전이 지점 한 곳에 공지 로직을 모아 active/error 전이와 토스트 추가 시 announcement를 발송하라. _지적: Karl Groves, Marcy Sutton, Haben Girma, Sarah Herrlinger **(4인)**_

- **호스트 키 검증 실패(첫 연결·MITM 의심)가 '포트 없음' 빈 상태로 침묵 처리** (보안 / SSH 신뢰 모델, `PortScanner.swift:16-52`, `TunnelManager.swift`) — BatchMode=yes 실행에서 'Host key verification failed'(exit 255)가 에러 패턴 매칭에 없고 비-0 exit catch-all도 없어, SSH의 가장 중요한 보안 경고가 무해한 빈 목록으로 위장된다. 사용자가 택할 가장 흔한 우회는 `StrictHostKeyChecking no`로, 그 사용자의 모든 SSH에서 MITM 방어를 꺼버린다. **개선안:** 해당 stderr를 전용 에러로 매핑하고 매핑 안 된 비-0 exit는 절대 빈 목록으로 삼키지 마라. 첫 연결은 키 지문을 보여주는 명시적 신뢰 결정 UI를, 키 변경은 한 클릭으로 우회 불가능한 위험 상태로 표시하라. _지적: Lorrie Cranor, Angela Sasse **(2인)**_

- **터널의 런타임 사망이 침묵 속에 묻힘** (에러 처리 / 메뉴바 상태, `AppViewModel.swift:411-418`) — 네트워크 단절로 터널이 죽어도 시스템 알림이 없고, 메뉴바 'N errors' 카운트는 토스트 기반이라 런타임 사망을 못 잡으며, 즐겨찾기 행에서 .error가 .idle과 같은 '○'로 그려진다. 메인 윈도우가 닫힌 메뉴바 상주 앱에서 사용자는 localhost 접속 실패 후에야 사망을 추론한다. **개선안:** `tunnelDidExit`에서 UserNotifications 알림을 발송하고, 메뉴 즐겨찾기 행에 .error 전용 글리프(⚠)를 추가하며, 에러 카운트가 .error 상태 포워딩도 집계하게 하라. _지적: Mitchell Hashimoto **(1인)**_

- **메뉴바에서 시작한 포워딩이 실패하면 해결 UI가 없는 막다른 길** (메뉴바 ↔ 메인 윈도우 흐름, `AppViewModel.swift:383`) — 포트 충돌 시트와 에러 토스트가 ContentView에만 렌더되므로, 메인 윈도우가 닫힌 채 메뉴바에서 시작한 포워딩이 충돌하면 아무 UI도 뜨지 않고 '클릭했는데 아무 일도 안 일어남'이 된다. **개선안:** 메뉴바 발 실패는 메뉴바 맥락에서 닫아라 — 최소한 메인 윈도우를 자동으로 띄워 시트를 표시하고, 이상적으로는 빈 포트로 자동 재시도 후 알림으로 고지하라. _지적: Ryan Singer **(1인)**_

### Major

- **메뉴바 즐겨찾기 항목의 상태 이중 인코딩(✓+●/○)과 위계 없는 run-on 타이틀** (메뉴바 메뉴, `MenuBarController.swift:103, 206-210`) — `NSMenuItem.state` 체크마크와 텍스트 ●/○ 글리프가 같은 상태를 두 번 표현하고, VoiceOver가 매 항목 'black circle'을 먼저 읽으며 점자 출력을 오염시킨다. '✓ ● Private VM (100.91.49.19):5173 MainThread'처럼 서버명·IP·포트·프로세스명이 구분자 없이 한 줄에 욱여넣어져 로그처럼 읽히고, 토글 시 RemotePort를 "0.0.0.0"으로 하드코딩(226·236행)해 데이터도 어긋난다. **개선안:** 상태는 `NSMenuItem.state` 하나로 일원화하고 ●/○를 제거하라. 타이틀은 '서버명 :포트' 수준으로 줄이고 IP·프로세스명은 subtitle/툴팁으로 강등하라. _지적: Krug, Young, Weinschenk, Kare, Dye, Stern, Siracusa, Snell, Edwards, Sasser, Cooper, Singer, Fried, Watson, Sutton, Girma, Groves, Herrlinger, Spiekermann, Vinh, Andersson, Hische, Chimero, Covert, Halvorson, Winters, Saarinen, Evans, Lloyd, Hudson **(30인, 8개 분야)**_

- **포트 메타데이터 표기 결함 — 원시값 '*' 노출, 반복 라벨의 소음화, 정보 위계 역전** (메인 윈도우 목록, `RemotePort.swift:18-24`, `ForwardingRowView.swift:92-97`) — scopeLabel의 default 분기가 ss 출력의 '*'를 그대로 흘려보내 :3389 행에 외로운 별표가 렌더링 글리치처럼 보이고, 11개 행 중 7개가 동일한 '모든 인터페이스'를 반복해 회색 소음이 되는 동안 정작 변별 정보인 프로세스명(python3, Xtigervnc)은 .tertiary 3차 텍스트로 격하되어 있다. 특정 IP에만 바인딩된 포트는 터널이 살아있어도 트래픽이 거부되는 'active인데 안 되는' 상태가 된다. **개선안:** '*'를 '모든 인터페이스'로 정규화하고, 프로세스명(또는 well-known 포트 매핑)을 1차 텍스트로 승격하며, 스코프는 예외('로컬 전용')에만 배지로 표기하라. localhost로 도달 불가능한 포트에는 경고를 표시하라. _지적: Krug, Weinschenk, Budiu, Hashimoto, Saarinen, Evans, Covert, Yifrah, Halvorson, Winters, Spiekermann, Vinh, Andersson, Hische, Chimero **(15인)**_

- **행 전체가 보이지 않는 토글 버튼 — 어포던스 부재와 죽은 `isRowHovering` 코드** (메인 윈도우 목록, `ForwardingRowView.swift:57, 72-109, 122`) — 앱의 핵심 상호작용(행 클릭 → 터널 생성)에 시각 단서가 1초 호버 툴팁뿐이고, hover 피드백용 `@State isRowHovering`은 onHover에서 갱신만 되고 body 어디서도 읽히지 않는 죽은 코드다. ○ 기호는 라디오 버튼/상태 표시로 읽혀 신규 사용자는 핵심 동작을 발견하지 못하고, 목록을 둘러보려는 가벼운 클릭이 곧바로 ssh -L을 발사한다. **개선안:** `isRowHovering`을 실제로 배선해 hover 시 행 배경 하이라이트와 ○→▶ 아이콘 전환, '연결' 액션 단서를 표시하라. 큰 Fitts 타깃은 유지하되 '클릭하면 무슨 일이 일어나는지'를 클릭 전에 화면이 말하게 하라. _지적: Norman, Shneiderman, Tognazzini, Buxton, Krug, Spool, Budiu, Kare, Sorhus, Mueller, Edwards, Zhuo, Fried **(13인)**_

- **키보드 모델 부재 — ⌘F 미배선, List selection 없음, 오해를 부르는 ⌘O 표기, 수제 검색 필드** (키보드 UX, `ServerListView.swift:9, 209-279`, `MenuBarController.swift:144-148`) — SSH 사용자라는 타깃과 정면충돌하게, 목록 화살표 탐색·Return 토글·즐겨찾기 단축키가 전부 없고 `@FocusState isSearchFocused`는 선언만 된 채 ⌘F 배선이 없다. 검색 필드를 `.searchable` 대신 70줄 수제로 재구현해 시스템이 공짜로 주는 ⌘F·Esc·포커스 링·VoiceOver role을 모두 포기했다. 'Open Main Window ⌘O'는 메뉴가 열려 있을 때만 동작하는데 전역 핫키처럼 읽히고, ⌘O는 '파일 열기'에 예약된 의미다. **개선안:** `.searchable` 채택(또는 ⌘F→isSearchFocused 배선), List selection + Return/Space 토글, 검색 결과 1개 시 Enter 즉시 포워딩하는 커맨드 팔레트형 플로우를 만들어라. ⌘O 표기는 제거하거나 실제 전역 핫키로 승격하라. _지적: Shneiderman, Tognazzini, Buxton, Stern, Siracusa, Snell, Dye, Saarinen, Lloyd, Hudson, Sorhus, Mueller, Edwards **(13인)**_

- **활성 포워딩 행의 식별 결함 — 서버명 누락, 끝점 불명, 포트 위계 역전, 복사 액션 부재** (활성 포워딩 행, `ForwardingRowView.swift:44-49`) — `stateSubtitle`의 .active 케이스만 serverPrefix를 버려 ':5173 → :5173 포워딩 중'으로 표시되므로(serverDisplayName은 이미 전달됨 — 한 줄 수정), 서버 2대가 같은 포트를 쓰면 구분이 불가능해 엉뚱한 터널을 끄게 된다. 화살표의 양 끝(원격 vs 내 Mac)도 표기되지 않고, 사용자가 실제 입력할 로컬 포트가 가장 작은 활자에 묻히며, 브라우저로 열 수 없는 :5432·:3389에 'localhost:포트 복사' 같은 후속 액션이 없다. **개선안:** .active에 serverPrefix를 복원하고('Private VM · → localhost:5173에서 사용 가능'), ServerMonogram을 재사용하며, 우클릭 컨텍스트 메뉴(주소 복사 / ssh -L 명령 복사)를 추가하라. _지적: Young, Weinschenk, Budiu, Sasser, Evans, Lloyd, Singer, Covert, Spiekermann, Andersson, Hische **(11인)**_

- **표준 Settings 윈도우(⌘,) 부재 — 1회성 설정이 메뉴바 메뉴를 점령** (설정 구조, `MenuBarController.swift:152-191`) — Launch at Login, Show in Dock, 업데이트 설정 등 영속 환경설정이 상태 메뉴에 12개 이상 항목으로 쌓여 가장 빈번한 동선인 즐겨찾기 토글이 묻힌다. File 메뉴는 빈 블록이라 ⌘N·⌘R의 발견 경로도 없다. **개선안:** SwiftUI Settings 씬을 추가해 설정류를 ⌘,로 옮기고, 메뉴는 즐겨찾기/Active/메인 창 열기/업데이트 확인/종료로 압축하라. CommandGroup으로 메인 메뉴에 단축키를 정식 등록하라. _지적: Stern, Siracusa, Snell, Fried, Cooper, Singer, Saarinen, Evans, Lloyd, Hudson **(10인)**_

- **업데이트 신호가 4pt 점 하나 + 메뉴에 행동 경로 부재 — 막다른 퍼널** (업데이트 UX, `MenuBarController.swift:289-314`) — 업데이트 배지가 18pt 아이콘 구석의 4×4pt systemBlue CALayer라 사실상 비가시이고, 고정 cgColor라 다크 모드·하이라이트 반전에 적응하지 않으며, CALayer는 접근성 트리에도 안 올라간다. 점을 발견해 메뉴를 열어도 `buildMenu()`에 대응 항목이 없어 상태를 확인할 곳이 없다. **개선안:** `availableUpdate`가 있으면 메뉴 상단에 '업데이트 가능: vX.Y.Z — 다운로드…' 항목을 추가하고, 배지는 별도 레이어 대신 MenuBarIconRenderer에 파라미터로 합성해 템플릿 반전·색 적응을 공짜로 해결하라. _지적: Nielsen, Tognazzini, Jalkut, Edwards, Mueller, Sasser, Watson, Girma, Groves **(9인)**_

- **포트 충돌 시트: 미검증 +1 디폴트가 충돌 루프를 만들고, 앱이 풀 수 있는 문제를 모달로 떠넘김** (포트 충돌 처리, `ContentView.swift:89-110`) — `attemptedLocal+1` 제안이 실제 가용성을 확인하지 않아 연속 포트 점유가 흔한 개발 환경에서 '연결 → 또 충돌 → 또 시트' 루프가 생긴다. 사용자의 목표는 원격 포트 접속이지 로컬 포트 번호 고르기가 아니므로 모달 자체가 excise다. **개선안:** 시트 전에 bind 가능한 첫 포트를 탐색해 검증된 기본값을 제시하고, 이상적으로는 빈 포트로 자동 연결 후 '→ :5174 포워딩 중 (5173 사용 중)' 인라인 고지로 모달을 예외 경로로 강등하라. _지적: Nielsen, Buxton, Jalkut, Mueller, Cooper, Wroblewski, Zhuo, Singer **(8인)**_

- **메뉴바 아이콘 렌더링의 픽셀 정밀도 결함과 식별 불가능한 active 상태** (메뉴바 아이콘, `MenuBarIconView.swift:35-71`) — 24 그리드 도형을 18pt로 축소해 분수 좌표·1.5pt stroke가 픽셀 그리드에 안 맞아 1x에서 번지고, `NSScreen.main` 고정 스케일 래스터화라 혼합 DPI 환경에서 한쪽이 반드시 블러된다. active 신호가 반지름 2.2pt 점 하나라 '지금 터널이 살아있나'라는 앱의 단 하나의 질문에 아이콘이 답하지 못한다. **개선안:** `NSImage(size:flipped:drawingHandler:)` 벡터로 전환해 화면별 스케일에 자동 대응시키고, 18pt 그리드에 픽셀 스냅으로 재설계하며, active는 점 추가가 아닌 filled vs outline의 실루엣 수준 형태 전환으로 표현하라. _지적: Kare, Dye, Snell, Edwards, Sorhus, Sasser, Andersson **(7인)**_

- **디자인 시스템의 정의-적용 괴리 — 미사용 토큰 절반, 상태 색상 21곳 리터럴, raw .green 대비 미달, 모션 토큰 부재** (토큰 인프라, `DesignTokens.swift`, `ForwardingRowView.swift:81`) — 토큰 사전의 절반 이상이 사용처 0건인데 핵심 상태 색상(green/red/orange)은 21곳에 원시 리터럴로 산재하고, 라이트 모드 systemGreen 텍스트는 약 2.2:1로 WCAG 미달이다. 활성 행은 초록 점+초록 숫자+초록 캡션의 3중 반복으로 색의 변별력을 소모하며, 거의 같은 스프링 3종이 표류한다. **개선안:** statusActive/statusError/statusWarning 텍스트 토큰을 추가해 일괄 치환하고, 미사용 토큰은 삭제 또는 마이그레이션하며, PBMotion 토큰 레이어를 만들어 스프링을 1종으로 수렴시켜라. '초록=상태, 파랑=행동, 모노그램 hue=정체성' 역할 분담을 명문화하라. _지적: Mounter, Head, D'Silva, Spiekermann, Andersson, Chimero **(6인)**_

- **비인터랙티브 섹션 헤더에 액센트 컬러 — 위계 역전** (섹션 헤더, `AllServersSectionHeader.swift:10-13`, `ActiveSectionHeader.swift:13-16`) — 클릭 불가능한 '모든 서버 · 2' 라벨이 .tint 파랑 semibold인데 실제 동작하는 '모두 끄기' 버튼은 .secondary 캡션으로 더 약해, '파랑=클릭 가능'이라는 의미 체계가 무너진다. **개선안:** 헤더를 macOS 표준 .caption semibold + .secondary로 내리고 액센트는 인터랙티브 요소에만 예약하라. _지적: Spiekermann, Vinh, Hische, Chimero **(4인)**_

- **~/.ssh/config를 읽지 않는 온보딩 — 이미 가진 정보를 4개 필드에 재입력** (서버 추가 시트, `AddServerSheet.swift:72-77`) — 제품 포지셔닝은 ssh config 기반인데 파싱 코드가 없어, config에 Host·User·HostName·Port를 이미 정의해 둔 타깃 사용자가 같은 정보를 다시 타이핑해야 하고 IP 오타가 serverUnreachable의 직접 원인이 된다. **개선안:** '~/.ssh/config에서 가져오기' picker를 1순위 경로로 배치해 첫 서버 등록을 타이핑 0회로 줄이고, 빈 상태 화면 CTA로도 제안하라. _지적: Spool, Lloyd, Cooper, Wroblewski **(4인)**_

- **메뉴바 아이콘이 시스템 상태를 거짓/과대 보고** (메뉴바 아이콘, `MenuBarController.swift:284-287`, `AppViewModel.swift:260-267`) — `isAnyFavoriteActive`만 보므로 즐겨찾기 아닌 포워딩이 활성이어도 아이콘은 idle이고, 반대로 즐겨찾기 3개 중 2개가 인증 실패해도 하나만 살아있으면 정상으로 보인다. 사용자는 아이콘만 믿고 노트북을 닫거나, 죽은 터널로 DB 접속을 시도한다. **개선안:** 활성 표시 기준을 '활성 포워딩이 하나라도 있는가'로 바꾸고('점 없음 = 포워딩 없음' 보장), 즐겨찾기 중 error가 있으면 경고 변형을 표시하라. _지적: Norman, Cranor, Sasse **(3인)**_

- **서버 상태 점이 색상 단독 채널 + 경고 상태가 VoiceOver에 통째로 누락** (메인 윈도우 목록, `ServerSectionView.swift:44-51, 135-169`) — StatusDot이 같은 모양 8px 원의 녹/주황/회색만으로 구분해 색각 이상 사용자가 식별 불가하고(WCAG 1.4.1), authFailed/toolMissing 경고가 접근성 트리에 없어 섹션이 접혀 있으면 SSH 인증이 깨졌다는 신호를 스크린리더가 영영 받지 못한다. **개선안:** 헤더 accessibilityValue에 scanState를 합성하고, differentiateWithoutColor 환경값에 따라 모양 차이·텍스트 배지를 병행하라. _지적: Sutton, Girma, Herrlinger **(3인)**_

- **포워딩 토글 전환의 연속성 붕괴 — 포트 번호 소실 + 행의 섹션 간 순간이동** (목록 모션, `ForwardingRowView.swift:33-38`, `ServerListView.swift:145-157`) — .starting에서 방금 클릭한 포트 번호가 사라져 레이아웃이 점프하고, 연결되면 행이 제자리에서 소멸해 화면 최상단 '포워딩 중' 섹션에 새 identity로 출현한다. 모션의 1차 목적인 공간적 오리엔테이션이 빠져 '내가 켠 포트가 어디 갔지?' 비용이 매번 발생한다. **개선안:** showPortColumn의 .starting 분기를 제거해 포트 번호를 유지하고, 섹션 간 이동은 matchedGeometryEffect(또는 2단계 전환)로 추적 가능하게 하라. _지적: Young, Head, D'Silva **(3인)**_

- **접근성 잔여 이슈 — 라벨 컨텍스트 부재, tertiary 대비 미달, 24px 타깃 미달** (메인 윈도우 목록) — 별 버튼 라벨이 '즐겨찾기 추가/해제'뿐이라 행 10개에서 동일 라벨만 반복되고(WCAG 2.4.6), 프로세스명의 tertiary 색은 실효 대비 약 2:1로 4.5:1 기준 미달이며(`DesignTokens.swift:72`의 'WCAG 보장' 주석은 잘못된 전제), 별 18×18·복사 22×22 등 핵심 타깃이 24×24 최소 크기에 못 미친다. **개선안:** 라벨에 대상 포함('포트 5173 즐겨찾기 추가'), 의미 콘텐츠는 .secondary 이상, 히트 영역 24×24 이상 확장. _지적: Watson, Girma, Groves **(3인)**_

- **파괴적 동작 보호 수준의 역전 — '모두 끄기' 무확인, 삭제는 undo 없는 확인만, ⌘Q는 활성 터널 무경고 종료** (에러 방지 / 수명주기, `ServerListView.swift:74-76, 153`, `MenuBarController.swift:253-255`) — 터널 N개를 끊는 '모두 끄기'는 즉시 실행인데 레코드 하나 지우는 삭제는 확인을 거치고, 삭제 확인문은 기술적으로 복원 가능한데 '되돌릴 수 없습니다'라고 선언한다. `applicationShouldTerminate` 미구현으로 활성 포워딩 N개가 ⌘Q 한 번에 소리 없이 죽는다. **개선안:** '모두 끄기'에 개수 확인 또는 실행취소 토스트, 삭제에 'N초 안에 실행 취소' 경로, 종료 시 '포워딩 N개 연결 중입니다' 확인(+다시 묻지 않기)을 추가하라. _지적: Shneiderman, Sasser **(2인)**_

- **보안 결정의 동의 부재와 오처방 — 로그인 자동 터널 결합, ssh-copy-id 단정** (보안 UX, `AppViewModel.swift:172-189`, `ServerSectionViewModel.swift:53-54`) — '로그인 시 시작'이라는 편의 결정에 '부팅마다 원격 채널 개설'이라는 보안 결정이 고지 없이 묶여 있고 로그인 시 실패는 볼 수 없다. 인증 실패에 무조건 ssh-copy-id를 처방하지만 BatchMode는 패스프레이즈 키도 같은 에러로 떨어뜨려, 보안 모범 사례를 따르는 사용자가 '패스프레이즈 없는 키 생성'으로 내몰리는 역전이 생긴다. **개선안:** 두 옵션을 분리(자동 포워딩 기본 꺼짐)하고, 인증 실패 시 `ssh-add -l`로 agent 상태를 확인해 조건부 처방으로 바꿔라. _지적: Cranor, Sasse **(2인)**_

- **Reduce Motion 미대응 — 무한 반복 펄스 포함 전 애니메이션이 시스템 설정 무시** (접근성/모션, `ServerSectionView.swift:302-307`) — `accessibilityReduceMotion` 참조가 0건이고, 오프라인 재시도 중 StatusDot이 무한 repeatForever 스케일 펄스를 돈다 — 전정기관 민감 사용자에게 가장 문제 되는 패턴이다. **개선안:** `@Environment(\.accessibilityReduceMotion)` 분기를 PBMotion 토큰 레이어에서 일괄 처리하라(반복→정적, 이동→페이드). _지적: Head, Mounter **(2인)**_

- **단독 지적이지만 중요한 이슈들:**
  - *첫 실행 시 윈도우가 열리지 않음* (`PortBridgeApp.swift:72, 119-121`) — 런치 인자 없이는 메뉴바 아이콘만 추가돼 '앱이 켜졌는가'부터 실패. 최초 실행(서버 0개) 감지 시 자동으로 빈 상태 화면을 열어라. _지적: Jared Spool_
  - *윈도우 위치·크기 미기억* (`PortBridgeApp.swift:84-101`) — `setFrameAutosaveName` 미설정으로 매번 중앙 900×600 리셋. 한 줄로 복원하라. _지적: John Siracusa_
  - *자동 업데이트 체크가 포커스를 강탈하는 모달* (`UpdatePresenter.swift:69-72`) — 24시간 자동 체크도 `activate + runModal`로 작업을 중단시킨다. 자동 경로는 배지+메뉴 항목으로만 알려라. _지적: Daniel Jalkut_
  - *'active'가 검증이 아닌 2초 grace 휴리스틱* (`TunnelManager.swift:92-109`) — 로컬 포트 listen 확인이나 ssh -v 파싱으로 검증된 시점까지 starting을 유지하라. _지적: Mitchell Hashimoto_
  - *재스캔 후 유령 터널* (`ServerListView.swift:181-194`) — 원격 프로세스가 죽으면 헤더는 '포워딩 중 · 1'인데 행이 0개가 되어 개별로 끌 방법이 사라진다. 활성 행 렌더를 스캔 결과에 의존시키지 마라. _지적: Ryan Singer_

### Minor

- **즐겨찾기 ★의 시스템적 의미가 발견 불가능 + 메인 윈도우 IA에 즐겨찾기 부재** (개념 모델 / IA) — ★가 메뉴바 노출·일괄 토글 대상·아이콘 상태 기준이라는 세 가지를 좌우하는데 툴팁은 '즐겨찾기에 추가'뿐이고, 메뉴바에선 1급 섹션인 즐겨찾기가 메인 윈도우 구조에는 없다. 툴팁을 결과 중심으로 바꾸고('메뉴바에서 바로 켜고 끌 수 있습니다'), 메인 윈도우에 즐겨찾기 섹션 또는 상단 정렬을 추가하라. _지적: Don Norman, Abby Covert **(2인)**_
- **핵심 동사 혼용 — '포워딩 켜기/끄기' vs '연결' vs 내부 '터널'** (용어 체계, `ContentView.swift:130`) — 충돌 시트 버튼 '연결'은 무엇과 무엇이 연결되는지 말하지 않는다. 용어 사전을 만들어 '포워딩 시작/중지'로 고정하고 '연결'은 SSH 도달성 문맥에만 예약하라. _지적: Kristina Halvorson, Torrey Podmajersky **(2인)**_
- **'Download' 버튼이 실제로는 웹페이지를 엶** (`UpdatePresenter.swift:52, 59`) — 레이블을 동작에 맞춰 '릴리스 페이지 열기'로 바꿔라. _지적: Torrey Podmajersky, Kinneret Yifrah **(2인)**_
- **라이팅 디테일 — 이중부정 빈 상태('포워딩되지 않은 포트 없음'), 기호(↻/★)로 UI 지칭, '이(가)' 조사 병기** — 긍정문 분기, 버튼 이름 지칭, 받침 판정 헬퍼 또는 문형 재작성으로 정리하라. _지적: Podmajersky, Covert, Yifrah, Halvorson, Winters **(5인)**_
- **macOS VoiceOver 힌트에 iOS 관용구 '이중 탭하여' 사용** — 힌트에서 제스처 어휘를 제거하고 결과만 기술하라. _지적: Marcy Sutton, Sarah Herrlinger **(2인)**_
- **폼 검증 타이밍 결함 — 타이핑 중 즉시 에러, 비활성 버튼 사유 미표시, 초기 포커스 부재** (`AddServerSheet.swift:32-37, 78`) — focus-out 검증, 비활성 사유 한 줄, 필드 재배열 + defaultFocus. _지적: Luke Wroblewski **(1인)**_
- **행 높이 1줄/2줄 출렁임 + 안내문 '↻' 글리프 불일치** — 프로세스명 인라인 병기 또는 고정 minHeight, Text 보간 `Image(systemName:)` 사용. _지적: Khoi Vinh, Jessica Hische **(2인)**_
- **고정 헤더 '모든 서버'가 '포워딩 중' 섹션 위에 떠서 라벨링 계약 위반 + 상단 4단 적층** (`ServerListView.swift:32-39`) — 헤더를 List 내 Section header로 내려라. _지적: Khoi Vinh **(1인)**_
- **메뉴바 아이콘 상태 전환이 1프레임 스왑** (`MenuBarController.swift:284-287`) — 전환 순간에만 짧은 fade/scale 모션을 주고 정적 상태로 안착시켜라. _지적: Val Head, Pasquale D'Silva **(2인)**_

### Polish

- **웹 관습 유입 — 버튼 hover 시 pointing hand 커서 강제 + DragGesture 눌림 수동 재구현** (`ForwardingRowView.swift:161-217`) — macOS 버튼의 표준 커서는 화살표이고 `.set()` 직접 호출은 커서 고착 버그 패턴이다. 시스템 버튼 스타일로 교체하라. _지적: Mike Stern, John Siracusa **(2인)**_
- **PBLayout 토큰을 만들어 놓고 우회하는 매직 넘버(5·6·7·10)와 1.5pt 반픽셀 스트로크** (`ServerListView.swift:223-226` 등) — 토큰 스케일에 스냅하고 스트로크는 정수로 맞춰라. _지적: Khoi Vinh, Rasmus Andersson **(2인)**_

---

## 분야별 핵심 요약

**HCI 원론** — 에러 복구 설계(복사 가능한 명령, 인라인 검증)는 모범 사례지만, 가장 빈번한 표면인 메뉴바와 목록 행에서 예측가능성·일관성·가역성이라는 기본 원칙이 무너져 있다. 강력한 기능들이 시그니파이어 없이 우연한 발견에 의존하는 것이 공통 결론.

**사용성 리서치** — "켜기 전"의 자명성과 에러 복구는 수준급이나, 첫 실행 경로와 "켠 후"의 상태 표시가 시스템 중심(포트 번호, 바인드 스코프)이고 사용자 기억 중심(어느 서버의 무슨 프로세스)이 아니다. 우클릭 일괄 토글은 발견성과 안전성을 동시에 위반하는 유일한 만장일치 이슈.

**Apple/macOS 플랫폼** — 템플릿 아이콘, 표준 NSMenu, 충실한 툴팁 등 기본기는 합격점이나 '시스템 앱처럼 느껴지는가'라는 최종 관문을 넘지 못한다. 우클릭=메뉴, 설정은 ⌘,, 윈도우 위치 기억 같은 30년 플랫폼 관습으로의 회귀가 시급하다.

**Mac 인디 장인** — Canvas로 직접 그린 아이콘, Sparkle 정석의 3버튼 다이얼로그 등 정성은 충분하나, '살아있는 SSH 연결'에 대한 신뢰 계약(⌘Q 무경고, 런타임 사망 침묵)이 깨져 있다. 이런 메뉴바 유틸리티는 마지막 5%의 마감이 곧 제품인데 지금 그 5%가 정성을 갉아먹고 있다.

**개발자 도구 DX** — ExitOnForwardFailure 명시 등 SSH 기본기는 평균 이상이나, 'active'가 2초 grace 휴리스틱이고 런타임 사망이 침묵하는 등 '정확한 상태 보고'라는 도구의 존재 이유가 약화되어 있다. 키보드 플로우와 ssh config 임포트, localhost 주소 복사가 빠져 'ssh -L 한 줄보다 빠른가'의 마지막 구간이 끊겨 있다.

**인터랙션/제품** — 행 클릭 한 번 토글이라는 코어 인터랙션은 잘 깎였으나 행복 경로 바깥의 품질이 절반 수준이다. 미검증 +1 디폴트, config 재입력, 메뉴바 발 실패의 막다른 길 등 '앱이 스스로 풀 수 있는 일을 사용자에게 떠넘기는' 패턴이 반복된다.

**접근성** — 정적 라벨링(accessibilityLabel/Hint/Value 합성)은 인디 평균을 상회하나, 동적 상태 공지와 비시각 대체 경로가 통째로 비어 있다. 에러는 hover에만, 일괄 토글은 우클릭에만, 업데이트는 4px 점에만 존재해 실패·예외 상황에서 보조기술 사용자가 막다른 길에 부딪힌다.

**비주얼/타이포** — monospacedDigit 포트 정렬, WCAG 근거 주석 등 골격은 좋으나 디테일에서 체계가 샌다. 메뉴바는 메인 윈도우와 "다른 손이 만진" 낙차를 보이고, 액센트 오용·초록 3중 반복·원시값 노출 등 "가장 굵은 것이 가장 중요한 것이 아닌" 위계 역전이 반복된다.

**UX라이팅/IA** — 행동 지향 카피와 복사 가능한 안내는 평균 이상이나, 언어/보이스 분열로 단일 제품의 목소리가 깨져 있다. 실패 경로에서 raw stderr와 '*'가 카피 자리를 차지해 "무슨 일이 + 왜 + 다음 행동" 공식이 무너지며, 용어 사전과 String Catalog 도입이 핵심 처방.

**보안UX/모션/시스템** — 호스트 키 검증 부재가 MITM 경고를 빈 상태로 위장시키고, 보안 결정(자동 터널, 일괄 토글)이 동의 없이 내려지며, 보안 의식 높은 사용자일수록 위험한 우회로 내몰리는 역전이 있다. 모션은 정작 핵심 전환에서 연속성이 끊기고 Reduce Motion 대응이 전무하며, 토큰 시스템은 정의-적용 괴리가 크다.

---

## 우선순위 Top 10 실행 권고 (노력 대비 효과 순)

1. **우클릭 일괄 토글 제거/이전** — `MenuBarController.swift:40-50`의 rightMouseUp을 좌클릭과 같은 메뉴 표시로 통일하고, 메뉴에 '모든 즐겨찾기 켜기/끄기 (N개 활성)' 항목 추가. 36인이 지적한 최대 위험을 사실상 수 시간에 제거. (+ VoiceOver 경로도 함께 확보)
2. **원라이너 2건 즉시 수정** — `ForwardingRowView.swift` stateSubtitle의 .active 케이스에 serverPrefix 복원, `RemotePort.swift:22` scopeLabel에 `"*"` 케이스 추가('모든 인터페이스'). 각 한 줄로 다중 서버 식별 불가·원시값 노출 해결.
3. **메뉴바 메뉴 한국어 통일** — `MenuBarController.swift:81-201`과 `UpdatePresenter.swift`의 하드코딩 영어를 메인 윈도우와 같은 한국어로 교체('오류 N개'로 복수형 분기도 제거). String Catalog 도입은 후속 작업으로.
4. **`isRowHovering` 배선** — `ForwardingRowView.swift:57`의 죽은 상태를 행 배경 하이라이트 + ○→▶ 아이콘 전환에 연결. 이미 선언된 코드라 비용이 거의 없고 핵심 어포던스 문제 해소.
5. **에러 인라인 노출 + stderr 번역** — `ForwardingRowView.swift:115-119`의 hover 툴팁을 행 보조 텍스트 인라인 표시로 바꾸고, `PortBridgeError.swift`에서 흔한 stderr 패턴(Permission denied, bind, refused)을 한국어 원인+조치로 매핑(원문은 펼침). serverUnreachable의 버려지는 reason도 노출.
6. **업데이트 퍼널 연결** — `buildMenu()`에 'PortBridge vX.Y.Z 사용 가능 — 다운로드…' 항목을 조건부 추가하고, 배지를 CALayer 대신 MenuBarIconRenderer에 합성. accessibilityDescription에도 반영.
7. **호스트 키 검증 + 비-0 exit 침묵 금지** — `PortScanner.swift`/`TunnelManager.swift`에 'host key verification failed'/'identification has changed' 전용 에러를 매핑하고, 매핑 안 된 비-0 exit는 빈 목록이 아닌 .error로 노출. 보안상 가장 위험한 침묵 제거.
8. **터널 사망 알림 + 종료 보호** — `AppViewModel.swift` tunnelDidExit에 UserNotifications 알림, 메뉴 즐겨찾기 행에 .error 글리프(⚠), AppDelegate에 활성 포워딩 시 `applicationShouldTerminate` 확인 추가.
9. **키보드 경로 구축** — `ServerListView.swift`에 `.searchable`(또는 ⌘F→isSearchFocused 배선 + Esc 비우기), List selection + Return 토글 도입. 메뉴의 'Open Main Window ⌘O' 표기는 제거하거나 전역 핫키로 승격.
10. **메뉴 항목 정리 + Settings 씬** — favoriteTitle의 ●/○ 글리프 제거(NSMenuItem.state로 일원화), 타이틀을 '서버명 :포트'로 단순화, Launch at Login 등 설정류를 SwiftUI Settings 씬(⌘,)으로 이전해 메뉴를 즐겨찾기/Active/열기/종료로 압축.

---

## 잘하고 있는 점

- **에러 복구 설계의 기본기** — AuthFailedView의 복사 가능한 ssh-copy-id 명령, 배포판별 도구 설치 안내(ToolInstallGuideView), 포트 충돌 시트의 대체 포트 프리필과 인라인 검증은 거의 모든 분야에서 모범 사례로 인용됐다. "원인 + 해결 명령을 인라인으로"라는 이 패턴을 나머지 에러 경로로 확장하는 것이 처방의 골자일 만큼 좋은 본보기다.
- **타이포그래피와 토큰의 성실함** — 포트 번호의 monospacedDigit + trailing 정렬, WCAG 대비 근거를 주석으로 남긴 DesignTokens.swift, 채도·명도를 고정한 서버 모노그램(ServerMonogram)은 유틸리티 앱치고 드물게 성실하다는 평가(비주얼/타이포 분야).
- **플랫폼 기본기** — 직접 그린 템플릿 메뉴바 아이콘, 표준 NSMenu 채택, 충실한 .help 툴팁, 행 단위 accessibilityLabel/Hint/Value 합성과 장식 요소의 accessibilityHidden 처리, 상태별 accessibilityDescription은 인디 macOS 유틸리티 평균을 상회한다(Apple/접근성 분야 공통).
- **절제된 인터랙션 디자인** — 행 클릭 한 번으로 터널 토글이라는 코어 플로우, 활성 포워딩 개수를 세어주는 삭제 확인문, '포워딩 실패 — 클릭해 다시 시도' 같은 행동 지향 카피, 절제된 마이크로 모션, Sparkle 정석을 따른 3버튼 업데이트 다이얼로그가 긍정적으로 평가됐다.
- **SSH 구현의 신중함** — ExitOnForwardFailure 등 SSH 옵션 명시, 포트 노출 범위의 사용자 언어 번역 시도('모든 인터페이스'/'로컬 전용')는 이 카테고리 도구의 평균을 넘는 설계 의도로 인정받았다.