// PoC 소비자 — UniFFI 바인딩이 (1) Swift가 FfiCommandRunner(foreign trait)를 구현해
// 주입하고, (2) payload-bearing 에러를 Swift catch로 전달하며, (3) Record/Optional을
// 자연스럽게 노출함을 보인다. 실제 swiftc 컴파일/실행은 #59(macOS 툴체인) 소관이며,
// 여기서는 생성 바인딩(scanPorts(runner:server:))과의 소스 정합만 보장한다.
//
// 바인딩 생성 (crates/portbridge-ffi/ 에서):
//   cargo build -p portbridge-ffi
//   cargo run -p portbridge-ffi --bin uniffi-bindgen -- generate \
//     --library ../../target/debug/libportbridge_ffi.dylib --language swift --out-dir <dir>
//
// 생성된 시그니처:
//   func scanPorts(runner: FfiCommandRunner, server: ServerDto) throws -> [RemotePortDto]
//   protocol FfiCommandRunner { func run(executable:args:timeout:) throws -> CommandResultDto }

import Foundation

#if canImport(portbridge_ffiFFI)
    import portbridge_ffiFFI
#endif

// happy 경로: exit 0 + ss LISTEN 라인을 돌려주는 러너.
final class OkRunner: FfiCommandRunner {
    func run(executable: String, args: [String], timeout: TimeInterval) throws -> CommandResultDto {
        CommandResultDto(
            exitCode: 0,
            stdout: "LISTEN 0 128 0.0.0.0:8080 0.0.0.0:* users:((\"nginx\",pid=1,fd=1))\n",
            stderr: ""
        )
    }
}

// error 경로: exit 255 + publickey stderr → core가 SshAuthFailed로 분류.
final class AuthFailRunner: FfiCommandRunner {
    func run(executable: String, args: [String], timeout: TimeInterval) throws -> CommandResultDto {
        CommandResultDto(exitCode: 255, stdout: "", stderr: "Permission denied (publickey).")
    }
}

func server() -> ServerDto {
    ServerDto(id: "deploy@prod", name: nil, user: "deploy", host: "prod", port: 22)
}

func runOk() {
    do {
        let ports = try scanPorts(runner: OkRunner(), server: server())
        for p in ports {
            print("PORT \(p.port) addr=\(p.address) proc=\(p.processName ?? "nil")")
        }
    } catch {
        print("UNEXPECTED \(error)")
    }
}

func runErr() {
    do {
        _ = try scanPorts(runner: AuthFailRunner(), server: server())
    } catch let e as PortBridgeFfiError {
        switch e {
        case .SshAuthFailed(let host):
            print("CAUGHT SshAuthFailed host=\(host)")
        default:
            print("CAUGHT other \(e)")
        }
    } catch {
        print("UNEXPECTED \(error)")
    }
}

runOk()
runErr()
