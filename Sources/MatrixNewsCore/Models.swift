import Foundation

public enum NewsCategory: String, Codable, CaseIterable, Sendable {
    case politics
    case economy
    case society
    case international
    case culture
    case technology
    case sports
    case entertainment
    case other

    public static func fromRSSValue(_ value: String?, fallback: [NewsCategory] = []) -> NewsCategory {
        let normalized = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized.contains("정치") || normalized.contains("politic") {
            return .politics
        }
        if normalized.contains("경제") || normalized.contains("business") || normalized.contains("econom") {
            return .economy
        }
        if normalized.contains("사회") || normalized.contains("social") {
            return .society
        }
        if normalized.contains("국제") || normalized.contains("세계") || normalized.contains("world") || normalized.contains("international") {
            return .international
        }
        if normalized.contains("문화") || normalized.contains("생활") || normalized.contains("culture") {
            return .culture
        }
        if normalized.contains("과학") || normalized.contains("it") || normalized.contains("tech") {
            return .technology
        }
        if normalized.contains("스포츠") || normalized.contains("sport") {
            return .sports
        }
        if normalized.contains("연예") || normalized.contains("entertain") {
            return .entertainment
        }

        return fallback.count == 1 ? (fallback.first ?? .other) : .other
    }
}

public enum LicenseStatus: String, Codable, Sendable {
    case unlicensed
    case testOnly = "test-only"
    case licensed
}

public struct NewsItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var sourceID: String
    public var sourceName: String
    public var url: URL
    public var publishedAt: Date
    public var category: NewsCategory
    public var summary: String?
    public var keywords: [String]

    public init(
        id: String,
        title: String,
        sourceID: String,
        sourceName: String,
        url: URL,
        publishedAt: Date,
        category: NewsCategory,
        summary: String? = nil,
        keywords: [String]
    ) {
        self.id = id
        self.title = title
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.url = url
        self.publishedAt = publishedAt
        self.category = category
        self.summary = summary
        self.keywords = keywords
    }

    public static func makeID(sourceID: String, url: URL, title: String) -> String {
        let normalizedURL = URLNormalizer.normalizedURLString(url)
        return StableHash.hexDigest("\(sourceID)|\(normalizedURL)|\(title.normalizedForMatching)")
    }
}

public struct NewsSource: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var feedURL: URL
    public var homepageURL: URL
    public var defaultEnabled: Bool
    public var licenseStatus: LicenseStatus
    public var categories: [NewsCategory]

    public init(
        id: String,
        displayName: String,
        feedURL: URL,
        homepageURL: URL,
        defaultEnabled: Bool,
        licenseStatus: LicenseStatus,
        categories: [NewsCategory]
    ) {
        self.id = id
        self.displayName = displayName
        self.feedURL = feedURL
        self.homepageURL = homepageURL
        self.defaultEnabled = defaultEnabled
        self.licenseStatus = licenseStatus
        self.categories = categories
    }

    public func resolvedFeedURL(currentYear: Int) -> URL {
        let resolvedString = feedURL.absoluteString
            .replacingOccurrences(of: "@@YEAR@@", with: String(currentYear))
        return URL(string: resolvedString) ?? feedURL
    }
}

public struct NewsFeedManifest: Codable, Equatable, Sendable {
    public var version: Int
    public var generatedAt: Date
    public var latestURL: URL
    public var sourcesURL: URL
    public var itemCount: Int

    public init(
        version: Int,
        generatedAt: Date,
        latestURL: URL,
        sourcesURL: URL,
        itemCount: Int
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.latestURL = latestURL
        self.sourcesURL = sourcesURL
        self.itemCount = itemCount
    }
}

public struct LatestNewsPayload: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var items: [NewsItem]

    public init(generatedAt: Date, items: [NewsItem]) {
        self.generatedAt = generatedAt
        self.items = items
    }
}

public struct ViewerSettings: Codable, Equatable, Sendable {
    public var scrollSpeed: Double
    public var visibleNewsCount: Int
    public var fontSize: Double
    public var fontFamily: String
    public var enabledSourceIDs: Set<String>

    public init(
        scrollSpeed: Double,
        visibleNewsCount: Int,
        fontSize: Double,
        fontFamily: String,
        enabledSourceIDs: Set<String>
    ) {
        self.scrollSpeed = scrollSpeed
        self.visibleNewsCount = visibleNewsCount
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.enabledSourceIDs = enabledSourceIDs
        normalize()
    }

    public static let `default` = ViewerSettings(
        scrollSpeed: 3.5,
        visibleNewsCount: 8,
        fontSize: 26,
        fontFamily: "SF Mono",
        enabledSourceIDs: []
    )

    public mutating func normalize() {
        scrollSpeed = min(max(scrollSpeed, 0.5), 12)
        visibleNewsCount = min(max(visibleNewsCount, 1), 16)
        fontSize = min(max(fontSize, 14), 72)
    }

    public mutating func reconcileEnabledSources(_ sources: [NewsSource]) {
        let availableSourceIDs = Set(sources.map(\.id))
        enabledSourceIDs = enabledSourceIDs.intersection(availableSourceIDs)

        if enabledSourceIDs.isEmpty {
            enabledSourceIDs = Set(sources.filter(\.defaultEnabled).map(\.id))
        }
    }
}
