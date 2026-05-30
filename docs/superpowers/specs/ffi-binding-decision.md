# FFI 바인딩 기술 결정 — UniFFI 채택 (#49)

- **상태**: 결정됨(Decided). 채택 = **UniFFI 0.28.x**. 후보 swift-bridge 탈락.
- **작성일**: 2026-05-30
- **이슈**: #49 (zone:ffi, grade:3 spike) · Epic #48
- **검증**: 두 기술로 `portbridge-core`의 `scan()` + payload-bearing `PortBridgeError`를 Swift에
  바인딩하는 최소 PoC를 macOS 26 / Swift 6.3.2 / Xcode 26.5 (arm64) 환경에서 **실제 빌드·실행**해
  측정. 추측 아님.

---

## 1. 결론 (1줄)

**UniFFI를 채택한다.** PortBridge가 실제로 필요로 하는 두 반환 형태 —
`Result<Vec<RemotePort>, PortBridgeError>`(= Swift `throws -> [RemotePortDto]`)와
payload-bearing 에러 enum — 가 UniFFI에서는 런타임까지 완전 동작(`RUN_EXIT=0`)했고,
swift-bridge 0.1.59에서는 **둘 다 깨졌다**(미구현 패닉 / 컴파일 불가 Swift 생성).

> **리스크**: UniFFI는 async/콜백-인터페이스를 이 spike에서 시험하지 않았다(scan은 동기).
> 향후 터널 생명주기(`ssh -L`)처럼 async/콜백이 필요하면 `#[uniffi::export(async)]`·
> callback-interface를 별도 검증해야 한다(다음 사이클).

## 2. 비교 점수 (1=나쁨 … 5=좋음, 실측)

| 항목 | UniFFI 0.28.3 | swift-bridge 0.1.59 |
|------|:---:|:---:|
| 바인딩 성숙도 | **5** | 2 |
| 에러 매핑(payload enum) | **5** | 3 |
| async/스레딩 | 2 *(미시험)* | 1 |
| 빌드 통합 | **4** | 2 |
| macOS 26 호환 | **5** | 3 |
| **Swift 호출 round-trip** | **yes (런타임 검증)** | partial (컴파일 불가) |

## 3. 결정적 차이 — PortBridge가 실제로 쓰는 반환 형태

`core::scan()`의 시그니처는 `Result<Vec<RemotePort>, PortBridgeError>`다. 이 두 형태를 각 기술이
어떻게 다루는지가 결정을 갈랐다.

### UniFFI — 둘 다 자연스럽게 동작
생성된 Swift(발췌, 실측):

```swift
public enum PortBridgeFfiError {
    case SshAuthFailed(host: String)
    case ServerUnreachable(host: String, reason: String)
    case RemoteToolsMissing
}
extension PortBridgeFfiError: Foundation.LocalizedError { ... }
extension PortBridgeFfiError: Foundation.Error {}      // = Swift Error
extension PortBridgeFfiError: Equatable, Hashable {}

public struct RemotePortDto {
    public var port: UInt16
    public var address: String
    public var processName: String?                    // Option<String> → String?
}

public func scanPorts(user: String, host: String, port: UInt16)
    throws -> [RemotePortDto]                           // Result<Vec<_>,E> → throws -> [_]
```

런타임 증명(swiftc 컴파일+링크+실행, `SWIFTC_EXIT=0`/`RUN_EXIT=0`):

```swift
do { _ = try scanPorts(user: "deploy", host: "prod", port: 0) }
catch let e as PortBridgeFfiError {
    case .ServerUnreachable(let host, let reason):
        print("CAUGHT ServerUnreachable host=\(host) reason=\(reason)")
}
// 출력: CAUGHT ServerUnreachable host=prod reason=command timed out
```

→ Rust `PortBridgeError::ServerUnreachable{host, reason}`의 **두 associated value가 손실 없이**
FFI 경계를 넘어 Swift `catch`에 도달했다.

### swift-bridge — 두 형태 모두 막힘
- **`Result<T, E>`를 extern-fn 반환으로 쓰면 미구현 패닉**: `swift-bridge-ir bridged_type.rs:1986
  todo!()` (0.1.59). scan의 반환을 그대로 표현 불가.
- **`Vec<SharedStruct>` 반환이 컴파일 안 되는 Swift 생성**: `-> RustVec<RemotePortFfi>`가
  `RemotePortFfi: Vectorizable`을 요구하는데 0.1.59가 그 구현을 생성하지 못함
  (`'RemotePortFfi' has no member 'len'` 등 Swift 컴파일 에러).
- (긍정) payload enum 자체와 `Option<String>`(struct 필드로서)은 잘 넘어갔으나, scan의 실제
  시그니처를 표현하지 못해 **부분 적합**에 그친다.
- 추가 마찰: `///` doc 주석이 IR 파서를 패닉시킴, field-bearing struct에 `swift_repr="struct"`
  강제, `RustString`/`RustVec`이 네이티브 `String`/`[T]`가 아니라 `.toString()` 변환 필요.

