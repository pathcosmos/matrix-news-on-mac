import Foundation

#if SWIFT_PACKAGE
import MatrixNewsCore
#endif

enum SampleNews {
    static let newsSources: [NewsSource] = [
        NewsSource(
            id: "mbc-headline",
            displayName: "MBC",
            feedURL: URL(string: "https://imnews.imbc.com/operate/common/main/topnews/headline_news.js")!,
            homepageURL: URL(string: "https://imnews.imbc.com")!,
            defaultEnabled: true,
            licenseStatus: .testOnly,
            categories: [.politics, .economy, .society, .international, .culture, .technology, .sports]
        )
    ]

    static let sources: [NewsSourceOption] = [
        NewsSourceOption(id: "mbc-headline", displayName: "MBC")
    ]

    static let items: [NewsItem] = [
        item(
            id: "sample-1",
            title: "김민석 총리, 삼성전자 노사 대화 지원 당부",
            summary: "삼성전자의 노사 협상이 결렬된 가운데 정부가 파업으로 이어지지 않도록 대화 지원을 주문했습니다.",
            sourceID: "mbc-headline",
            sourceName: "MBC",
            category: .politics,
            offset: -600
        ),
        item(
            id: "sample-2",
            title: "트럼프-시진핑 회담 앞두고 LNG 직항 재개",
            summary: "미중 정상회담을 앞두고 미국산 액화천연가스 선박이 1년여 만에 중국으로 향했습니다.",
            sourceID: "mbc-headline",
            sourceName: "MBC",
            category: .international,
            offset: -1_200
        ),
        item(
            id: "sample-3",
            title: "국회부의장 후보에 박덕흠 의원 선출",
            summary: "국민의힘이 야당 몫 국회부의장 후보로 4선의 박덕흠 의원을 선출했습니다.",
            sourceID: "mbc-headline",
            sourceName: "MBC",
            category: .politics,
            offset: -1_800
        )
    ]

    private static func item(
        id: String,
        title: String,
        summary: String,
        sourceID: String,
        sourceName: String,
        category: NewsCategory,
        offset: TimeInterval
    ) -> NewsItem {
        NewsItem(
            id: id,
            title: title,
            sourceID: sourceID,
            sourceName: sourceName,
            url: URL(string: "https://example.com/\(id)")!,
            publishedAt: Date().addingTimeInterval(offset),
            category: category,
            summary: summary,
            keywords: KeywordExtractor.keywords(from: title)
        )
    }
}
