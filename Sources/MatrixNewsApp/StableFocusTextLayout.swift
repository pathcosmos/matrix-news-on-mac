import SwiftUI

#if SWIFT_PACKAGE
import MatrixNewsCore
#endif

struct StableFocusTextMetrics: Equatable {
    var topChromeHeight: CGFloat
    var contentSpacing: CGFloat
    var bodySpacing: CGFloat
    var titleFontSize: CGFloat
    var summaryFontSize: CGFloat
    var metadataFontSize: CGFloat
    var titleLineHeight: CGFloat
    var summaryLineHeight: CGFloat
    var metadataLineHeight: CGFloat
    var titleLineCount: Int
    var summaryLineCount: Int
    var scrimSize: CGSize
}

struct StableFocusTextLayout: Equatable {
    let readingFrame: CGRect
    let metrics: StableFocusTextMetrics
    let titleLines: [String]
    let summaryLines: [String]
    let titleCharacterCount: Int
    let summaryCharacterCount: Int
    private let titleLineLengths: [Int]
    private let summaryLineLengths: [Int]

    var fullTitle: String {
        titleLines.joined(separator: "\n").trimmingTrailingNewlines()
    }

    var fullSummary: String {
        summaryLines.joined(separator: "\n").trimmingTrailingNewlines()
    }

    init(
        item: NewsItem,
        viewportSize: CGSize,
        topChromeHeight: CGFloat = 52
    ) {
        let metricsAndFrame = Self.makeMetricsAndFrame(
            viewportSize: viewportSize,
            topChromeHeight: topChromeHeight
        )
        readingFrame = metricsAndFrame.frame
        metrics = metricsAndFrame.metrics
        let titleLines = Self.wrap(
            item.title,
            maxLines: metrics.titleLineCount,
            fontSize: metrics.titleFontSize,
            maxWidth: readingFrame.width
        )

        let summary = item.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? item.summary!.trimmingCharacters(in: .whitespacesAndNewlines)
            : item.url.absoluteString
        let summaryLines = Self.wrap(
            summary,
            maxLines: metrics.summaryLineCount,
            fontSize: metrics.summaryFontSize,
            maxWidth: readingFrame.width
        )

        let titleLengths = titleLines.map(\.count)
        let summaryLengths = summaryLines.map(\.count)
        self.titleLines = titleLines
        self.summaryLines = summaryLines
        self.titleLineLengths = titleLengths
        self.summaryLineLengths = summaryLengths
        self.titleCharacterCount = titleLengths.reduce(0, +)
        self.summaryCharacterCount = summaryLengths.reduce(0, +)
    }

    func visibleTitleLines(characterCount: Int, showsCursor: Bool = false) -> [String] {
        visibleLines(
            from: titleLines,
            lengths: titleLineLengths,
            totalCount: titleCharacterCount,
            characterCount: characterCount,
            showsCursor: showsCursor
        )
    }

    func visibleSummaryLines(characterCount: Int, showsCursor: Bool = false) -> [String] {
        visibleLines(
            from: summaryLines,
            lengths: summaryLineLengths,
            totalCount: summaryCharacterCount,
            characterCount: characterCount,
            showsCursor: showsCursor
        )
    }

    private func visibleLines(
        from lines: [String],
        lengths: [Int],
        totalCount: Int,
        characterCount: Int,
        showsCursor: Bool
    ) -> [String] {
        let targetCount = max(0, min(characterCount, totalCount))
        let shouldShowCursor = showsCursor
        var remaining = targetCount
        var didPlaceCursor = false

        var visibleLines = zip(lines, lengths).map { line, lineLen -> String in
            guard remaining < lineLen else {
                remaining -= lineLen
                return line
            }

            let prefix = line.prefixCharacters(remaining)
            remaining = 0
            if shouldShowCursor && !didPlaceCursor {
                didPlaceCursor = true
                return prefix + "▌"
            }
            return ""
        }

        if shouldShowCursor && !didPlaceCursor {
            let lineIndex = visibleLines.lastIndex {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } ?? max(0, visibleLines.count - 1)
            if visibleLines.indices.contains(lineIndex) {
                visibleLines[lineIndex] += "▌"
            }
        }

        return visibleLines
    }

