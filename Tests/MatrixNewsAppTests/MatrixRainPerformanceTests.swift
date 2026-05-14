import Testing
import SwiftUI
@testable import MatrixNewsApp
@testable import MatrixNewsCore

@Suite("Matrix rain performance")
struct MatrixRainPerformanceTests {
    @Test("4K render plan lowers glyph budget and frame rate")
    func fourKRenderPlanLowersGlyphBudgetAndFrameRate() {
        let plan = MatrixRainRenderPlan(size: CGSize(width: 3840, height: 2160))

        #expect(plan.framesPerSecond == 20)
        #expect(plan.densityScale == 0.25)
        #expect(plan.estimatedGlyphDraws <= 1_250)
        #expect(plan.estimatedTextDraws <= 1_350)
    }

    @Test("Metal instance budget stays within the existing text draw budget at 4K")
    func metalInstanceBudgetStaysWithinExistingTextDrawBudgetAt4K() {
        let plan = MatrixRainRenderPlan(size: CGSize(width: 3840, height: 2160))

        #expect(plan.estimatedMetalInstances <= plan.estimatedTextDraws)
        #expect(plan.estimatedMetalInstances <= 1_350)
    }

    @Test("HD render plan keeps more visual density than 4K")
    func hdRenderPlanKeepsMoreVisualDensityThan4K() {
        let hd = MatrixRainRenderPlan(size: CGSize(width: 1920, height: 1080))
        let fourK = MatrixRainRenderPlan(size: CGSize(width: 3840, height: 2160))

        #expect(hd.densityScale > fourK.densityScale)
        #expect(hd.framesPerSecond == 20)
        #expect(hd.estimatedGlyphDraws > fourK.estimatedGlyphDraws)
        #expect(hd.estimatedGlyphDraws < 1_300)
    }

    @Test("large displays use the middle density budget")
    func largeDisplaysUseMiddleDensityBudget() {
        let plan = MatrixRainRenderPlan(size: CGSize(width: 2560, height: 1440))

        #expect(plan.framesPerSecond == 20)
        #expect(plan.densityScale == 0.36)
    }

    @Test("layer sampling preserves foreground detail")
    func layerSamplingPreservesForegroundDetail() {
        let plan = MatrixRainRenderPlan(size: CGSize(width: 3840, height: 2160))
        let distant = plan.layerPlan(for: .distant)
        let middle = plan.layerPlan(for: .middle)
        let near = plan.layerPlan(for: .near)

        #expect(distant.effectiveDensityScale == 0.1875)
        #expect(middle.effectiveDensityScale == 0.225)
        #expect(near.effectiveDensityScale == 0.25)
        #expect(distant.tailStep == 3)
        #expect(middle.tailStep == 3)
        #expect(near.tailStep == 2)
        #expect(distant.visibleTailDistances == [0, 3, 6, 9, 12])
        #expect(middle.visibleTailDistances == [0, 3, 6, 9, 12, 15, 18])
        #expect(near.visibleTailDistances == [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24])
        #expect(distant.sampledColumns.count < middle.sampledColumns.count)
        #expect(middle.sampledColumns.count < near.sampledColumns.count)
    }

    @Test("head glow is skipped for distant rain")
    func headGlowIsSkippedForDistantRain() {
        let plan = MatrixRainRenderPlan(size: CGSize(width: 3840, height: 2160))
        let distant = plan.layerPlan(for: .distant)
        let middle = plan.layerPlan(for: .middle)
        let near = plan.layerPlan(for: .near)

        #expect(distant.headGlowOpacity == 0)
        #expect(distant.headGlowRadius == 0)
        #expect(distant.estimatedHeadGlowDraws == 0)
        #expect(middle.headGlowOpacity < MatrixRainDepthLayer.middle.defaultHeadGlowOpacity)
        #expect(middle.headGlowRadius < MatrixRainDepthLayer.middle.glowRadius)
        #expect(middle.estimatedHeadGlowDraws == middle.sampledColumns.count)
        #expect(near.headGlowOpacity < MatrixRainDepthLayer.near.defaultHeadGlowOpacity)
        #expect(near.headGlowRadius < MatrixRainDepthLayer.near.glowRadius)
        #expect(near.estimatedHeadGlowDraws == near.sampledColumns.count)
    }

