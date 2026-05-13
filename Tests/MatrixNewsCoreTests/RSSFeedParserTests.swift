import Foundation
import Testing
@testable import MatrixNewsCore

@Suite("RSS feed parser")
struct RSSFeedParserTests {
    @Test("parses RSS items into normalized news items")
    func parsesRSSItems() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Sample</title>
            <item>
              <title><![CDATA[반도체 수출 회복세 확대]]></title>
              <description><![CDATA[<p>주요 수출 지표가 개선되며 경기 회복 기대가 커지고 있습니다.</p>]]></description>
              <link>https://news.example.com/article?id=1&amp;utm_source=rss</link>
              <pubDate>Wed, 13 May 2026 03:30:00 +0900</pubDate>
              <category>경제</category>
              <guid>sample-1</guid>
            </item>
          </channel>
        </rss>
        """
        let source = NewsSource(
            id: "sample",
            displayName: "Sample News",
            feedURL: URL(string: "https://news.example.com/rss.xml")!,
            homepageURL: URL(string: "https://news.example.com")!,
            defaultEnabled: true,
            licenseStatus: .testOnly,
            categories: [.economy]
        )

        let items = try RSSFeedParser().parse(
            Data(xml.utf8),
            source: source
        )

        #expect(items.count == 1)
        #expect(items[0].title == "반도체 수출 회복세 확대")
        #expect(items[0].summary == "주요 수출 지표가 개선되며 경기 회복 기대가 커지고 있습니다.")
        #expect(items[0].sourceID == "sample")
        #expect(items[0].sourceName == "Sample News")
        #expect(items[0].category == .economy)
        #expect(items[0].keywords.contains("반도체"))
        #expect(items[0].url.absoluteString == "https://news.example.com/article?id=1")
    }

    @Test("deduplicates items by normalized URL before falling back to title")
    func deduplicatesItems() {
        let first = NewsItem(
            id: "1",
            title: "같은 기사",
            sourceID: "a",
            sourceName: "A",
            url: URL(string: "https://example.com/news?id=1&utm_medium=rss")!,
            publishedAt: Date(timeIntervalSince1970: 100),
            category: .society,
            summary: "첫 번째 기사 내용",
            keywords: ["같은", "기사"]
        )
        let duplicateURL = NewsItem(
            id: "2",
            title: "제목이 조금 다른 같은 기사",
            sourceID: "a",
            sourceName: "A",
            url: URL(string: "https://example.com/news?id=1")!,
            publishedAt: Date(timeIntervalSince1970: 200),
            category: .society,
            summary: "더 최신 중복 기사 내용",
            keywords: ["제목"]
        )
        let duplicateTitle = NewsItem(
            id: "3",
            title: "같은 기사",
            sourceID: "b",
            sourceName: "B",
            url: URL(string: "https://other.example.com/story")!,
            publishedAt: Date(timeIntervalSince1970: 300),
            category: .society,
            summary: "제목 중복 기사 내용",
            keywords: ["같은", "기사"]
        )

        let deduped = NewsDeduplicator.deduplicate([first, duplicateURL, duplicateTitle])

        #expect(deduped.map(\.id) == ["3", "2"])
    }
}