    private static func makeMetricsAndFrame(
        viewportSize: CGSize,
        topChromeHeight: CGFloat
    ) -> (metrics: StableFocusTextMetrics, frame: CGRect) {
        let width = max(320, viewportSize.width)
        let height = max(320, viewportSize.height)
        let horizontalMargin = width < 760
            ? CGFloat(24)
            : min(max(width * 0.08, 56), 160)
        let maxContentWidth: CGFloat = width >= 1_800 ? 1_340 : 1_120
        let contentWidth = min(maxContentWidth, max(280, width - horizontalMargin * 2))

        let titleFontSize = clamp(
            width * 0.046,
            lower: width < 760 ? 28 : 34,
            upper: width >= 1_800 ? 76 : 68
        )
        let summaryFontSize = clamp(width * 0.021, lower: 18, upper: 31)
        let metadataFontSize = clamp(width * 0.014, lower: 12, upper: 18)
        let contentSpacing = clamp(height * 0.028, lower: 16, upper: 28)
        let bodySpacing = clamp(height * 0.020, lower: 12, upper: 18)
        let titleLineCount = height < 600 ? 2 : 3
        let summaryLineCount = height < 600 ? 3 : (height < 900 ? 5 : 6)
        let titleLineHeight = ceil(titleFontSize * 1.16)
        let summaryLineHeight = ceil(summaryFontSize * 1.34)
        let metadataLineHeight = ceil(metadataFontSize * 1.25)
        let frameHeight = metadataLineHeight
            + contentSpacing
            + titleLineHeight * CGFloat(titleLineCount)
            + bodySpacing
            + summaryLineHeight * CGFloat(summaryLineCount)
        let usableHeight = max(0, height - topChromeHeight)
        let idealOriginY = topChromeHeight + usableHeight * 0.43 - frameHeight / 2
        let originY = min(
            max(topChromeHeight + 12, idealOriginY),
            max(topChromeHeight + 12, height - frameHeight - 20)
        )
        let frame = CGRect(
            x: max(0, (width - contentWidth) / 2),
            y: originY,
            width: contentWidth,
            height: frameHeight
        )
        let scrimSize = CGSize(
            width: min(width * 0.94, contentWidth + 300),
            height: min(height * 0.64, frameHeight + 190)
        )
        let metrics = StableFocusTextMetrics(
            topChromeHeight: topChromeHeight,
            contentSpacing: contentSpacing,
            bodySpacing: bodySpacing,
            titleFontSize: titleFontSize,
            summaryFontSize: summaryFontSize,
            metadataFontSize: metadataFontSize,
            titleLineHeight: titleLineHeight,
            summaryLineHeight: summaryLineHeight,
            metadataLineHeight: metadataLineHeight,
            titleLineCount: titleLineCount,
            summaryLineCount: summaryLineCount,
            scrimSize: scrimSize
        )
        return (metrics, frame)
    }

    private static func wrap(
        _ value: String,
        maxLines: Int,
        fontSize: CGFloat,
        maxWidth: CGFloat
    ) -> [String] {
        let text = value.collapsedWhitespace
        guard maxLines > 0 else { return [] }
        guard !text.isEmpty else { return Array(repeating: "", count: maxLines) }

        var lines: [String] = []
        var current = ""
        var currentWidth: CGFloat = 0

        for character in text {
            let characterWidth = estimatedWidth(of: character, fontSize: fontSize)
            if currentWidth + characterWidth > maxWidth, !current.isEmpty {
                lines.append(current.trimmingTrailingSpaces())
                if character.isWhitespace {
                    current = ""
                    currentWidth = 0
                } else {
                    current = String(character)
                    currentWidth = characterWidth
                }
            } else {
                current.append(character)
                currentWidth += characterWidth
            }
        }

        if !current.isEmpty {
            lines.append(current.trimmingTrailingSpaces())
        }

        if lines.count > maxLines {
            var clipped = Array(lines.prefix(maxLines))
            clipped[maxLines - 1] = ellipsized(
                clipped[maxLines - 1],
                fontSize: fontSize,
                maxWidth: maxWidth
            )
            return clipped
        }

        if lines.count < maxLines {
            lines.append(contentsOf: Array(repeating: "", count: maxLines - lines.count))
        }
        return lines
    }

