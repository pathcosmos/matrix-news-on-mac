import Foundation

public struct MBCNewsJSONFeedParser: Sendable {
    private var currentDate: Date

    public init(currentDate: Date = Date()) {
        self.currentDate = currentDate
    }

    public func parse(_ data: Data, source: NewsSource) throws -> [NewsItem] {
        let payload = try JSONDecoder().decode(MBCNewsPayload.self, from: data.cleanedMBCJSONData())

        return payload.items.enumerated().compactMap { index, item in
            item.makeNewsItem(
                source: source,
                publishedAt: currentDate.addingTimeInterval(-Double(index)),
                sequenceOffset: Double(index)
            )
        }
    }
}

private struct MBCNewsPayload: Decodable {
    var items: [MBCNewsPayloadItem]

    private enum CodingKeys: String, CodingKey {
        case items = "Data"
    }
}

private struct MBCNewsPayloadItem: Decodable {
    var articleID: String?
    var title: String?
    var summary: String?
    var section: String?
    var link: String?
    var startDate: String?
    var publishedDate: String?

    private enum CodingKeys: String, CodingKey {
        case articleID = "AId"
        case title = "Title"
        case summary = "Desc"
        case section = "Section"
        case link = "Link"
        case startDate = "StartDate"
        case publishedDate = "Date"
    }

    func makeNewsItem(source: NewsSource, publishedAt: Date, sequenceOffset: TimeInterval) -> NewsItem? {
        guard let rawTitle = title,
              let title = SummaryCleaner.clean(rawTitle),
              !title.isEmpty else { return nil }

        let resolvedURL = URL(string: (link ?? "").withHTTPSIfNeeded)
            ?? source.homepageURL
        let normalizedURL = URLNormalizer.normalizedURL(resolvedURL)
        let cleanedArticleID = (articleID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let id = cleanedArticleID.isEmpty
            ? NewsItem.makeID(sourceID: source.id, url: normalizedURL, title: title)
            : "\(source.id)-\(cleanedArticleID)"
        let publishedDate = MBCDateParser.parse(startDate, sequenceOffset: sequenceOffset)
            ?? MBCDateParser.parse(publishedDate, sequenceOffset: sequenceOffset)
            ?? publishedAt

        return NewsItem(
            id: id,
            title: title,
            sourceID: source.id,
            sourceName: source.displayName,
            url: normalizedURL,
            publishedAt: publishedDate,
            category: NewsCategory.fromRSSValue(section, fallback: source.categories),
            summary: summary.flatMap(SummaryCleaner.clean),
            keywords: KeywordExtractor.keywords(from: title)
        )
    }
}

private enum MBCDateParser {
    static func parse(_ value: String?, sequenceOffset: TimeInterval) -> Date? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let date = DateParser.parse(text) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)?.addingTimeInterval(-sequenceOffset)
    }
}

private extension Data {
    func cleanedMBCJSONData() -> Data {
        guard var text = String(data: self, encoding: .utf8) else { return self }
        text = text.replacingOccurrences(of: "\u{feff}", with: "")

        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            text = String(text[start...end])
        }

        return Data(text.utf8)
    }
}

private extension String {
    var withHTTPSIfNeeded: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("//") {
            return "https:" + trimmed
        }
        return trimmed
    }
}
