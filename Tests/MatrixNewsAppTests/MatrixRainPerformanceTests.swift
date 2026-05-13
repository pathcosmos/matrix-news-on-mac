import Testing
import SwiftUI
@testable import MatrixNewsApp
@testable import MatrixNewsCore

@Suite("Matrix rain performance")
struct MatrixRainPerformanceTests {
    @Test("4K render plan lowers glyph budget and frame rate")
    func fourKRenderPlanLowersGlyphBudgetAndFrameRate() {
        let plan = MatrixRainRenderPlan(size: CGSize(width: 3840, height: 2160))

        #expect(plan.framesPerSecond == 24)
        #expect(plan.densityScale <= 0.32)
        #expect(plan.estimatedGlyphDraws < 3_800)
    }

    @Test("HD render plan keeps more visual density than 4K")
    func hdRenderPlanKeepsMoreVisualDensityThan4K() {
        let hd = MatrixRainRenderPlan(size: CGSize(width: 1920, height: 1080))
        let fourK = MatrixRainRenderPlan(size: CGSize(width: 3840, height: 2160))

        #expect(hd.densityScale > fourK.densityScale)
        #expect(hd.framesPerSecond == 30)
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