    @Test("render plan precomputes column motion")
    func renderPlanPrecomputesColumnMotion() {
        let plan = MatrixRainRenderPlan(size: CGSize(width: 1920, height: 1080))
        let middle = plan.layerPlan(for: .middle)
        let expectedColumns = Array(stride(from: -1, to: middle.columns, by: middle.columnStep))

        #expect(middle.sampledColumns.map(\.column) == expectedColumns)
        #expect(middle.sampledColumns.first?.motion == MatrixRainColumnMotion(column: -1, layer: .middle))
    }

    @Test("reduce motion freezes rain animation seconds")
    func reduceMotionFreezesRainAnimationSeconds() {
        let plan = MatrixRainRenderPlan(size: CGSize(width: 1920, height: 1080))

        #expect(plan.animationSeconds(rawSeconds: 123.456, reduceMotion: true) == 0)
        #expect(plan.animationSeconds(rawSeconds: 10.049, reduceMotion: false) == 10)
    }

    @Test("reduce motion selects a paused Metal playback policy")
    func reduceMotionSelectsPausedMetalPlaybackPolicy() {
        let reduced = MatrixRainMetalPlaybackPolicy.resolve(
            reduceMotion: true,
            applicationActive: true,
            windowVisible: true,
            performanceFallback: false
        )
        let active = MatrixRainMetalPlaybackPolicy.resolve(
            reduceMotion: false,
            applicationActive: true,
            windowVisible: true,
            performanceFallback: false
        )
        let fallback = MatrixRainMetalPlaybackPolicy.resolve(
            reduceMotion: false,
            applicationActive: true,
            windowVisible: true,
            performanceFallback: true
        )

        #expect(reduced.isPaused)
        #expect(reduced.framesPerSecond == 1)
        #expect(reduced.animationSeconds(rawSeconds: 123.456) == 0)
        #expect(active.isPaused == false)
        #expect(active.framesPerSecond == 60)
        #expect(fallback.framesPerSecond == 30)
    }

    @Test("visible inactive Metal playback stays smooth")
    func visibleInactiveMetalPlaybackStaysSmooth() {
        let policy = MatrixRainMetalPlaybackPolicy.resolve(
            reduceMotion: false,
            applicationActive: false,
            windowVisible: true,
            performanceFallback: false
        )

        #expect(policy.framesPerSecond == 60)
        #expect(policy.isPaused == false)
        #expect(policy.drawsOnDemand == false)
    }

    @Test("visible inactive Metal playback uses fallback frame rate when enabled")
    func visibleInactiveMetalPlaybackUsesFallbackFrameRateWhenEnabled() {
        let policy = MatrixRainMetalPlaybackPolicy.resolve(
            reduceMotion: false,
            applicationActive: false,
            windowVisible: true,
            performanceFallback: true
        )

        #expect(policy.framesPerSecond == 30)
        #expect(policy.isPaused == false)
        #expect(policy.drawsOnDemand == false)
    }

    @Test("occluded Metal playback throttles to one frame per second")
    func occludedMetalPlaybackThrottlesToOneFramePerSecond() {
        let policy = MatrixRainMetalPlaybackPolicy.resolve(
            reduceMotion: false,
            applicationActive: true,
            windowVisible: false,
            performanceFallback: false
        )

        #expect(policy.framesPerSecond == 1)
        #expect(policy.isPaused == false)
        #expect(policy.drawsOnDemand == false)
    }

    @Test("Metal animation clock keeps shader time in a precise Float range")
    func metalAnimationClockKeepsShaderTimeInPreciseFloatRange() {
        let active = MatrixRainMetalPlaybackPolicy.resolve(
            reduceMotion: false,
            applicationActive: true,
            windowVisible: true,
            performanceFallback: false
        )
        let absoluteStart = 800_000_000.0

        let first = Float(active.animationSeconds(now: absoluteStart + 0.05, start: absoluteStart))
        let second = Float(active.animationSeconds(now: absoluteStart + 0.10, start: absoluteStart))

        #expect(first < 1)
        #expect(second < 1)
        #expect(second > first)
    }

