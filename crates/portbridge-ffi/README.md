# portbridge-ffi (spike — #49)

> **상태: spike (PoC).** FFI 바인딩 기술 결정(#49)을 위한 최소 검증 크레이트.
> 정식 워크스페이스 등록·생산용 바인딩 노출은 후속 이슈(#56 REG-FFI, #58 FFI-3) 소관.
> 결정 근거: [`docs/superpowers/specs/ffi-binding-decision.md`](../../docs/superpowers/specs/ffi-binding-decision.md).

## 무엇을 증명하는가

`portbridge-core`의 `scan()`(제네릭)을 구체 래퍼 `scan_ports(user, host, port)`로 감싸
**UniFFI**로 Swift에 바인딩한다. 핵심 검증 대상:

- payload-bearing `PortBridgeError`(`SshAuthFailed{host}`, `ServerUnreachable{host,reason}`,
  `RemoteToolsMissing`) → Swift `enum: Error`로 **associated value 보존**.
- `Result<Vec<RemotePort>, PortBridgeError>` → Swift `throws -> [RemotePortDto]`.
- `Option<String>` → Swift `String?`.

## 워크스페이스 분리

`Cargo.toml`의 빈 `[workspace]` 테이블이 이 크레이트를 루트 PortBridge 워크스페이스에서
분리한다. 따라서 루트 `Cargo.toml`/`Cargo.lock`을 **건드리지 않는다**(§4 픽업 조건: 그 zone만으로
독립 빌드). `git status --short`로 루트 매니페스트 무변경을 확인할 수 있다.

## 빌드 + 바인딩 생성 + 실행

```bash
cd crates/portbridge-ffi

# 1) Rust 빌드 (cdylib + staticlib + rlib)
cargo build

# 2) Swift 바인딩 생성 (uniffi-bindgen은 PATH에 없어 임베드 bin 사용)
cargo run --bin uniffi-bindgen -- \
  generate --library target/debug/libportbridge_ffi.dylib \
  --language swift --out-dir generated

# 3) swiftc용 C 모듈 배선 (modulemap은 portbridge_ffiFFI.modulemap → module.modulemap 으로 복사)
mkdir -p ffimod
cp generated/portbridge_ffiFFI.h ffimod/
cp generated/portbridge_ffiFFI.modulemap ffimod/module.modulemap

# 4) Swift 소비자 컴파일 + 실행 (entrypoint 파일명은 main.swift 여야 함)
cp swift/main.swift ./main.swift
swiftc -emit-executable -o poc_exe main.swift generated/portbridge_ffi.swift \
  -I ffimod -L target/debug -lportbridge_ffi
DYLD_LIBRARY_PATH=target/debug ./poc_exe
```

기대 출력:

```
PORT 8080 addr=0.0.0.0 proc=nginx
CAUGHT ServerUnreachable host=prod reason=command timed out
```

`generated/`, `target/`, `ffimod/`, `poc_exe`, `Cargo.lock`은 `.gitignore` 대상(빌드 산출물).
