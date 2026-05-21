import Foundation

struct ReleaseInfo: Decodable, Equatable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let publishedAt: Date?
    let body: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case body
    }

    var version: SemanticVersion? {
        SemanticVersion(string: tagName)
    }
}