    @Test("renderer selector falls back to Canvas when Metal is unavailable")
    func rendererSelectorFallsBackToCanvasWhenMetalIsUnavailable() {
        #expect(
            MatrixRainRendererSelector.backend(
                platformSupportsMetalView: true,
                metalAvailable: true
            ) == .metal
        )
        #expect(
            MatrixRainRendererSelector.backend(
                platformSupportsMetalView: true,
                metalAvailable: false
            ) == .canvas
        )
        #expect(
            MatrixRainRendererSelector.backend(
                platformSupportsMetalView: false,
                metalAvailable: true
            ) == .canvas
        )
    }

    @Test("Metal glyph atlas layout covers base and value glyphs")
    func metalGlyphAtlasLayoutCoversBaseAndValueGlyphs() {
        let composer = MatrixRainGlyphComposer()
        let layout = MatrixRainGlyphAtlasLayout(glyphComposer: composer)
        var glyphs = Set(composer.baseGlyphs)
        glyphs.formUnion(composer.valueFragments.joined())

        for glyph in glyphs {
            for layer in MatrixRainDepthLayer.allCases {
                for style in MatrixRainMetalGlyphStyle.allCases {
                    let expectedStyles = MatrixRainGlyphAtlasLayout.atlasStyles(for: layer)
                    let entry = layout.entry(for: glyph, layer: layer, style: style)

                    if expectedStyles.contains(style) {
                        guard let entry else {
                            Issue.record("Missing atlas entry for \(glyph), \(layer), \(style)")
                            continue
                        }

                        #expect(entry.uvRect.minX >= 0)
                        #expect(entry.uvRect.minY >= 0)
                        #expect(entry.uvRect.maxX <= 1)
                        #expect(entry.uvRect.maxY <= 1)
                        #expect(entry.uvRect.width > 0)
                        #expect(entry.uvRect.height > 0)
                        #expect(entry.pointSize.width > 0)
                        #expect(entry.pointSize.height > 0)
                    } else {
                        #expect(entry == nil)
                    }
                }
            }
        }
    }

    @Test("Metal rain uses static GPU instances for a render plan")
    func metalRainUsesStaticGPUInstancesForRenderPlan() {
        let composer = MatrixRainGlyphComposer()
        let renderPlan = MatrixRainRenderPlan(size: CGSize(width: 3840, height: 2160))
        let staticPlan = MatrixRainMetalStaticInstancePlan(
            renderPlan: renderPlan,
            glyphComposer: composer
        )

        #expect(staticPlan.instances.count == renderPlan.estimatedMetalInstances)
        #expect(staticPlan.baseGlyphAtlasIndices.count == composer.baseGlyphs.count)
        #expect(staticPlan.valueGlyphAtlasIndices.count == composer.valueFragments.joined().count)
        #expect(staticPlan.requiresPerFrameCPUInstanceBuild == false)
    }

    @Test("column motion changes y position smoothly between adjacent frames")
    func columnMotionChangesYPositionSmoothlyBetweenAdjacentFrames() {
        let motion = MatrixRainColumnMotion(column: 7, layer: .middle)
        let first: CGFloat = motion.yPosition(
            distanceFromHead: 0,
            seconds: 10,
            rowHeight: 25,
            rows: 90,
            tailLength: 18
        )
        let next: CGFloat = motion.yPosition(
            distanceFromHead: 0,
            seconds: 10 + (1.0 / 24.0),
            rowHeight: 25,
            rows: 90,
            tailLength: 18
        )

        #expect(next > first)
        #expect(next - first < 12)
    }

    @Test("value glyph blending uses neutral civic fragments without party names")
    func valueGlyphBlendingUsesNeutralCivicFragmentsWithoutPartyNames() {
        let composer = MatrixRainGlyphComposer()

        #expect(!composer.valueFragments.contains("민주당"))
        #expect(!composer.valueFragments.contains("대한독립만세"))
        #expect(composer.valueFragments.contains("민주"))
        #expect(composer.valueFragments.contains("독립"))
        #expect(composer.valueFragments.contains("만세"))

        let sample = (0..<80).map {
            composer.glyph(column: $0, row: $0 * 3, seconds: 12, valueBlendIntensity: 1.0)
        }
        let civicGlyphs = Set("대한민국국가애국독립만세민주주의")

        #expect(sample.contains { civicGlyphs.contains($0) })
    }
}

private extension MatrixRainRenderPlan {
    func layerPlan(for layer: MatrixRainDepthLayer) -> MatrixRainLayerRenderPlan {
        layers.first { $0.layer == layer }!
    }
}
