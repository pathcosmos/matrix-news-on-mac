import Foundation
import Testing
@testable import MatrixNewsCore

@Suite("Settings and JSON schema")
struct SettingsAndSchemaTests {
    @Test("viewer settings clamp unsafe values")
    func viewerSettingsClampUnsafeValues() {
        var settings = ViewerSettings.default
        settings.scrollSpeed = 100
        settings.visibleNewsCount = 100
        settings.fontSize = 3

        settings.normalize()

        #expect(settings.scrollSpeed == 12)
        #expect(settings.visibleNewsCount == 16)
        #expect(settings.fontSize == 14)
    }

    @Test("settings replace unavailable enabled sources with defaults")
    func settingsReplaceUnavailableEnabledSourcesWithDefaults() {
        var settings = ViewerSettings.default
        settings.enabledSourceIDs = ["sbs-latest", "khan-total"]

        settings.reconcileEnabledSources(
            [
                NewsSource(
                    id: "mbc-headline",
                    displayName: "MBC",
                    feedURL: URL(string: "https://imnews.imbc.com/operate/common/main/topnews/headline_news.js")!,
                    homepageURL: URL(string: "https://imnews.imbc.com")!,
                    defaultEnabled: true,
                    licenseStatus: .testOnly,
                    categories: [.politics, .economy, .society]
                )
            ]
        )

        #expect(settings.enabledSourceIDs == ["mbc-headline"])
    }

    @Test("matrix glyph set is Hangul first")
    func matrixGlyphSetIsHangulFirst() {
        #expect(MatrixGlyphSet.koreanMatrix.contains("가"))
        #expect(MatrixGlyphSet.koreanMatrix.contains("뉴스"))
        #expect(MatrixGlyphSet.koreanMatrix.contains("정치"))
    }

    @Test("matrix glyph orientation is mostly upright with rare mirroring")
    func matrixGlyphOrientationIsMostlyUprightWithRareMirroring() {
        let orientations = (0..<400).map {
            MatrixGlyphOrientation.orientation(column: $0, row: $0 * 3)
        }
        let normalCount = orientations.filter { $0 == .normal }.count
        let mirroredCount = orientations.filter { $0 == .mirrored }.count
        let upsideDownCount = orientations.filter {
            $0 == .upsideDown || $0 == .mirroredUpsideDown
        }.count

        #expect(normalCount > 340)
        #expect(mirroredCount > 0)
        #expect(upsideDownCount <= 3)
    }

    @Test("matrix rain depth layers get larger and faster toward the foreground")
    func matrixRainDepthLayersGetLargerAndFasterTowardForeground() {
        #expect(MatrixRainDepthLayer.distant.fontSize < MatrixRainDepthLayer.middle.fontSize)
        #expect(MatrixRainDepthLayer.middle.fontSize < MatrixRainDepthLayer.near.fontSize)
        #expect(MatrixRainDepthLayer.distant.speed < MatrixRainDepthLayer.middle.speed)
        #expect(MatrixRainDepthLayer.middle.speed < MatrixRainDepthLayer.near.speed)
    }

    @Test("matrix rain opacity has a bright head and fading trail")
    func matrixRainOpacityHasBrightHeadAndFadingTrail() {
        let profile = MatrixRainCinematicProfile(layer: .middle)

        #expect(profile.opacity(distanceFromHead: 0) > 0.7)
        #expect(profile.opacity(distanceFromHead: 1) > profile.opacity(distanceFromHead: 6))
        #expect(profile.opacity(distanceFromHead: 6) > profile.opacity(distanceFromHead: 14))
        #expect(profile.opacity(distanceFromHead: 30) < 0.08)
    }

    @Test("latest payload round trips through JSON")
    func latestPayloadRoundTrips() throws {
        let payload = LatestNewsPayload(
            generatedAt: Date(timeIntervalSince1970: 1_778_625_000),
            items: [
                NewsItem(
                    id: "sample",
                    title: "주요 뉴스 제목",
                    sourceID: "sample-source",
                    sourceName: "Sample Source",
                    url: URL(string: "https://example.com/news")!,
                    publishedAt: Date(timeIntervalSince1970: 1_778_624_000),
                    category: .politics,
                    keywords: ["주요", "뉴스"]
                )
            ]
        )

        let encoder = JSONEncoder.matrixNews
        let decoder = JSONDecoder.matrixNews
        let data = try encoder.encode(payload)
        let decoded = try decoder.decode(LatestNewsPayload.self, from: data)

        #expect(decoded == payload)
    }

    @Test("category fallback only applies to single-category feeds")
    func categoryFallbackOnlyAppliesToSingleCategoryFeeds() {
        #expect(
            NewsCategory.fromRSSValue("세계") == .international
        )
        #expect(
            NewsCategory.fromRSSValue(nil, fallback: [.economy]) == .economy
        )
        #expect(
            NewsCategory.fromRSSValue(nil, fallback: [.politics, .economy, .society]) == .other
        )
    }
}
