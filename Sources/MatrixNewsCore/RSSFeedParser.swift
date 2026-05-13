import Foundation

#if canImport(FoundationXML)
import FoundationXML
#endif

public enum RSSFeedParserError: Error, Equatable {
    case invalidXML(line: Int, column: Int)
}

public struct RSSFeedParser: Sendable {
    public init() {}

    public func parse(_ data: Data, source: NewsSource) throws -> [NewsItem] {
        let delegate = RSSParserDelegate(source: source)
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw RSSFeedParserError.invalidXML(
                line: parser.lineNumber,
                column: parser.columnNumber
            )
        }

        return delegate.items
    }
}

private final class RSSParserDelegate: NSObject, XMLParserDelegate {
    private let source: NewsSource
    private var currentItem: PartialRSSItem?
    private var currentElement: String?
    private var currentText = ""

    private(set) var items: [NewsItem] = []

    init(source: NewsSource) {
        self.source = source
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let element = elementName.lowercased()
        currentElement = element
        currentText = ""

        if element == "item" || element == "entry" {
            currentItem = PartialRSSItem()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let element = elementName.lowercased()
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard var item = currentItem else {
            currentText = ""
            currentElement = nil
            return
        }

        switch element {
        case "title":
            item.title = text
        case "description", "summary", "content", "content:encoded", "encoded":
            item.summary = text
        case "link":
            item.link = text
        case "guid", "id":
            item.guid = text
        case "pubdate", "published", "updated":
            item.pubDate = text
        case "category":
            item.category = text
        default:
            break
        }

        if element == "item" || element == "entry" {
            if let newsItem = item.makeNewsItem(source: source) {
                items.append(newsItem)
            }
            currentItem = nil
        } else {
            currentItem = item
        }

        currentText = ""
        currentElement = nil
    }
}

private struct PartialRSSItem {
    var title = ""
    var link = ""
    var guid = ""
    var pubDate = ""
    var category = ""
    var summary = ""

    func makeNewsItem(source: NewsSource) -> NewsItem? {
        let cleanedTitle = title.normalizedForMatching
        guard !cleanedTitle.isEmpty else { return nil }

        let candidateURL = URL(string: link)
            ?? URL(string: guid)
            ?? source.homepageURL
        let normalizedURL = URLNormalizer.normalizedURL(candidateURL)
        let category = NewsCategory.fromRSSValue(category, fallback: source.categories)
        let keywords = KeywordExtractor.keywords(from: cleanedTitle)

        return NewsItem(
            id: NewsItem.makeID(sourceID: source.id, url: normalizedURL, title: cleanedTitle),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceID: source.id,
            sourceName: source.displayName,
            url: normalizedURL,
            publishedAt: DateParser.parse(pubDate) ?? Date(timeIntervalSince1970: 0),
            category: category,
            summary: SummaryCleaner.clean(summary),
            keywords: keywords
        )
    }
}

public enum SummaryCleaner {
    public static func clean(_ value: String) -> String? {
        let withoutFooters = value
            .replacingOccurrences(
                of: #"(?is)MBC\s*뉴스는\s*24시간\s*여러분의\s*제보를\s*기다립니다\.?.*$"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?is)▷\s*전화\s*02-784-4000.*$"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?is)▷\s*이메일\s*mbcjebo@mbc\.co\.kr.*$"#,
                with: " ",
                options: .regularExpression
            )
        let withoutTags = withoutFooters
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return withoutTags.isEmpty ? nil : withoutTags
    }
}

public enum DateParser {
    private static let rfc822Formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    private static let rfc822NoWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    public static func parse(_ value: String) -> Date? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let date = ISO8601DateFormatter().date(from: text) {
            return date
        }
        if let date = rfc822Formatter.date(from: text) {
            return date
        }
        if let date = rfc822NoWeekdayFormatter.date(from: text) {
            return date
        }
        return nil
    }
}
