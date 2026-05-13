import Foundation
import Testing
@testable import MatrixNewsCore

@Suite("MBC article summary enricher")
struct MBCArticleSummaryEnricherTests {
    @Test("fills missing and URL-like MBC summaries from article excerpts")
    func fillsMissingAndURLLikeSummaries() async {
        let missing = item(id: "missing", summary: nil)
        let urlSummary = item(
            id: "url-summary",
            summary: "https://imnews.imbc.com/news/2026/society/article/2.html"
        )
        let normal = item(id: "normal", summary: "이미 제공된 정상 요약입니다.")
        let html = """
        <div class="news_txt" itemprop="articleBody">
          본문 첫 문장입니다.<br>
          본문 두 번째 문장입니다.
        </div>
        """
        let enricher = MBCArticleSummaryEnricher(fetchHTML: { _ in html })

        let enriched = await enricher.enrich([missing, urlSummary, normal])

        #expect(enriched[0].summary == "본문 첫 문장입니다. 본문 두 번째 문장입니다.")
        #expect(enriched[1].summary == "본문 첫 문장입니다. 본문 두 번째 문장입니다.")
        #expect(enriched[2].summary == "이미 제공된 정상 요약입니다.")
    }

    @Test("keeps existing value when fetching or parsing fails")
    func keepsExistingValueWhenFetchingOrParsingFails() async {
        let missing = item(id: "missing", summary: nil)
        let urlSummary = item(
            id: "url-summary",
            summary: "https://imnews.imbc.com/news/2026/society/article/2.html"
        )
        let enricher = MBCArticleSummaryEnricher(fetchHTML: { url in
            if url.lastPathComponent == "2.html" {
                return "<html><body>본문 컨테이너 없음</body></html>"
            }
            throw CocoaError(.fileReadUnknown)
        })

        let enriched = await enricher.enrich([missing, urlSummary])

        #expect(enriched[0].summary == nil)
        #expect(enriched[1].summary == "https://imnews.imbc.com/news/2026/society/article/2.html")
    }

    @Test("only targets MBC article pages with missing or URL-like summaries")
    func onlyTargetsSupportedMBCArticlePages() {
        #expect(MBCArticleSummaryEnricher.shouldEnrich(item(id: "nil", summary: nil)) == true)
        #expect(MBCArticleSummaryEnricher.shouldEnrich(item(id: "blank", summary: "   ")) == true)
        #expect(MBCArticleSummaryEnricher.shouldEnrich(item(id: "url", summary: "https://imnews.imbc.com/replay/2026/nwtoday/article/1.html")) == true)
        #expect(MBCArticleSummaryEnricher.shouldEnrich(item(id: "normal", summary: "정상 요약")) == false)
        #expect(MBCArticleSummaryEnricher.shouldEnrich(item(
            id: "unsupported",
            url: URL(string: "https://example.com/news/1")!,
            summary: nil
        )) == false)
        #expect(MBCArticleSummaryEnricher.shouldEnrich(item(
            id: "non-article",
            url: URL(string: "https://imnews.imbc.com/news/2026/society/list.html")!,
            summary: nil
        )) == false)
    }

    private func item(
        id: String,
        url: URL = URL(string: "https://imnews.imbc.com/news/2026/society/article/1.html")!,
        summary: String?
    ) -> NewsItem {
        NewsItem(
            id: id,
            title: "MBC 기사 \(id)",
            sourceID: "mbc-society",
            sourceName: "MBC",
            url: url,
            publishedAt: Date(timeIntervalSince1970: 1_778_624_000),
            category: .society,
            summary: summary,
            keywords: ["MBC", "기사"]
        )
    }
}
