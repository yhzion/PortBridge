import Foundation

struct Forwarding: Identifiable, Equatable {
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

    init(
        id: UUID = UUID(),
        serverId: UUID,
        remotePort: Int,
        localPort: Int,
        state: State
    ) {
        self.id = id
        self.serverId = serverId
        self.remotePort = remotePort
        self.localPort = localPort
        self.state = state
    }
}
