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

    @Test("stable playback reports a short transition at each news handoff")
    func stablePlaybackReportsShortTransitionAtEachNewsHandoff() {
        let first = newsItem(title: "첫 번째", summary: "요약")
        let second = newsItem(title: "두 번째", summary: "다음 요약")
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

        let handoff = playback.frame(
            for: [first, second],
            viewportSize: viewportSize,
            elapsedTime: firstDuration + 0.05
        )
        let afterHandoff = playback.frame(
            for: [first, second],
            viewportSize: viewportSize,
            elapsedTime: firstDuration + StableFocusNewsTransition.duration + 0.1
        )

        #expect(handoff?.item.id == second.id)
        #expect(handoff?.newsTransitionProgress ?? 1 > 0)
        #expect(handoff?.newsTransitionProgress ?? 0 < 1)
        #expect(handoff?.newsTransitionIntensity ?? 0 > 0)
        #expect(afterHandoff?.item.id == second.id)
        #expect(afterHandoff?.newsTransitionProgress == 1)
        #expect(afterHandoff?.newsTransitionIntensity == 0)
    }

    @Test("completed title keeps cursor at line end")
    func completedTitleKeepsCursorAtLineEnd() {
        let item = newsItem(title: "제목", summary: "본문")
        let layout = StableFocusTextLayout(
            item: item,
            viewportSize: CGSize(width: 640, height: 480)
        )

        let lines = layout.visibleTitleLines(
            characterCount: layout.titleCharacterCount,
            showsCursor: true
        )

        #expect(lines.joined().contains("▌"))
    }

    @Test("stable playback blinks cursor three times after title before summary")
    func stablePlaybackBlinksCursorThreeTimesAfterTitleBeforeSummary() {
        let item = newsItem(title: "제목", summary: "본문")
        let configuration = TypewriterPlaybackConfiguration(
            titleCharactersPerSecond: 2,
            summaryCharactersPerSecond: 2,
            titlePauseDuration: 1.2,
            summaryPauseDuration: 1.2
        )
        let playback = StableFocusTypewriterPlayback(configuration: configuration)
        let viewportSize = CGSize(width: 640, height: 480)
        let layout = StableFocusTextLayout(item: item, viewportSize: viewportSize)
        let titleDuration = Double(layout.titleCharacterCount) / 2

        let firstOn = playback.frame(
            for: [item],
            viewportSize: viewportSize,
            elapsedTime: titleDuration + 0.05
        )
        let firstOff = playback.frame(
            for: [item],
            viewportSize: viewportSize,
            elapsedTime: titleDuration + 0.25
        )
        let secondOn = playback.frame(
            for: [item],
            viewportSize: viewportSize,
            elapsedTime: titleDuration + 0.45
        )
        let secondOff = playback.frame(
            for: [item],
            viewportSize: viewportSize,
            elapsedTime: titleDuration + 0.65
        )
        let thirdOn = playback.frame(
            for: [item],
            viewportSize: viewportSize,
            elapsedTime: titleDuration + 0.85
        )
        let thirdOff = playback.frame(
            for: [item],
            viewportSize: viewportSize,
            elapsedTime: titleDuration + 1.05
        )
        let summaryStarted = playback.frame(
            for: [item],
            viewportSize: viewportSize,
            elapsedTime: titleDuration + 1.75
        )

        #expect(firstOn?.cursorTarget == .title)
        #expect(firstOn?.showsCursor == true)
        #expect(firstOff?.cursorTarget == .title)
        #expect(firstOff?.showsCursor == false)
        #expect(secondOn?.showsCursor == true)
        #expect(secondOff?.showsCursor == false)
        #expect(thirdOn?.showsCursor == true)
        #expect(thirdOff?.showsCursor == false)
        #expect(summaryStarted?.cursorTarget == .summary)
        #expect(summaryStarted?.revealedSummaryCharacterCount ?? 0 > 0)
    }

    @Test("stable playback blinks cursor three times after summary before next news")
    func stablePlaybackBlinksCursorThreeTimesAfterSummaryBeforeNextNews() {
        let first = newsItem(title: "제목", summary: "본문")
        let second = newsItem(title: "다음", summary: "다음 본문")
        let configuration = TypewriterPlaybackConfiguration(
            titleCharactersPerSecond: 2,
            summaryCharactersPerSecond: 2,
            titlePauseDuration: 1.2,
            summaryPauseDuration: 1.2
        )
        let playback = StableFocusTypewriterPlayback(configuration: configuration)
        let viewportSize = CGSize(width: 640, height: 480)
        let layout = StableFocusTextLayout(item: first, viewportSize: viewportSize)
        let summaryPauseStart = Double(layout.titleCharacterCount) / 2
            + 1.2
            + Double(layout.summaryCharacterCount) / 2

        let firstOn = playback.frame(
            for: [first, second],
            viewportSize: viewportSize,
            elapsedTime: summaryPauseStart + 0.05
        )
        let firstOff = playback.frame(
            for: [first, second],
            viewportSize: viewportSize,
            elapsedTime: summaryPauseStart + 0.25
        )
        let secondOn = playback.frame(
            for: [first, second],
            viewportSize: viewportSize,
            elapsedTime: summaryPauseStart + 0.45
        )
        let secondOff = playback.frame(
            for: [first, second],
            viewportSize: viewportSize,
            elapsedTime: summaryPauseStart + 0.65
        )
        let thirdOn = playback.frame(
            for: [first, second],
            viewportSize: viewportSize,
            elapsedTime: summaryPauseStart + 0.85
        )
        let thirdOff = playback.frame(
            for: [first, second],
            viewportSize: viewportSize,
            elapsedTime: summaryPauseStart + 1.05
        )
        let nextNews = playback.frame(
            for: [first, second],
            viewportSize: viewportSize,
            elapsedTime: summaryPauseStart + 1.25
        )

        #expect(firstOn?.cursorTarget == .summary)
        #expect(firstOn?.showsCursor == true)
        #expect(firstOff?.showsCursor == false)
        #expect(secondOn?.showsCursor == true)
        #expect(secondOff?.showsCursor == false)
        #expect(thirdOn?.showsCursor == true)
        #expect(thirdOff?.showsCursor == false)
        #expect(nextNews?.item.id == second.id)
        #expect(nextNews?.position == 2)
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
