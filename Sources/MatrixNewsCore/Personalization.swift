import Foundation

public struct UserPreferences: Codable, Equatable, Sendable {
    public var likedItemIDs: Set<String>
    public var savedItemIDs: Set<String>
    public var hiddenItemIDs: Set<String>
    public var blockedSourceIDs: Set<String>
    public var boostedSourceScores: [String: Double]
    public var boostedCategoryScores: [String: Double]
    public var boostedKeywordScores: [String: Double]
    public var suppressedCategoryScores: [String: Double]
    public var suppressedKeywordScores: [String: Double]

    public init(
        likedItemIDs: Set<String> = [],
        savedItemIDs: Set<String> = [],
        hiddenItemIDs: Set<String> = [],
        blockedSourceIDs: Set<String> = [],
        boostedSourceScores: [String: Double] = [:],
        boostedCategoryScores: [String: Double] = [:],
        boostedKeywordScores: [String: Double] = [:],
        suppressedCategoryScores: [String: Double] = [:],
        suppressedKeywordScores: [String: Double] = [:]
    ) {
        self.likedItemIDs = likedItemIDs
        self.savedItemIDs = savedItemIDs
        self.hiddenItemIDs = hiddenItemIDs
        self.blockedSourceIDs = blockedSourceIDs
        self.boostedSourceScores = boostedSourceScores
        self.boostedCategoryScores = boostedCategoryScores
        self.boostedKeywordScores = boostedKeywordScores
        self.suppressedCategoryScores = suppressedCategoryScores
        self.suppressedKeywordScores = suppressedKeywordScores
    }

    public static let empty = UserPreferences()

    public mutating func like(_ item: NewsItem) {
        likedItemIDs.insert(item.id)
        savedItemIDs.insert(item.id)
        boostedSourceScores[item.sourceID, default: 0] += 4
        boostedCategoryScores[item.category.rawValue, default: 0] += 3
        for keyword in item.keywords {
            boostedKeywordScores[keyword, default: 0] += 2
        }
    }

    public mutating func save(_ item: NewsItem) {
        savedItemIDs.insert(item.id)
    }

    public mutating func hide(_ item: NewsItem) {
        hiddenItemIDs.insert(item.id)
    }

    public mutating func blockSource(_ sourceID: String) {
        blockedSourceIDs.insert(sourceID)
    }

    public mutating func suppressSimilar(to item: NewsItem) {
        suppressedCategoryScores[item.category.rawValue, default: 0] += 5
        for keyword in item.keywords {
            suppressedKeywordScores[keyword, default: 0] += 3
        }
    }
}

public struct PersonalizationEngine: Sendable {
    public init() {}

    public func rank(
        _ items: [NewsItem],
        preferences: UserPreferences,
        enabledSourceIDs: Set<String>?
    ) -> [NewsItem] {
        items
            .filter { item in
                !preferences.hiddenItemIDs.contains(item.id)
                    && !preferences.blockedSourceIDs.contains(item.sourceID)
                && (enabledSourceIDs == nil || enabledSourceIDs?.contains(item.sourceID) == true)
            }
            .sorted { lhs, rhs in
                let lhsScore = score(lhs, preferences: preferences)
                let rhsScore = score(rhs, preferences: preferences)

                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                if lhs.publishedAt != rhs.publishedAt {
                    return lhs.publishedAt > rhs.publishedAt
                }
                return lhs.title < rhs.title
            }
    }

    public func score(_ item: NewsItem, preferences: UserPreferences) -> Double {
        var score = item.publishedAt.timeIntervalSince1970 / 10_000_000_000
        score += preferences.boostedSourceScores[item.sourceID, default: 0]
        score += preferences.boostedCategoryScores[item.category.rawValue, default: 0]
        score -= preferences.suppressedCategoryScores[item.category.rawValue, default: 0]

        for keyword in item.keywords {
            score += preferences.boostedKeywordScores[keyword, default: 0]
            score -= preferences.suppressedKeywordScores[keyword, default: 0]
        }

        return score
    }
}
