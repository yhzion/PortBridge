import Foundation

nonisolated struct FavoriteKey: Hashable, Codable {
    let serverId: UUID
    let remotePort: Int
}
