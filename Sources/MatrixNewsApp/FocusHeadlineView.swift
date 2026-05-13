import SwiftUI

#if SWIFT_PACKAGE
import MatrixNewsCore
#endif

struct TypewriterNewsView: View {
    @EnvironmentObject private var model: NewsViewModel
    @State private var startDate = Date()
    @State private var playbackCache = StableFocusPlaybackPlanCache()
    @State private var lastObservedCycleIndex: Int?
    @State private var refreshRequestedCycleIndex: Int?
    var items: [NewsItem]
    var playbackRevision: Int = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { timeline in
            GeometryReader { geometry in
                if let frame = playbackFrame(for: timeline.date, viewportSize: geometry.size) {
                    let marker = PlaybackRefreshMarker(frame: frame)
                    let layout = frame.layout
                    ZStack {
                        FocusReadabilityScrim()
                            .frame(
                                width: layout.metrics.scrimSize.width,
                                height: layout.metrics.scrimSize.height
                            )
                            .allowsHitTesting(false)

                        VStack(alignment: .leading, spacing: layout.metrics.contentSpacing) {
                            HStack(spacing: 12) {
                                Text(frame.item.sourceName.uppercased())
                                    .foregroundStyle(.green.opacity(0.82))

                                Text(frame.item.publishedAt.formatted(date: .omitted, time: .shortened))
                                    .foregroundStyle(.white.opacity(0.68))

                                Text("\(frame.position)/\(frame.totalCount)")
                                    .foregroundStyle(.green.opacity(0.76))
                            }
                            .font(.system(size: layout.metrics.metadataFontSize, weight: .bold, design: .monospaced))
                            .frame(height: layout.metrics.metadataLineHeight, alignment: .leading)
                            .shadow(color: .black.opacity(0.8), radius: 9, y: 2)

                            VStack(alignment: .leading, spacing: layout.metrics.bodySpacing) {
                                StableFocusLineStack(
                                    reservedLines: layout.titleLines,
                                    visibleLines: layout.visibleTitleLines(
                                        characterCount: frame.revealedTitleCharacterCount,
                                        showsCursor: showsTitleCursor(frame: frame, layout: layout)
                                    ),
                                    width: layout.readingFrame.width,
                                    lineHeight: layout.metrics.titleLineHeight,
                                    font: .custom(model.settings.fontFamily, size: layout.metrics.titleFontSize),
                                    weight: .semibold,
                                    color: Color(red: 0.82, green: 1.0, blue: 0.82).opacity(0.98)
                                )
                                .shadow(color: .black.opacity(0.92), radius: 14, y: 3)
                                .shadow(color: .green.opacity(0.64), radius: 10)

                                StableFocusLineStack(
                                    reservedLines: layout.summaryLines,
                                    visibleLines: layout.visibleSummaryLines(
                                        characterCount: frame.revealedSummaryCharacterCount,
                                        showsCursor: showsSummaryCursor(frame: frame, layout: layout)
                                    ),
                                    width: layout.readingFrame.width,
                                    lineHeight: layout.metrics.summaryLineHeight,
                                    font: .custom(model.settings.fontFamily, size: layout.metrics.summaryFontSize),
                                    weight: .regular,
                                    color: .white.opacity(0.9)
                                )
                                .shadow(color: .black.opacity(0.9), radius: 12, y: 3)
                                .shadow(color: .green.opacity(0.34), radius: 6)
                            }
                        }
                        .frame(
                            width: layout.readingFrame.width,
                            height: layout.readingFrame.height,
                            alignment: .topLeading
                        )
                    }
                    .position(x: layout.readingFrame.midX, y: layout.readingFrame.midY)
                    .onAppear {
                        model.selectedItemID = frame.item.id
                        observePlayback(marker)
                    }
                    .onChange(of: frame.item.id) { _, itemID in
                        model.selectedItemID = itemID
                    }
                    .onChange(of: marker) { _, marker in
                        observePlayback(marker)
                    }
                }
            }
        }
        .onChange(of: playbackRevision) { _, _ in
            startDate = Date()
            playbackCache.reset()
            lastObservedCycleIndex = nil
            refreshRequestedCycleIndex = nil
        }
    }

    private func playbackFrame(for date: Date, viewportSize: CGSize) -> StableFocusTypewriterFrame? {
        let speed = model.settings.scrollSpeed
        let playback = StableFocusTypewriterPlayback(
            configuration: playbackConfiguration(speed: speed)
        )
        return playbackCache.frame(
            for: Array(items.prefix(50)),
            viewportSize: viewportSize,
            configuration: playback.configuration,
            elapsedTime: date.timeIntervalSince(startDate)
        )
    }

    private func playbackConfiguration(speed: Double) -> TypewriterPlaybackConfiguration {
        TypewriterPlaybackConfiguration(
            titleCharactersPerSecond: max(2, speed * 2.1),
            summaryCharactersPerSecond: max(4, speed * 3.7),
            titlePauseDuration: max(0.85, 2.8 / speed),
            summaryPauseDuration: max(2.6, 9.0 / speed)
        )
    }

    private func showsTitleCursor(frame: StableFocusTypewriterFrame, layout: StableFocusTextLayout) -> Bool {
        !frame.isPaused && frame.revealedTitleCharacterCount < layout.titleCharacterCount
    }

    private func showsSummaryCursor(frame: StableFocusTypewriterFrame, layout: StableFocusTextLayout) -> Bool {
        !frame.isPaused
            && frame.revealedTitleCharacterCount == layout.titleCharacterCount
            && frame.revealedSummaryCharacterCount < layout.summaryCharacterCount
    }

    private func observePlayback(_ marker: PlaybackRefreshMarker) {
        if lastObservedCycleIndex == nil {
            lastObservedCycleIndex = marker.cycleIndex
        } else if marker.cycleIndex > (lastObservedCycleIndex ?? marker.cycleIndex) {
            lastObservedCycleIndex = marker.cycleIndex
            Task {
                await model.applyPreparedNewsRefreshIfAvailable()
            }
        }

        guard marker.totalCount == 50, marker.position >= 48 else { return }
        guard refreshRequestedCycleIndex != marker.cycleIndex else { return }

        refreshRequestedCycleIndex = marker.cycleIndex
        Task {
            await model.prepareNewsRefreshForNextCycle()
        }
    }
}

