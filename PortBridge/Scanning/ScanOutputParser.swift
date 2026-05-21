import Foundation

nonisolated enum ScanOutputParser {
    static func parseSS(_ output: String) -> [RemotePort] {
        var results: [RemotePort] = []
        for raw in output.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let firstWord = line.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
            if firstWord.uppercased() != "LISTEN" { continue }

            let cols = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard cols.count >= 4 else { continue }
            let localAddr = cols[3]

            guard let (addr, port) = splitAddressPort(localAddr) else { continue }
            let procName = extractProcessName(line)
            results.append(RemotePort(port: port, address: addr, processName: procName))
        }
        return results
    }

    static func parseLsof(_ output: String) -> [RemotePort] {
        var results: [RemotePort] = []
        let lines = output.components(separatedBy: .newlines)
        for (idx, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if idx == 0 && line.uppercased().hasPrefix("COMMAND") { continue }
            guard line.contains("(LISTEN)") else { continue }

            let cols = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard cols.count >= 10 else { continue }
            let command = cols[0]
            let name = cols[8]
            let processName = command == "-" ? nil : command

            let normalized = name.replacingOccurrences(of: "*", with: "0.0.0.0")
            guard let (addr, port) = splitAddressPort(normalized) else { continue }
            results.append(RemotePort(port: port, address: addr, processName: processName))
        }
        return results
    }

    fileprivate static func splitAddressPort(_ s: String) -> (String, Int)? {
        if s.hasPrefix("[") {
            guard let close = s.firstIndex(of: "]") else { return nil }
            let addr = String(s[s.index(after: s.startIndex)..<close])
            let afterClose = s.index(after: close)
            guard afterClose < s.endIndex, s[afterClose] == ":" else { return nil }
            let portStr = String(s[s.index(after: afterClose)...])
            guard let port = Int(portStr) else { return nil }
            return (addr, port)
        } else {
            guard let colon = s.lastIndex(of: ":") else { return nil }
            let addr = String(s[..<colon])
            let portStr = String(s[s.index(after: colon)...])
            guard let port = Int(portStr) else { return nil }
            return (addr, port)
        }
    }

    private static func extractProcessName(_ line: String) -> String? {
        guard let usersRange = line.range(of: "users:((") else { return nil }
        let rest = line[usersRange.upperBound...]
        guard let quoteStart = rest.firstIndex(of: "\"") else { return nil }
        let afterQuote = rest.index(after: quoteStart)
        guard let quoteEnd = rest[afterQuote...].firstIndex(of: "\"") else { return nil }
        return String(rest[afterQuote..<quoteEnd])
    }
}
