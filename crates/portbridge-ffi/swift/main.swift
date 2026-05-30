// PoC 소비자 — UniFFI 바인딩이 (1) payload-bearing 에러를 Swift catch로 전달하고
// (2) Record/Optional을 자연스럽게 노출함을 런타임으로 증명한다.
//
// 빌드/실행 (crates/portbridge-ffi/ 에서):
//   cargo build
//   cargo run --bin uniffi-bindgen -- generate --library target/debug/libportbridge_ffi.dylib \
//     --language swift --out-dir generated
//   mkdir -p ffimod && cp generated/portbridge_ffiFFI.h ffimod/ \
//     && cp generated/portbridge_ffiFFI.modulemap ffimod/module.modulemap
//   swiftc -emit-executable -o poc_exe swift/main.swift generated/portbridge_ffi.swift \
//     -I ffimod -L target/debug -lportbridge_ffi
//   DYLD_LIBRARY_PATH=target/debug ./poc_exe
// 기대 출력:
//   PORT 8080 addr=0.0.0.0 proc=nginx
//   CAUGHT ServerUnreachable host=prod reason=command timed out

import Foundation

#if canImport(portbridge_ffiFFI)
    import portbridge_ffiFFI
#endif

func runOk() {
    do {
        let ports = try scanPorts(user: "deploy", host: "prod", port: 8080)
        for p in ports {
            print("PORT \(p.port) addr=\(p.address) proc=\(p.processName ?? "nil")")
        }
    } catch {
        print("UNEXPECTED \(error)")
    }
}

func runErr() {
    do {
        _ = try scanPorts(user: "deploy", host: "prod", port: 0)
    } catch let e as PortBridgeFfiError {
        switch e {
        case .ServerUnreachable(let host, let reason):
            print("CAUGHT ServerUnreachable host=\(host) reason=\(reason)")
        default:
            print("CAUGHT other \(e)")
        }
    } catch {
        print("UNEXPECTED \(error)")
    }
}

runOk()
runErr()