    private static func ellipsized(
        _ value: String,
        fontSize: CGFloat,
        maxWidth: CGFloat
    ) -> String {
        let suffix = "..."
        var result = value.trimmingTrailingSpaces()
        while !result.isEmpty,
              estimatedWidth(of: result + suffix, fontSize: fontSize) > maxWidth {
            result.removeLast()
        }
        return result.isEmpty ? suffix : result.trimmingTrailingSpaces() + suffix
    }

    private static func estimatedWidth(of string: String, fontSize: CGFloat) -> CGFloat {
        string.reduce(CGFloat(0)) {
            $0 + estimatedWidth(of: $1, fontSize: fontSize)
        }
    }

    private static func estimatedWidth(of character: Character, fontSize: CGFloat) -> CGFloat {
        if character.isWhitespace {
            return fontSize * 0.36
        }
        guard let scalar = character.unicodeScalars.first else {
            return fontSize * 0.9
        }
        return scalar.value <= 0x007F ? fontSize * 0.58 : fontSize * 0.94
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}

struct StableFocusTypewriterFrame: Equatable {
    var item: NewsItem
    var layout: StableFocusTextLayout
    var revealedTitleCharacterCount: Int
    var revealedSummaryCharacterCount: Int
    var isPaused: Bool
    var position: Int
    var totalCount: Int
    var cycleIndex: Int
    var cursorTarget: StableFocusCursorTarget
    var showsCursor: Bool
    var newsTransitionProgress: Double
    var newsTransitionIntensity: Double
}

enum StableFocusCursorTarget: Equatable {
    case none
    case title
    case summary
}

enum StableFocusNewsTransition {
    static let duration: TimeInterval = 0.42

    static func progress(elapsedTime: TimeInterval) -> Double {
        guard elapsedTime > 0 else { return 0 }
        return min(1, max(0, elapsedTime / duration))
    }

    static func intensity(progress: Double) -> Double {
        let clampedProgress = min(1, max(0, progress))
        guard clampedProgress < 1 else { return 0 }

        let easedExit = 1 - smoothStep(clampedProgress)
        let flicker = 0.74 + 0.26 * abs(sin(clampedProgress * .pi * 5))
        return easedExit * flicker
    }

    private static func smoothStep(_ value: Double) -> Double {
        value * value * (3 - 2 * value)
    }
}

struct StableFocusTypewriterPlayback {
    var configuration: TypewriterPlaybackConfiguration

    func frame(
        for items: [NewsItem],
        viewportSize: CGSize,
        elapsedTime: TimeInterval
    ) -> StableFocusTypewriterFrame? {
        StableFocusPlaybackPlan(
            items: items,
            viewportSize: viewportSize,
            configuration: configuration
        )
        .frame(elapsedTime: elapsedTime)
    }
}

struct StableFocusPlaybackPlan: Equatable {
    private var entries: [StableFocusPlaybackEntry]
    private var durations: [TimeInterval]
    private var totalDuration: TimeInterval
    private var configuration: TypewriterPlaybackConfiguration

    init(
        items: [NewsItem],
        viewportSize: CGSize,
        configuration: TypewriterPlaybackConfiguration
    ) {
        self.configuration = configuration
        let totalCount = items.count
        entries = items.enumerated().map { index, item in
            StableFocusPlaybackEntry(
                item: item,
                layout: StableFocusTextLayout(item: item, viewportSize: viewportSize),
                position: index + 1,
                totalCount: totalCount
            )
        }
        durations = entries.map {
            Self.duration($0, configuration: configuration)
        }
        totalDuration = durations.reduce(0, +)
    }

    func frame(elapsedTime: TimeInterval) -> StableFocusTypewriterFrame? {
        guard !entries.isEmpty else { return nil }
        guard totalDuration > 0 else { return nil }

        let cycleIndex = Self.cycleIndex(elapsedTime: elapsedTime, totalDuration: totalDuration)
        var localTime = elapsedTime.truncatingRemainder(dividingBy: totalDuration)
        if localTime < 0 {
            localTime += totalDuration
        }

        for index in entries.indices {
            let entryDuration = durations[index]
            if localTime < entryDuration || index == entries.indices.last {
                return frame(for: entries[index], localTime: localTime, cycleIndex: cycleIndex)
            }
            localTime -= entryDuration
        }

        return frame(for: entries[0], localTime: 0, cycleIndex: cycleIndex)
    }

