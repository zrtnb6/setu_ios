import Foundation

public struct JmAlbum: Decodable, Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let author: String?
    public let coverURL: String?
    public let tags: [String]
    public let description: String?
    public let likes: String?
    public let chapters: [JmChapter]

    public var subtitle: String {
        [author, tags.prefix(2).joined(separator: " / ")].compactMap { value in
            value?.isEmpty == false ? value : nil
        }.joined(separator: " · ")
    }

    public var favoriteSnapshot: ModuleFavoriteSnapshot {
        ModuleFavoriteSnapshot(
            module: .jm,
            externalId: id,
            title: title,
            coverUrl: coverURL,
            subtitle: subtitle
        )
    }

    public var watchRecord: ModuleWatchRecord {
        ModuleWatchRecord(module: .jm, externalId: id, title: title, coverUrl: coverURL, subtitle: subtitle)
    }

    public init(
        id: String,
        title: String,
        author: String? = nil,
        coverURL: String? = nil,
        tags: [String] = [],
        description: String? = nil,
        likes: String? = nil,
        chapters: [JmChapter] = []
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverURL = coverURL
        self.tags = tags
        self.description = description
        self.likes = likes
        self.chapters = chapters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .title)
            ?? "未命名本子"
        author = Self.decodeAuthor(container)
        coverURL = [
            try container.decodeIfPresent(String.self, forKey: .cover),
            try container.decodeIfPresent(String.self, forKey: .mainImage),
            try container.decodeIfPresent(String.self, forKey: .image),
        ].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }.first
        tags = Self.decodeTags(container)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        likes = Self.decodeLikes(container)
        let series = try container.decodeIfPresent([JmSeriesNode].self, forKey: .series) ?? []
        let albumTitle = title
        let albumID = id
        if series.isEmpty {
            chapters = [JmChapter(id: albumID, title: albumTitle)]
        } else {
            chapters = series.map { node in
                JmChapter(id: node.id, title: node.name ?? albumTitle)
            }
        }
    }

    private static func decodeLikes(_ container: KeyedDecodingContainer<CodingKeys>) -> String? {
        if let text = try? container.decode(String.self, forKey: .likes) {
            return text
        }
        if let number = try? container.decode(Int.self, forKey: .likes) {
            return String(number)
        }
        if let liked = try? container.decode(Int.self, forKey: .liked) {
            return String(liked)
        }
        return nil
    }

    private static func decodeAuthor(_ container: KeyedDecodingContainer<CodingKeys>) -> String? {
        if let authors = try? container.decode([String].self, forKey: .author) {
            return authors.joined(separator: " / ")
        }
        return try? container.decode(String.self, forKey: .author)
    }

    private static func decodeTags(_ container: KeyedDecodingContainer<CodingKeys>) -> [String] {
        if let tags = try? container.decode([String].self, forKey: .tags) {
            return tags.filter { !$0.isEmpty }
        }
        if let tags = try? container.decode(String.self, forKey: .tags) {
            return tags.split { $0 == "," || $0 == "，" || $0 == "/" }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return []
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, title, author, tags, description, likes, liked, series, image
        case cover
        case mainImage = "main_image"
    }
}

public struct JmChapter: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct JmAlbumPage: Sendable {
    public let page: Int
    public let total: Int
    public let albums: [JmAlbum]

    public init(page: Int, total: Int, albums: [JmAlbum]) {
        self.page = page
        self.total = total
        self.albums = albums
    }
}

public struct JmPageImage: Identifiable, Sendable, Hashable {
    public let id: String
    public let url: URL
    public let albumID: Int
    public let scrambleID: Int

    public init(id: String, url: URL, albumID: Int, scrambleID: Int) {
        self.id = id
        self.url = url
        self.albumID = albumID
        self.scrambleID = scrambleID
    }
}

struct JmSeriesNode: Decodable, Sendable {
    let id: String
    let name: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }

    private enum CodingKeys: String, CodingKey { case id, name }
}

struct JmListEnvelope: Decodable {
    let list: [JmAlbum]?
    let content: [JmAlbum]?
    let total: Int?
    let redirectAID: String?

    var albums: [JmAlbum] { list ?? content ?? [] }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        list = container.decodeLossyArray(forKey: .list)
        content = container.decodeLossyArray(forKey: .content)
        total = container.decodeFlexibleIntIfPresent(forKey: .total)
        redirectAID = try? container.decodeFlexibleString(forKey: .redirectAID)
    }

    private enum CodingKeys: String, CodingKey {
        case list, content, total
        case redirectAID = "redirect_aid"
    }
}

struct JmChapterEnvelope: Decodable {
    let id: String?
    let images: [String]?
    let scrambleID: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeFlexibleString(forKey: .id)
        images = try container.decodeIfPresent([String].self, forKey: .images)
        scrambleID = try container.decodeIfPresent(Int.self, forKey: .scrambleId)
            ?? container.decodeIfPresent(Int.self, forKey: .scramble_id)
    }

    private enum CodingKeys: String, CodingKey {
        case id, images
        case scrambleId
        case scramble_id
    }
}

private struct LossyDecoded<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

extension KeyedDecodingContainer {
    func decodeFlexibleString(forKey key: Key) throws -> String {
        if let value = try? decode(String.self, forKey: key), !value.isEmpty { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing id"))
    }

    func decodeFlexibleIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let raw = try? decode(String.self, forKey: key), let value = Int(raw) { return value }
        return nil
    }

    func decodeLossyArray(forKey key: Key) -> [JmAlbum]? {
        guard contains(key) else { return nil }
        return (try? decode([LossyDecoded<JmAlbum>].self, forKey: key))?.compactMap(\.value)
    }
}
