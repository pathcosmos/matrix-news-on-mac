import Foundation
import Testing
@testable import MatrixNewsApp
@testable import MatrixNewsCore

@Suite("Passive display")
struct PassiveDisplayTests {
    @MainActor
    @Test("passive display uses loaded latest news capped at fifty")
    func passiveDisplayUsesLoadedLatestNewsCappedAtFifty() async {
        let items = (0..<60).map { index in
            NewsItem(
                id: "item-\(index)",
                title: "뉴스 \(index)",
                sourceID: index == 0 ? "blocked" : "mbc-headline",
                sourceName: "MBC",
                url: URL(string: "https://example.com/\(index)")!,
                publishedAt: Date(timeIntervalSince1970: 1_778_624_000 - Double(index)),
                category: .politics,
                summary: "요약 \(index)",
                keywords: ["뉴스"]
            )
        }
        let payload = NewsDataPayload(
            latest: LatestNewsPayload(generatedAt: Date(timeIntervalSince1970: 1), items: items),
            sources: [
                NewsSource(
                    id: "mbc-headline",
                    displayName: "MBC",
                    feedURL: URL(string: "https://imnews.imbc.com/operate/common/main/topnews/headline_news.js")!,
                    homepageURL: URL(string: "https://imnews.imbc.com")!,
                    defaultEnabled: true,
                    licenseStatus: .testOnly,
                    categories: [.politics]
                )
            ]
        )
        let model = NewsViewModel(
            dataLoader: NewsDataLoader(
                remoteLoad: nil,
                bundledLoad: { payload },
                fallback: NewsDataPayload(
                    latest: LatestNewsPayload(generatedAt: Date(timeIntervalSince1970: 0), items: []),
                    sources: []
                )
            )
        )
        model.settings.visibleNewsCount = 3
        model.preferences.hiddenItemIDs = ["item-1"]
        model.preferences.blockedSourceIDs = ["blocked"]

        await model.load()

        #expect(model.passiveDisplayItems.map(\.id) == items.prefix(50).map(\.id))
    }

    @MainActor
    @Test("passive display is ordered by newest published time")
    func passiveDisplayIsOrderedByNewestPublishedTime() async {
        let older = newsItem(id: "older", publishedAt: Date(timeIntervalSince1970: 100))
        let newest = newsItem(id: "newest", publishedAt: Date(timeIntervalSince1970: 300))
        let middle = newsItem(id: "middle", publishedAt: Date(timeIntervalSince1970: 200))
        let model = NewsViewModel(dataLoader: loader(items: [older, newest, middle]))

        await model.load()

        #expect(model.passiveDisplayItems.map(\.id) == ["newest", "middle", "older"])
    }

    @MainActor
    @Test("prepared refresh waits until the cycle boundary to swap changed news")
    func preparedRefreshWaitsUntilCycleBoundaryToSwapChangedNews() async {
        let payloads = PayloadQueue([
            payload(items: [newsItem(id: "first", publishedAt: Date(timeIntervalSince1970: 100))]),
            payload(items: [newsItem(id: "second", publishedAt: Date(timeIntervalSince1970: 200))])
        ])
        let model = NewsViewModel(
            dataLoader: NewsDataLoader(
                remoteLoad: {
                    payloads.next()
                },
                bundledLoad: {
                    payload(items: [])
                },
                fallback: payload(items: [])
            )
        )

        await model.load()
        model.selectedItemID = "first"
        let initialRevision = model.playbackRevision
        await model.prepareNewsRefreshForNextCycle()

        #expect(model.passiveDisplayItems.map(\.id) == ["first"])
        #expect(model.selectedItemID == "first")
        #expect(model.playbackRevision == initialRevision)

        await model.applyPreparedNewsRefreshIfAvailable()
        #expect(model.passiveDisplayItems.map(\.id) == ["second"])
        #expect(model.selectedItemID == nil)
        #expect(model.playbackRevision == initialRevision + 1)
    }

    @MainActor
    @Test("unchanged prepared refresh does not bump playback revision")
    func unchangedPreparedRefreshDoesNotBumpPlaybackRevision() async {
        let unchangedPayload = payload(
            items: [newsItem(id: "first", publishedAt: Date(timeIntervalSince1970: 100))]
        )
        let model = NewsViewModel(
            dataLoader: NewsDataLoader(
                remoteLoad: { unchangedPayload },
                bundledLoad: { unchangedPayload },
                fallback: payload(items: [])
            )
        )

        await model.load()
        model.selectedItemID = "first"
        let initialRevision = model.playbackRevision
        await model.prepareNewsRefreshForNextCycle()
        await model.applyPreparedNewsRefreshIfAvailable()

        #expect(model.selectedItemID == "first")
        #expect(model.playbackRevision == initialRevision)
    }

    @MainActor
    @Test("failed prepared refresh keeps the current cycle data")
    func failedPreparedRefreshKeepsCurrentCycleData() async {
        let currentPayload = payload(
            items: [newsItem(id: "first", publishedAt: Date(timeIntervalSince1970: 100))]
        )
        let model = NewsViewModel(
            dataLoader: NewsDataLoader(
                remoteLoad: {
                    throw CocoaError(.fileReadUnknown)
                },
                bundledLoad: { currentPayload },
                fallback: payload(items: [])
            )
        )

        await model.load()
        let initialRevision = model.playbackRevision
        await model.prepareNewsRefreshForNextCycle()
        await model.applyPreparedNewsRefreshIfAvailable()

        #expect(model.passiveDisplayItems.map(\.id) == ["first"])
        #expect(model.playbackRevision == initialRevision)
    }

    private func loader(items: [NewsItem]) -> NewsDataLoader {
        loader(payload: payload(items: items))
    }

    private func loader(payload: NewsDataPayload) -> NewsDataLoader {
        NewsDataLoader(
            remoteLoad: nil,
            bundledLoad: { payload },
            fallback: NewsDataPayload(
                latest: LatestNewsPayload(generatedAt: Date(timeIntervalSince1970: 0), items: []),
                sources: []
            )
        )
    }

    private func payload(items: [NewsItem]) -> NewsDataPayload {
        NewsDataPayload(
            latest: LatestNewsPayload(generatedAt: Date(timeIntervalSince1970: 1), items: items),
            sources: [
                NewsSource(
                    id: "mbc-headline",
                    displayName: "MBC",
                    feedURL: URL(string: "https://imnews.imbc.com/operate/common/main/topnews/headline_news.js")!,
                    homepageURL: URL(string: "https://imnews.imbc.com")!,
                    defaultEnabled: true,
                    licenseStatus: .testOnly,
                    categories: [.politics]
                )
            ]
        )
    }

    private func newsItem(id: String, publishedAt: Date) -> NewsItem {
        NewsItem(
            id: id,
            title: "뉴스 \(id)",
            sourceID: "mbc-headline",
            sourceName: "MBC",
            url: URL(string: "https://example.com/\(id)")!,
            publishedAt: publishedAt,
            category: .politics,
            summary: "요약 \(id)",
            keywords: ["뉴스"]
        )
    }
}

private final class PayloadQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var payloads: [NewsDataPayload]

    init(_ payloads: [NewsDataPayload]) {
        self.payloads = payloads
    }

    func next() -> NewsDataPayload {
        lock.lock()
        defer { lock.unlock() }
        return payloads.removeFirst()
    }
}
