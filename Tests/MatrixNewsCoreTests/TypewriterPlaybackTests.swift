import Foundation
import Testing
@testable import MatrixNewsCore

@Suite("Typewriter playback")
struct TypewriterPlaybackTests {
    @Test("reveals title, pauses, reveals summary, then pauses before the next item")
    func revealsTitlePausesThenSummaryThenPauses() {
        let items = [
            item(id: "one", title: "가나", summary: "다라마"),
            item(id: "two", title: "바사", summary: "아자")
        ]
        let playback = TypewriterPlayback(
            configuration: TypewriterPlaybackConfiguration(
                titleCharactersPerSecond: 2,
                summaryCharactersPerSecond: 1,
                titlePauseDuration: 1,
                summaryPauseDuration: 2
            )
        )

        #expect(playback.frame(for: items, elapsedTime: 0.5)?.item.id == "one")
        #expect(playback.frame(for: items, elapsedTime: 0.5)?.revealedTitle == "가")
        #expect(playback.frame(for: items, elapsedTime: 0.5)?.revealedSummary == "")

        #expect(playback.frame(for: items, elapsedTime: 1.0)?.revealedTitle == "가나")
        #expect(playback.frame(for: items, elapsedTime: 1.5)?.revealedSummary == "")
        #expect(playback.frame(for: items, elapsedTime: 1.5)?.isPaused == true)

        #expect(playback.frame(for: items, elapsedTime: 2.1)?.revealedSummary == "")
        #expect(playback.frame(for: items, elapsedTime: 3.1)?.revealedSummary == "다")
        #expect(playback.frame(for: items, elapsedTime: 5.1)?.revealedSummary == "다라마")
        #expect(playback.frame(for: items, elapsedTime: 5.1)?.isPaused == true)

        #expect(playback.frame(for: items, elapsedTime: 7.0)?.item.id == "two")
        #expect(playback.frame(for: items, elapsedTime: 7.5)?.revealedTitle == "바")
    }

    @Test("falls back to URL text when summary is missing")
    func fallsBackWhenSummaryIsMissing() {
        let item = item(id: "one", title: "제목", summary: nil)
        let playback = TypewriterPlayback(
            configuration: TypewriterPlaybackConfiguration(
                titleCharactersPerSecond: 10,
                summaryCharactersPerSecond: 10,
                pauseDuration: 1
            )
        )

        let frame = playback.frame(for: [item], elapsedTime: 1.0)

        #expect(frame?.fullSummary == "https://example.com/one")
    }

    private func item(id: String, title: String, summary: String?) -> NewsItem {
        NewsItem(
            id: id,
            title: title,
            sourceID: "sample",
            sourceName: "Sample",
            url: URL(string: "https://example.com/\(id)")!,
            publishedAt: Date(timeIntervalSince1970: 0),
            category: .society,
            summary: summary,
            keywords: KeywordExtractor.keywords(from: title)
        )
    }
}
