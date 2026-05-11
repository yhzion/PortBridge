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
            case "include":
                flush()
                for value in values {
                    let expanded = expandIncludePath(value, relativeTo: resolved)
                    for matched in expanded {
                        let sub = try parseRecursive(path: matched, visited: &visited)
                        results.append(contentsOf: sub)
                    }
                }
            default:
                break
            }
        }
        flush()

        return results
    }

    private static func expandIncludePath(_ pattern: String, relativeTo configFile: URL) -> [URL] {
        let expanded = (pattern as NSString).expandingTildeInPath
        let base: URL
        if expanded.hasPrefix("/") {
            base = URL(fileURLWithPath: expanded)
        } else {
            base = configFile.deletingLastPathComponent().appending(path: expanded)
        }

        if !expanded.contains("*") && !expanded.contains("?") {
            return [base]
        }

        let dir = base.deletingLastPathComponent()
        let glob = base.lastPathComponent
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return []
        }
        return entries
            .filter { fnmatch(glob, $0) }
            .map { dir.appending(path: $0) }
    }

    private static func fnmatch(_ pattern: String, _ name: String) -> Bool {
        let p = Array(pattern)
        let n = Array(name)
        return globMatch(p, 0, n, 0)
    }

    private static func globMatch(_ p: [Character], _ pi: Int, _ s: [Character], _ si: Int) -> Bool {
        if pi == p.count { return si == s.count }
        if p[pi] == "*" {
            if pi + 1 == p.count { return true }
            var k = si
            while k <= s.count {
                if globMatch(p, pi + 1, s, k) { return true }
                k += 1
            }
            return false
        }
        if si == s.count { return false }
        if p[pi] == "?" || p[pi] == s[si] {
            return globMatch(p, pi + 1, s, si + 1)
        }
        return false
    }
}
