// PortBridgeTests/ServerSectionRowIDTests.swift
@testable import PortBridge
import XCTest

/// 회귀 방지: 여러 서버가 같은 포트를 같은 주소로 노출할 때, List 행 정체성이 서버 단위로
/// 유일해야 한다. 그렇지 않으면(`RemotePort.id`="address:port"만 사용) 한 List 안에서 id가
/// 충돌해 SwiftUI가 탭/뷰를 엉뚱한 서버 행에 재사용한다(원래 버그).
@MainActor
final class ServerSectionRowIDTests: XCTestCase {
    func test_samePortDifferentServers_haveDistinctRowIDs() {
        let serverA = UUID()
        let serverB = UUID()
        let port = RemotePort(port: 5173, address: "0.0.0.0", processName: nil)

        let idA = ServerSectionView.rowID(serverID: serverA, port: port)
        let idB = ServerSectionView.rowID(serverID: serverB, port: port)

        XCTAssertNotEqual(idA, idB, "같은 포트라도 서버가 다르면 행 정체성이 달라야 한다")
    }

    func test_rowID_isStableForSameServerAndPort() {
        let server = UUID()
        let port = RemotePort(port: 8080, address: "127.0.0.1", processName: "nginx")

        XCTAssertEqual(
            ServerSectionView.rowID(serverID: server, port: port),
            ServerSectionView.rowID(serverID: server, port: port),
            "동일 서버·포트는 안정적으로 같은 정체성을 가져야 한다"
        )
    }

    func test_differentPortsSameServer_haveDistinctRowIDs() {
        let server = UUID()
        let p1 = RemotePort(port: 5173, address: "0.0.0.0", processName: nil)
        let p2 = RemotePort(port: 5174, address: "0.0.0.0", processName: nil)

        XCTAssertNotEqual(
            ServerSectionView.rowID(serverID: server, port: p1),
            ServerSectionView.rowID(serverID: server, port: p2)
        )
    }
}