## 4. UniFFI 빌드 통합 — 기록된 마찰 (점수 4의 근거)

생산 도입(#56/#58) 시 그대로 적용할 운영 지식:

1. **`uniffi-bindgen`이 PATH에 없음** → 크레이트에 임베드 `[[bin]] name="uniffi-bindgen"`
   (`uniffi::uniffi_bindgen_main()` 호출, `features=["cli"]`)을 두고
   `cargo run --bin uniffi-bindgen -- generate --library <dylib> --language swift` 로 생성.
2. **워크스페이스 분리 필수** → spike 크레이트에 빈 `[workspace]` 테이블이 없으면 cargo가 루트로
   walk-up 해 루트 워크스페이스를 빌드한다(`no bin target named uniffi-bindgen ... available:
   portbridge`). 테이블 추가 후 `cargo locate-project --workspace`가 spike로 해석되고 루트
   `Cargo.toml`/`Cargo.lock`은 무변경(`git status --short` 빈 것으로 확인).
   - `portbridge-core`의 `[workspace.package]` 상속(`edition.workspace=true` 등)은 path-dep
     walk-up으로 자동 해결 — 추가 수정 불필요.
3. **swiftc C 모듈 배선** → 생성된 modulemap 파일명은 `<lib>FFI.modulemap`인데 이를
   `module.modulemap`으로 복사해 `<lib>FFI.h`와 같은 `-I` 디렉터리에 둬야 `import <lib>FFI`가 해석됨.
4. **Swift entrypoint 파일명은 `main.swift`** 여야 top-level `do/catch` 문이 허용됨.
   - (3)(4)는 수동 swiftc CLI 한정 마찰. 실제 Xcode 타깃은 build settings로 모듈을 배선하고 앱
     entrypoint를 쓰므로 해당 없음.

## 5. 인터페이스 컨벤션 (후속 #58 FFI-3 / macOS 전환 #59·#61·#62가 따를 규칙)

spike 실측에서 도출한 네이밍·경계 규칙. **core 타입을 직접 노출하지 않고 FFI 미러 타입을 둔다**
(UniFFI는 외부 크레이트 타입에 derive 불가하므로).

- **미러 타입**: core `RemotePort` → `#[derive(uniffi::Record)] RemotePortDto`,
  core `PortBridgeError` → `#[derive(uniffi::Error)] PortBridgeFfiError`. 각 미러는
  `From<코어타입>`을 구현해 1:1 변환(소비자 없는 추측성 필드 금지).
- **에러는 variant-for-variant 미러** + associated field 보존. Swift `catch let e as <Error>`로
  분기 가능해야 한다.
- **네이밍 비대칭(UniFFI 규칙, 반드시 인지)**:
  - 함수·Record 필드 → camelCase (`scanPorts`, `processName`).
  - enum **case** 이름 → Rust PascalCase 유지 (`.SshAuthFailed`/`.ServerUnreachable`).
    Swift `catch`에서 PascalCase case 이름을 써야 한다.
- **반환 규약**: 실패 가능 함수는 `Result<_, <Error>>` → Swift `throws`. 컬렉션은 `Vec<Record>` →
  `[Record]`. 선택값은 `Option<T>` → `T?`.
- **스칼라 매핑**: `u16` → `UInt16` 등 정수 폭 보존.
- **워크스페이스 등록 경계**: 크레이트 본체(타입·export)는 zone:ffi. 루트 `Cargo.toml`/`Cargo.lock`
  등록은 #56 REG-FFI 단독 소유(serial-only). FFI-3(#58)는 등록된 크레이트 위에서 코드만 추가.
- **parity 책임 분리**: FFI 레이어 단독 round-trip 단위 테스트(에러 3-variant 왕복 보존)는
  zone:ffi(#58 DoD)에서, "Swift import 실검증"은 macOS 툴체인이 필요하므로 #59 / CI(#60)에서.

## 6. 채택 버전·의존

- `uniffi = "0.28"` (features: 런타임/`cli`; build-dep `build`).
- 미러 타입의 `Display`/`Error`는 `thiserror`로 작성(spike 검증 구성). 생산에서 thiserror 도입
  여부는 #58에서 확정(불필요하면 수동 `Display`+`Error`로 대체 가능).
- crate-type: `["cdylib", "staticlib", "lib"]`.

## 7. 다음 단계

1. **#56 REG-FFI** — `crates/portbridge-ffi/`를 루트 워크스페이스에 정식 등록(빈 `[workspace]`
   제거 + 루트 members 추가) + uniffi 의존 벤더(루트 `Cargo.lock` 변동 흡수).
2. **#58 FFI-3** — scan() 생산용 바인딩 + `PortBridgeError` 3-variant FFI 라운드트립 단위 테스트.
3. **#59/#61/#62** — macOS Swift 측을 본 컨벤션대로 FFI 경유 전환 + parity 게이트.
