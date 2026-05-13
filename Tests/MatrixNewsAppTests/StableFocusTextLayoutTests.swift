import Foundation
import Testing
import SwiftUI
@testable import MatrixNewsApp
@testable import MatrixNewsCore

@Suite("Stable focus text layout")
struct StableFocusTextLayoutTests {
    @Test("revealed text keeps the same fixed line slots")
    func revealedTextKeepsFixedLineSlots() {
        let item = newsItem(
            title: "MBC 긴급 속보 Mixed English headline wraps without jumping",
            summary: "한글과 English words가 섞인 요약 문장입니다. typewriter 진행 중에도 줄바꿈과 영역이 고정되어야 합니다."
        )
        let layout = StableFocusTextLayout(
            item: item,
            viewportSize: CGSize(width: 900, height: 680)
        )

        let earlyTitle = layout.visibleTitleLines(characterCount: 4, showsCursor: true)
        let laterTitle = layout.visibleTitleLines(characterCount: 28, showsCursor: true)
        let earlySummary = layout.visibleSummaryLines(characterCount: 6, showsCursor: true)
        let laterSummary = layout.visibleSummaryLines(characterCount: 44, showsCursor: true)

        #expect(layout.titleLines.count == layout.metrics.titleLineCount)
        #expect(layout.summaryLines.count == layout.metrics.summaryLineCount)
        #expect(earlyTitle.count == layout.titleLines.count)
        #expect(laterTitle.count == layout.titleLines.count)
        #expect(earlySummary.count == layout.summaryLines.count)
        #expect(laterSummary.count == layout.summaryLines.count)
        #expect(layout == StableFocusTextLayout(item: item, viewportSize: CGSize(width: 900, height: 680)))
    }

    @Test("long summaries are truncated before reveal")
    func longSummariesAreTruncatedBeforeReveal() {
        let item = newsItem(
            title: "고정 영역 테스트",
            summary: String(repeating: "아주 긴 요약 문장과 English context가 계속 이어집니다. ", count: 18)
        )
        let layout = StableFocusTextLayout(
            item: item,
            viewportSize: CGSize(width: 720, height: 540)
        )

        #expect(layout.summaryLines.count == layout.metrics.summaryLineCount)
        #expect(layout.fullSummary.hasSuffix("..."))
        #expect(layout.visibleSummaryLines(characterCount: layout.fullSummary.count + 20).joined(separator: "\n") == layout.fullSummary)
    }

    @Test("reading frame stays within small and full screen viewports")
    func readingFrameStaysWithinViewports() {
        let item = newsItem(title: "화면 크기별 프레임", summary: "요약")
        let small = StableFocusTextLayout(
            item: item,
            viewportSize: CGSize(width: 640, height: 480)
        )
        let fullScreen = StableFocusTextLayout(
            item: item,
            viewportSize: CGSize(width: 2560, height: 1440)
        )

        #expect(small.readingFrame.minX >= 0)
        #expect(small.readingFrame.maxX <= 640)
        #expect(small.readingFrame.minY >= small.metrics.topChromeHeight)
        #expect(small.readingFrame.maxY <= 480)
        #expect(fullScreen.readingFrame.width <= 1_360)
        #expect(fullScreen.readingFrame.midY < 1440 * 0.52)
    }

    @Test("stable playback uses truncated text duration")
    func stablePlaybackUsesTruncatedTextDuration() {
        let long = newsItem(
            title: "첫 번째 뉴스",
            summary: String(repeating: "아주 긴 요약 문장입니다. ", count: 30)
        )
        let next = newsItem(title: "두 번째 뉴스", summary: "짧은 요약")
        let configuration = TypewriterPlaybackConfiguration(
            titleCharactersPerSecond: 10,
            summaryCharactersPerSecond: 10,
            titlePauseDuration: 1,
            summaryPauseDuration: 1
        )
        let playback = StableFocusTypewriterPlayback(configuration: configuration)
        let viewportSize = CGSize(width: 640, height: 480)
        let layout = StableFocusTextLayout(item: long, viewportSize: viewportSize)
        let firstItemDuration = Double(layout.titleCharacterCount) / 10
            + 1
            + Double(layout.summaryCharacterCount) / 10
            + 1

        let frame = playback.frame(
            for: [long, next],
            viewportSize: viewportSize,
            elapsedTime: firstItemDuration + 0.1
        )

        #expect(layout.fullSummary.hasSuffix("..."))
        #expect(frame?.item.id == next.id)
    }

    @Test("stable playback reports one based item position")
    func stablePlaybackReportsOneBasedItemPosition() {
        let first = newsItem(title: "첫 번째 뉴스", summary: "요약")
        let second = newsItem(title: "두 번째 뉴스", summary: "요약")
        let configuration = TypewriterPlaybackConfiguration(
            titleCharactersPerSecond: 10,
            summaryCharactersPerSecond: 10,
            titlePauseDuration: 1,
            summaryPauseDuration: 1
        )
        let playback = StableFocusTypewriterPlayback(configuration: configuration)
        let viewportSize = CGSize(width: 640, height: 480)
        let firstLayout = StableFocusTextLayout(item: first, viewportSize: viewportSize)
        let firstDuration = Double(firstLayout.titleCharacterCount) / 10
            + 1
            + Double(firstLayout.summaryCharacterCount) / 10
            + 1

        let frame = playback.frame(
            for: [first, second],
            viewportSize: viewportSize,
            elapsedTime: firstDuration + 0.1
        )

        #expect(frame?.item.id == second.id)
        #expect(frame?.position == 2)
        #expect(frame?.totalCount == 2)
    }

    @Test("stable playback reports a stable cycle index after wrapping")
    func stablePlaybackReportsStableCycleIndexAfterWrapping() {
        let first = newsItem(title: "A", summary: "B")
        let second = newsItem(title: "C", summary: "D")
        let configuration = TypewriterPlaybackConfiguration(
            titleCharactersPerSecond: 1,
            summaryCharactersPerSecond: 1,
            titlePauseDuration: 1,
            summaryPauseDuration: 1
        )
        let playback = StableFocusTypewriterPlayback(configuration: configuration)
        let viewportSize = CGSize(width: 640, height: 480)
        let firstLayout = StableFocusTextLayout(item: first, viewportSize: viewportSize)
        let secondLayout = StableFocusTextLayout(item: second, viewportSize: viewportSize)
        let firstDuration = Double(firstLayout.titleCharacterCount)
            + 1
            + Double(firstLayout.summaryCharacterCount)
            + 1
        let secondDuration = Double(secondLayout.titleCharacterCount)
            + 1
            + Double(secondLayout.summaryCharacterCount)
            + 1
        let totalDuration = firstDuration + secondDuration

        let firstCycle = playback.frame(
            for: [first, second],
            viewportSize: viewportSize,
            elapsedTime: totalDuration - 0.1
        )
        let secondCycle = playback.frame(
            for: [first, second],
            viewportSize: viewportSize,
            elapsedTime: totalDuration + 0.1
        )

        #expect(firstCycle?.cycleIndex == 0)
        #expect(secondCycle?.cycleIndex == 1)
        #expect(secondCycle?.position == 1)
    }

    private func newsItem(title: String, summary: String) -> NewsItem {
        NewsItem(
            id: title,
            title: title,
            sourceID: "mbc-headline",
            sourceName: "MBC",
            url: URL(string: "https://example.com/layout")!,
            publishedAt: Date(timeIntervalSince1970: 1_778_624_000),
            category: .society,
            summary: summary,
            keywords: KeywordExtractor.keywords(from: title)
        )
    }
}
