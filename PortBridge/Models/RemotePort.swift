import Foundation

struct RemotePort: Identifiable, Hashable {
    let port: Int
    let address: String
    let processName: String?

    var id: String { "\(address):\(port)" }
}
