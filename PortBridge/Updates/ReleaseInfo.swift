import Foundation

struct ReleaseInfo: Decodable, Equatable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let publishedAt: Date?
    let body: String?

    var version: SemanticVersion? {
        SemanticVersion(string: tagName)
    }
}
