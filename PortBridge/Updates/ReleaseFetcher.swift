import Foundation

enum UpdateCheckError: Error, Equatable {
    case network(URLError)
    case httpStatus(Int)
    case decoding(String)
    case invalidResponse
}

protocol ReleaseFetcher: Sendable {
    func fetchLatest() async throws -> ReleaseInfo
}

struct GitHubReleaseFetcher: ReleaseFetcher {
    let owner: String
    let repo: String
    let session: URLSession
    let currentAppVersion: String

    init(owner: String,
         repo: String,
         currentAppVersion: String,
         session: URLSession = .shared) {
        self.owner = owner
        self.repo = repo
        self.currentAppVersion = currentAppVersion
        self.session = session
    }

    func fetchLatest() async throws -> ReleaseInfo {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("PortBridge/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw UpdateCheckError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UpdateCheckError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UpdateCheckError.httpStatus(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(ReleaseInfo.self, from: data)
        } catch {
            throw UpdateCheckError.decoding(String(describing: error))
        }
    }
}