    private func frame(
        for entry: StableFocusPlaybackEntry,
        localTime: TimeInterval,
        cycleIndex: Int
    ) -> StableFocusTypewriterFrame {
        let titleDuration = Double(entry.layout.titleCharacterCount) / configuration.titleCharactersPerSecond
        let summaryDuration = Double(entry.layout.summaryCharacterCount) / configuration.summaryCharactersPerSecond
        let transitionProgress = StableFocusNewsTransition.progress(elapsedTime: localTime)

        let titleCount: Int
        let summaryCount: Int
        let isPaused: Bool
        let cursorTarget: StableFocusCursorTarget
        let showsCursor: Bool

        if localTime < titleDuration {
            titleCount = Int(localTime * configuration.titleCharactersPerSecond)
            summaryCount = 0
            isPaused = false
            cursorTarget = .title
            showsCursor = true
        } else if localTime < titleDuration + configuration.titlePauseDuration {
            titleCount = entry.layout.titleCharacterCount
            summaryCount = 0
            isPaused = true
            cursorTarget = .title
            showsCursor = Self.cursorIsVisible(
                elapsedTime: localTime - titleDuration,
                duration: configuration.titlePauseDuration
            )
        } else if localTime < titleDuration + configuration.titlePauseDuration + summaryDuration {
            titleCount = entry.layout.titleCharacterCount
            let summaryTime = localTime - titleDuration - configuration.titlePauseDuration
            summaryCount = Int(summaryTime * configuration.summaryCharactersPerSecond)
            isPaused = false
            cursorTarget = .summary
            showsCursor = true
        } else {
            titleCount = entry.layout.titleCharacterCount
            summaryCount = entry.layout.summaryCharacterCount
            isPaused = true
            cursorTarget = .summary
            showsCursor = Self.cursorIsVisible(
                elapsedTime: localTime
                    - titleDuration
                    - configuration.titlePauseDuration
                    - summaryDuration,
                duration: configuration.summaryPauseDuration
            )
        }

        return StableFocusTypewriterFrame(
            item: entry.item,
            layout: entry.layout,
            revealedTitleCharacterCount: max(0, min(titleCount, entry.layout.titleCharacterCount)),
            revealedSummaryCharacterCount: max(0, min(summaryCount, entry.layout.summaryCharacterCount)),
            isPaused: isPaused,
            position: entry.position,
            totalCount: entry.totalCount,
            cycleIndex: cycleIndex,
            cursorTarget: cursorTarget,
            showsCursor: showsCursor,
            newsTransitionProgress: transitionProgress,
            newsTransitionIntensity: StableFocusNewsTransition.intensity(progress: transitionProgress)
        )
    }

    private static func duration(
        _ entry: StableFocusPlaybackEntry,
        configuration: TypewriterPlaybackConfiguration
    ) -> TimeInterval {
        Double(entry.layout.titleCharacterCount) / configuration.titleCharactersPerSecond
            + configuration.titlePauseDuration
            + Double(entry.layout.summaryCharacterCount) / configuration.summaryCharactersPerSecond
            + configuration.summaryPauseDuration
    }

    private static func cycleIndex(
        elapsedTime: TimeInterval,
        totalDuration: TimeInterval
    ) -> Int {
        guard totalDuration > 0, elapsedTime > 0 else { return 0 }
        return max(0, Int(floor(elapsedTime / totalDuration)))
    }

    private static func cursorIsVisible(
        elapsedTime: TimeInterval,
        duration: TimeInterval
    ) -> Bool {
        guard duration > 0 else { return false }
        let segmentDuration = duration / 6
        guard segmentDuration > 0 else { return false }
        let segment = min(5, max(0, Int(floor(elapsedTime / segmentDuration))))
        return segment.isMultiple(of: 2)
    }
}

private struct StableFocusPlaybackEntry: Equatable {
    var item: NewsItem
    var layout: StableFocusTextLayout
    var position: Int
    var totalCount: Int
}

private extension String {
    var collapsedWhitespace: String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func trimmingTrailingSpaces() -> String {
        var result = self
        while result.last?.isWhitespace == true {
            result.removeLast()
        }
        return result
    }

    func trimmingTrailingNewlines() -> String {
        var result = self
        while result.last == "\n" {
            result.removeLast()
        }
        return result
    }

    func prefixCharacters(_ count: Int) -> String {
        String(prefix(max(0, min(count, self.count))))
    }
}
