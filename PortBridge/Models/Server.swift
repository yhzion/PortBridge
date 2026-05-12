import Foundation

struct Server: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String?
    var user: String
    var host: String
    var port: Int

    init(id: UUID = UUID(), name: String? = nil, user: String, host: String, port: Int = 22) {
        self.id = id
        self.name = name
        self.user = user
        self.host = host
        self.port = port
    }

    var displayName: String {
        name.map { "\($0) (\(host))" } ?? host
    }

    var sshTarget: String { "\(user)@\(host)" }
}
