import Foundation

public struct TypewriterPlaybackConfiguration: Equatable, Sendable {
    public var titleCharactersPerSecond: Double
    public var summaryCharactersPerSecond: Double
    public var titlePauseDuration: Double
    public var summaryPauseDuration: Double

    public init(
        titleCharactersPerSecond: Double,
        summaryCharactersPerSecond: Double,
        titlePauseDuration: Double = 0.8,
        summaryPauseDuration: Double = 2.4,
        pauseDuration: Double? = nil
    ) {
        self.titleCharactersPerSecond = max(1, titleCharactersPerSecond)
        self.summaryCharactersPerSecond = max(1, summaryCharactersPerSecond)
        self.titlePauseDuration = max(0.25, titlePauseDuration)
        self.summaryPauseDuration = max(0.5, pauseDuration ?? summaryPauseDuration)
    }
}

public struct TypewriterFrame: Equatable, Sendable {
    public var item: NewsItem
    public var fullTitle: String
    public var fullSummary: String
    public var revealedTitle: String
    public var revealedSummary: String
    public var isPaused: Bool
    public var cycleIndex: Int

    public init(
        item: NewsItem,
        fullTitle: String,
        fullSummary: String,
        revealedTitle: String,
        revealedSummary: String,
        isPaused: Bool,
        cycleIndex: Int = 0
    ) {
        self.item = item
        self.fullTitle = fullTitle
        self.fullSummary = fullSummary
        self.revealedTitle = revealedTitle
        self.revealedSummary = revealedSummary
        self.isPaused = isPaused
        self.cycleIndex = cycleIndex
    }
}

public struct TypewriterPlayback: Sendable {
    public var configuration: TypewriterPlaybackConfiguration

    public init(configuration: TypewriterPlaybackConfiguration) {
        self.configuration = configuration
    }

    public func frame(for items: [NewsItem], elapsedTime: TimeInterval) -> TypewriterFrame? {
        guard !items.isEmpty else { return nil }

        let durations = items.map(itemDuration)
        let totalDuration = durations.reduce(0, +)
        guard totalDuration > 0 else { return nil }

        let cycleIndex = Self.cycleIndex(elapsedTime: elapsedTime, totalDuration: totalDuration)
        var localTime = elapsedTime.truncatingRemainder(dividingBy: totalDuration)
        if localTime < 0 {
            localTime += totalDuration
        }

        for index in items.indices {
            let duration = durations[index]
            if localTime < duration || index == items.indices.last {
                return frame(for: items[index], localTime: localTime, cycleIndex: cycleIndex)
            }
            localTime -= duration
        }

        return frame(for: items[0], localTime: 0, cycleIndex: cycleIndex)
    }

    private func frame(
        for item: NewsItem,
        localTime: TimeInterval,
        cycleIndex: Int
    ) -> TypewriterFrame {
        let title = item.title
        let summary = item.summary?.normalizedForMatching.isEmpty == false
            ? item.summary!.trimmingCharacters(in: .whitespacesAndNewlines)
            : item.url.absoluteString
        let titleDuration = Double(title.count) / configuration.titleCharactersPerSecond
        let summaryDuration = Double(summary.count) / configuration.summaryCharactersPerSecond

        let revealedTitle: String
        let revealedSummary: String
        let isPaused: Bool

        if localTime < titleDuration {
            revealedTitle = title.prefixCharacters(Int(localTime * configuration.titleCharactersPerSecond))
            revealedSummary = ""
            isPaused = false
        } else if localTime < titleDuration + configuration.titlePauseDuration {
            revealedTitle = title
            revealedSummary = ""
            isPaused = true
        } else if localTime < titleDuration + configuration.titlePauseDuration + summaryDuration {
            revealedTitle = title
            let summaryTime = localTime - titleDuration - configuration.titlePauseDuration
            revealedSummary = summary.prefixCharacters(Int(summaryTime * configuration.summaryCharactersPerSecond))
            isPaused = false
        } else {
            revealedTitle = title
            revealedSummary = summary
            isPaused = true
        }

        return TypewriterFrame(
            item: item,
            fullTitle: title,
            fullSummary: summary,
            revealedTitle: revealedTitle,
            revealedSummary: revealedSummary,
            isPaused: isPaused,
            cycleIndex: cycleIndex
        )
    }

    private func itemDuration(_ item: NewsItem) -> TimeInterval {
        let summary = item.summary?.normalizedForMatching.isEmpty == false
            ? item.summary!.trimmingCharacters(in: .whitespacesAndNewlines)
            : item.url.absoluteString
        return Double(item.title.count) / configuration.titleCharactersPerSecond
            + configuration.titlePauseDuration
            + Double(summary.count) / configuration.summaryCharactersPerSecond
            + configuration.summaryPauseDuration
    }

    private static func cycleIndex(
        elapsedTime: TimeInterval,
        totalDuration: TimeInterval
    ) -> Int {
        guard totalDuration > 0, elapsedTime > 0 else { return 0 }
        return max(0, Int(floor(elapsedTime / totalDuration)))
    }
}

private extension String {
    func prefixCharacters(_ count: Int) -> String {
        String(prefix(max(0, min(count, self.count))))
    }
}
