import Foundation
import Observation

@Observable
final class ServerStore {
    private(set) var servers: [Server] = []
    private let defaultsKey = "portbridge.servers"

    init() {
        load()
    }

    func add(_ server: Server) {
        servers.append(server)
        save()
    }

    func update(_ server: Server) {
        guard let idx = servers.firstIndex(where: { $0.id == server.id }) else { return }
        servers[idx] = server
        save()
    }

    func delete(_ server: Server) {
        servers.removeAll { $0.id == server.id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([Server].self, from: data) else { return }
        servers = decoded
    }
}
