import Foundation

protocol ServerRepository: Sendable {
    func loadServers() throws -> [ServerRecord]
    func saveServers(_ servers: [ServerRecord]) throws
}

final class UserDefaultsServerRepository: ServerRepository, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "mobidex.servers.v3"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadServers() throws -> [ServerRecord] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }
        return try JSONDecoder().decode([ServerRecord].self, from: data)
    }

    func saveServers(_ servers: [ServerRecord]) throws {
        let data = try JSONEncoder().encode(servers)
        defaults.set(data, forKey: key)
    }
}

final class InMemoryServerRepository: ServerRepository, @unchecked Sendable {
    private var servers: [ServerRecord]
    private let lock = NSLock()

    init(servers: [ServerRecord] = []) {
        self.servers = servers
    }

    func loadServers() throws -> [ServerRecord] {
        lock.withLock { servers }
    }

    func saveServers(_ servers: [ServerRecord]) throws {
        lock.withLock {
            self.servers = servers
        }
    }
}
