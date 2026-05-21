import Foundation
import Observation

@MainActor
@Observable
final class FavoriteStore {
    private(set) var favorites: Set<FavoriteKey> = []
    private let defaultsKey = "PortBridge.Favorites.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func add(_ key: FavoriteKey) {
        guard !favorites.contains(key) else { return }
        favorites.insert(key)
        save()
    }

    func remove(_ key: FavoriteKey) {
        guard favorites.contains(key) else { return }
        favorites.remove(key)
        save()
    }

    func toggle(_ key: FavoriteKey) {
        if favorites.contains(key) {
            remove(key)
        } else {
            add(key)
        }
    }

    func contains(_ key: FavoriteKey) -> Bool {
        favorites.contains(key)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Array(favorites)) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([FavoriteKey].self, from: data) else { return }
        favorites = Set(decoded)
    }
}
