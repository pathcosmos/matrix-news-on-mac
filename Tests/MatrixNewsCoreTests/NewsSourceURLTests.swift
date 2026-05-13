import Foundation
import Testing
@testable import MatrixNewsCore

@Suite("News source URLs")
struct NewsSourceURLTests {
    @Test("feed URL templates replace the current year")
    func feedURLTemplatesReplaceCurrentYear() {
        let source = NewsSource(
            id: "mbc-politics",
            displayName: "MBC",
            feedURL: URL(string: "https://imnews.imbc.com/news/@@YEAR@@/politics/newest.js")!,
            homepageURL: URL(string: "https://imnews.imbc.com")!,
            defaultEnabled: true,
            licenseStatus: .testOnly,
            categories: [.politics]
        )

        #expect(
            source.resolvedFeedURL(currentYear: 2027)
                == URL(string: "https://imnews.imbc.com/news/2027/politics/newest.js")
        )
    }
}
