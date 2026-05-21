import Foundation

nonisolated struct RemotePort: Identifiable, Hashable {
    let port: Int
    let address: String
    let processName: String?

    var id: String { "\(address):\(port)" }

    var displayLine: String {
        let base = ":\(port) · \(scopeLabel)"
        guard let processName, !processName.isEmpty else { return base }
        return "\(base) · \(processName)"
    }

    private var scopeLabel: String {
        switch address {
        case "0.0.0.0", "::": return "모든 인터페이스"
        case "127.0.0.1", "::1": return "로컬 전용"
        default: return address
        }
    }
}
