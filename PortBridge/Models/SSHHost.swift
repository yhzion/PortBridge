import Foundation

struct SSHHost: Identifiable, Hashable {
    let name: String
    var hostName: String? = nil
    var user: String? = nil
    var port: Int? = nil

    var id: String { name }
}
