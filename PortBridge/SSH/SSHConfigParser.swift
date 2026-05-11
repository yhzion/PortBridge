import Foundation

enum SSHConfigParser {
    static func parse(
        path: URL = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".ssh/config")
    ) throws -> [SSHHost] {
        var visited = Set<URL>()
        return try parseRecursive(path: path, visited: &visited)
    }

    private static func parseRecursive(path: URL, visited: inout Set<URL>) throws -> [SSHHost] {
        let resolved = path.standardizedFileURL
        guard !visited.contains(resolved) else { return [] }
        visited.insert(resolved)

        guard FileManager.default.fileExists(atPath: resolved.path) else {
            throw PortBridgeError.sshConfigNotFound
        }

        let content: String
        do {
            content = try String(contentsOf: resolved, encoding: .utf8)
        } catch {
            throw PortBridgeError.sshConfigUnreadable(error.localizedDescription)
        }

        var results: [SSHHost] = []
        var current: [String]? = nil
        var currentOptions: [String: String] = [:]

        func flush() {
            guard let names = current else { return }
            for name in names where !name.contains("*") && !name.contains("?") && !name.contains("!") {
                results.append(SSHHost(
                    name: name,
                    hostName: currentOptions["hostname"],
                    user: currentOptions["user"],
                    port: currentOptions["port"].flatMap { Int($0) }
                ))
            }
            current = nil
            currentOptions = [:]
        }

        for raw in content.components(separatedBy: .newlines) {
            let line = raw.split(separator: "#", maxSplits: 1).first.map(String.init) ?? raw
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2 else { continue }
            let keyword = parts[0].lowercased()
            let values = Array(parts[1...])

            switch keyword {
            case "host":
                flush()
                current = values
            case "hostname", "user", "port":
                currentOptions[keyword] = values.first
            default:
                break
            }
        }
        flush()

        return results
    }
}
