import Foundation
import Testing
@testable import MatrixNewsCore

@Suite("Personalization engine")
struct PersonalizationEngineTests {
    @Test("hides hidden items and blocked sources")
    func hidesHiddenItemsAndBlockedSources() {
        let hidden = Self.item(id: "hidden", title: "Hidden story", sourceID: "sbs")
        let blocked = Self.item(id: "blocked", title: "Blocked source story", sourceID: "blocked-source")
        let visible = Self.item(id: "visible", title: "Visible story", sourceID: "khan")
        let preferences = UserPreferences(
            hiddenItemIDs: ["hidden"],
            blockedSourceIDs: ["blocked-source"]
        )

        let ranked = PersonalizationEngine().rank(
            [hidden, blocked, visible],
            preferences: preferences,
            enabledSourceIDs: nil
        )

        #expect(ranked.map(\.id) == ["visible"])
    }

    @Test("uses enabled sources as an additional filter")
    func filtersByEnabledSources() {
        let sbs = Self.item(id: "sbs-1", title: "SBS story", sourceID: "sbs")
        let khan = Self.item(id: "khan-1", title: "Khan story", sourceID: "khan")

        let ranked = PersonalizationEngine().rank(
            [sbs, khan],
            preferences: .empty,
            enabledSourceIDs: ["khan"]
        )

        #expect(ranked.map(\.id) == ["khan-1"])
    }

    @Test("liking an item saves it and boosts similar source, category, and keywords")
    func likingBoostsSimilarNews() {
        var preferences = UserPreferences.empty
        let liked = Self.item(
            id: "liked",
            title: "반도체 수출 회복세 확대",
            sourceID: "yonhap",
            category: .economy,
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        preferences.like(liked)

        let similar = Self.item(
            id: "similar",
            title: "반도체 업황 회복세 지속",
            sourceID: "yonhap",
            category: .economy,
            publishedAt: Date(timeIntervalSince1970: 90)
        )
        let newerUnrelated = Self.item(
            id: "newer-unrelated",
            title: "축구 대표팀 평가전 확정",
            sourceID: "sports",
            category: .sports,
            publishedAt: Date(timeIntervalSince1970: 200)
        )

        let ranked = PersonalizationEngine().rank(
            [newerUnrelated, similar],
            preferences: preferences,
            enabledSourceIDs: nil
        )

        #expect(preferences.savedItemIDs.contains("liked"))
        #expect(preferences.likedItemIDs.contains("liked"))
        #expect(ranked.map(\.id) == ["similar", "newer-unrelated"])
    }

    @Test("suppressing similar news lowers matching keyword and category results")
    func suppressingSimilarNewsLowersMatchingResults() {
        var preferences = UserPreferences.empty
        let disliked = Self.item(
            id: "disliked",
            title: "연예인 사생활 논란 확산",
            sourceID: "ent",
            category: .entertainment,
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        preferences.suppressSimilar(to: disliked)

        let similar = Self.item(
            id: "similar",
            title: "연예인 논란 추가 보도",
            sourceID: "ent",
            category: .entertainment,
            publishedAt: Date(timeIntervalSince1970: 300)
        )
        let olderUseful = Self.item(
            id: "older-useful",
            title: "국회 예산안 심사 시작",
            sourceID: "khan",
            category: .politics,
            publishedAt: Date(timeIntervalSince1970: 200)
        )

        let ranked = PersonalizationEngine().rank(
            [similar, olderUseful],
            preferences: preferences,
            enabledSourceIDs: nil
        )

        #expect(ranked.map(\.id) == ["older-useful", "similar"])
    }

    private static func item(
        id: String,
        title: String,
        sourceID: String,
        category: NewsCategory = .society,
        publishedAt: Date = Date(timeIntervalSince1970: 0)
    ) -> NewsItem {
        NewsItem(
            id: id,
            title: title,
            sourceID: sourceID,
            sourceName: sourceID.uppercased(),
            url: URL(string: "https://example.com/\(id)")!,
            publishedAt: publishedAt,
            category: category,
            keywords: KeywordExtractor.keywords(from: title)
        )
    }
}
