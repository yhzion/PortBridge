import Foundation

nonisolated struct ReleaseInfo: Decodable, Equatable {
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

    /// Bridges to the FFI DTO so core (`updateAvailable`) can judge this release.
    /// Core reads `tag_name` for the verdict; the remaining fields are mapped
    /// faithfully for completeness.
    var ffiDto: ReleaseInfoDto {
        ReleaseInfoDto(
            tagName: tagName,
            name: name,
            htmlUrl: htmlURL.absoluteString,
            publishedAt: publishedAt?.formatted(.iso8601),
            body: body
        )
    }
}