private struct PlaybackRefreshMarker: Equatable {
    var position: Int
    var totalCount: Int
    var cycleIndex: Int
    var itemID: String

    init(frame: StableFocusTypewriterFrame) {
        position = frame.position
        totalCount = frame.totalCount
        cycleIndex = frame.cycleIndex
        itemID = frame.item.id
    }
}

@MainActor
private final class StableFocusPlaybackPlanCache {
    private var signature: StableFocusPlaybackSignature?
    private var plan: StableFocusPlaybackPlan?

    func reset() {
        signature = nil
        plan = nil
    }

    func frame(
        for items: [NewsItem],
        viewportSize: CGSize,
        configuration: TypewriterPlaybackConfiguration,
        elapsedTime: TimeInterval
    ) -> StableFocusTypewriterFrame? {
        let signature = StableFocusPlaybackSignature(
            itemIDs: items.map(\.id),
            viewportWidth: Int(viewportSize.width.rounded()),
            viewportHeight: Int(viewportSize.height.rounded()),
            configuration: configuration
        )

        if signature != self.signature {
            plan = StableFocusPlaybackPlan(
                items: items,
                viewportSize: viewportSize,
                configuration: configuration
            )
            self.signature = signature
        }

        return plan?.frame(elapsedTime: elapsedTime)
    }
}

private struct StableFocusPlaybackSignature: Equatable {
    var itemIDs: [String]
    var viewportWidth: Int
    var viewportHeight: Int
    var configuration: TypewriterPlaybackConfiguration
}

private struct StableFocusLineStack: View {
    var reservedLines: [String]
    var visibleLines: [String]
    var width: CGFloat
    var lineHeight: CGFloat
    var font: Font
    var weight: Font.Weight
    var color: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            lineStack(reservedLines)
                .opacity(0)

            lineStack(visibleLines)
        }
        .frame(width: width, height: lineHeight * CGFloat(reservedLines.count), alignment: .topLeading)
        .clipped()
    }

    private func lineStack(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line)
                    .font(font)
                    .fontWeight(weight)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .frame(width: width, height: lineHeight, alignment: .leading)
                    .clipped()
            }
        }
    }
}

private struct FocusReadabilityScrim: View {
    var body: some View {
        GeometryReader { proxy in
            RadialGradient(
                colors: [
                    .black.opacity(0.82),
                    .black.opacity(0.62),
                    .black.opacity(0.28),
                    .black.opacity(0.0)
                ],
                center: .center,
                startRadius: 0,
                endRadius: max(proxy.size.width, proxy.size.height) * 0.54
            )
            .blur(radius: 28)
            .compositingGroup()
        }
    }
}
