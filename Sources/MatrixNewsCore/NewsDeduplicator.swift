import Foundation

public enum NewsDeduplicator {
    public static func deduplicate(_ items: [NewsItem]) -> [NewsItem] {
        var byURL: [String: NewsItem] = [:]

        for item in items {
            let key = URLNormalizer.normalizedURLString(item.url)
            if let existing = byURL[key] {
                byURL[key] = existing.publishedAt >= item.publishedAt ? existing : item
            } else {
                byURL[key] = item
            }
        }

        var byTitle: [String: NewsItem] = [:]
        for item in byURL.values {
            let key = item.title.normalizedForMatching
            if let existing = byTitle[key] {
                byTitle[key] = existing.publishedAt >= item.publishedAt ? existing : item
            } else {
                byTitle[key] = item
            }
        }

        return byTitle.values.sorted { lhs, rhs in
            if lhs.publishedAt != rhs.publishedAt {
                return lhs.publishedAt > rhs.publishedAt
            }
            return lhs.title < rhs.title
        }
    }
}
