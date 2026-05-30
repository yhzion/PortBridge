import Foundation

nonisolated struct Forwarding: Identifiable, Equatable {
    enum State: Equatable {
        case idle
        case starting
        case active
        case error(String)
    }

    let id: UUID
    let serverId: UUID
    let remotePort: Int
    var localPort: Int
    var state: State
    var activatedAt: Date?

    init(
        id: UUID = UUID(),
        serverId: UUID,
        remotePort: Int,
        localPort: Int,
        state: State,
        activatedAt: Date? = nil
    ) {
        self.id = id
        self.serverId = serverId
        self.remotePort = remotePort
        self.localPort = localPort
        self.state = state
        self.activatedAt = activatedAt
    }
}
