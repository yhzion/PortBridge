import Foundation
import Observation

@Observable
final class ServerStore {
    private(set) var servers: [Server] = []
    private let defaultsKey = "portbridge.servers"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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

    /// `(user, host, port)` 3튜플이 동일한 서버가 이미 있는지 검사.
    /// 편집 시에는 `excluding`에 자기 자신의 id를 전달해 자기 자신과의 비교를 제외한다.
    /// 같은 호스트에 다른 user 혹은 다른 port를 두는 사용 케이스는 정당하므로 중복으로 보지 않는다.
    func isDuplicate(user: String, host: String, port: Int, excluding id: UUID? = nil) -> Bool {
        servers.contains { server in
            server.id != id && server.user == user && server.host == host && server.port == port
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([Server].self, from: data) else { return }
        servers = decoded
    }
}
