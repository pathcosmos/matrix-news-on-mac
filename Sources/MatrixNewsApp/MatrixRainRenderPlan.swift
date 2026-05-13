import SwiftUI

#if SWIFT_PACKAGE
import MatrixNewsCore
#endif

struct MatrixRainRenderPlan: Equatable, Sendable {
    var size: CGSize
    var framesPerSecond: Double
    var densityScale: Double
    var scanlineSpacing: CGFloat
    var valueBlendIntensity: Double
    var layers: [MatrixRainLayerRenderPlan]

    var estimatedGlyphDraws: Int {
        layers.reduce(0) { $0 + $1.estimatedGlyphDraws }
    }

    init(size: CGSize) {
        self.size = size

        let pixelArea = max(1, size.width * size.height)
        let resolvedFramesPerSecond: Double
        let resolvedDensityScale: Double
        let resolvedScanlineSpacing: CGFloat
        let resolvedValueBlendIntensity: Double

        if pixelArea >= 7_500_000 {
            resolvedFramesPerSecond = 24
            resolvedDensityScale = 0.30
            resolvedScanlineSpacing = 8
            resolvedValueBlendIntensity = 0.16
        } else if pixelArea >= 3_000_000 {
            resolvedFramesPerSecond = 24
            resolvedDensityScale = 0.44
            resolvedScanlineSpacing = 6
            resolvedValueBlendIntensity = 0.14
        } else {
            resolvedFramesPerSecond = 30
            resolvedDensityScale = 0.78
            resolvedScanlineSpacing = 5
            resolvedValueBlendIntensity = 0.12
        }

        framesPerSecond = resolvedFramesPerSecond
        densityScale = resolvedDensityScale
        scanlineSpacing = resolvedScanlineSpacing
        valueBlendIntensity = resolvedValueBlendIntensity
        layers = MatrixRainDepthLayer.allCases.map {
            MatrixRainLayerRenderPlan(layer: $0, size: size, densityScale: resolvedDensityScale)
        }
    }
}

struct MatrixRainLayerRenderPlan: Equatable, Sendable {
    var layer: MatrixRainDepthLayer
    var columns: Int
    var rows: Int
    var columnStep: Int
    var visibleTailDistances: [Int]

    var estimatedGlyphDraws: Int {
        let sampledColumns = max(1, Int(ceil(Double(columns + 1) / Double(columnStep))))
        return sampledColumns * visibleTailDistances.count
    }

    init(layer: MatrixRainDepthLayer, size: CGSize, densityScale: Double) {
        self.layer = layer
        columns = max(1, Int(size.width / CGFloat(layer.columnWidth)) + 3)
        rows = max(1, Int(size.height / CGFloat(layer.rowHeight)) + layer.tailLength + 5)
        columnStep = max(1, Int((1 / densityScale).rounded(.toNearestOrAwayFromZero)))

        let tailStep = 2
        visibleTailDistances = Array(stride(from: 0, through: layer.tailLength, by: tailStep))
    }
}

struct MatrixRainColumnMotion: Equatable, Sendable {
    private var speedRowsPerSecond: Double
    private var phaseRows: Double
    private var gapRows: Int
    private var driftPhase: Double
    private var driftRate: Double
    private var driftMagnitude: Double

    init(column: Int, layer: MatrixRainDepthLayer) {
        let seed = Self.positiveHash(column: column, layer: layer)
        speedRowsPerSecond = layer.speed * (5.8 + Double(seed % 23) / 15.0)
        phaseRows = Double(seed % 10_000) / 10_000.0 * 80
        gapRows = 5 + seed % max(6, layer.tailLength)
        driftPhase = Double(seed % 6_283) / 1_000.0
        driftRate = 0.08 + Double((seed / 17) % 19) / 220.0
        driftMagnitude = 0.08 + Double((seed / 31) % 17) / 210.0
    }

    func row(distanceFromHead distance: Int, seconds: TimeInterval, rows: Int) -> Int {
        let rowCount = max(1, rows)
        let progressedRow = Int(floor(headProgress(seconds: seconds, rows: rowCount))) + distance
        return progressedRow.positiveModulo(rowCount)
    }

    func yPosition(
        distanceFromHead distance: Int,
        seconds: TimeInterval,
        rowHeight: CGFloat,
        rows: Int,
        tailLength: Int
    ) -> CGFloat {
        let progress = headProgress(seconds: seconds, rows: max(1, rows))
        return CGFloat(progress + Double(distance - tailLength)) * rowHeight
    }

    func xOffset(seconds: TimeInterval, columnWidth: CGFloat) -> CGFloat {
        CGFloat(sin(seconds * driftRate + driftPhase)) * columnWidth * CGFloat(driftMagnitude)
    }

    private func headProgress(seconds: TimeInterval, rows: Int) -> Double {
        let cycleRows = Double(max(1, rows + gapRows))
        return (phaseRows + seconds * speedRowsPerSecond)
            .positiveRemainder(dividingBy: cycleRows)
    }

    private static func positiveHash(column: Int, layer: MatrixRainDepthLayer) -> Int {
        var value = column &* 73_856_093
        value ^= layer.cacheSeed &* 19_349_663
        value ^= value >> 13
        return abs(value)
    }
}

struct MatrixRainGlyphComposer: Sendable {
    var baseGlyphs: [Character]
    var valueFragments: [String]

    private let valueGlyphs: [Character]

    init(
        baseGlyphs: String = MatrixGlyphSet.koreanMatrix,
        valueFragments: [String] = ["대한", "민국", "국가", "애국", "독립", "만세", "민주", "주의"]
    ) {
        self.baseGlyphs = Array(baseGlyphs)
        self.valueFragments = valueFragments
        valueGlyphs = Array(valueFragments.joined())
    }

    func glyph(
        column: Int,
        row: Int,
        seconds: TimeInterval,
        valueBlendIntensity: Double
    ) -> Character {
        let tick = Int((seconds * 2).rounded(.down))
        let hash = positiveHash(column: column, row: row, tick: tick)
        let blendThreshold = max(0, min(10, Int((valueBlendIntensity * 64).rounded())))

        if !valueGlyphs.isEmpty, hash % 97 < blendThreshold {
            return valueGlyphs[(hash / 97 + row + tick).positiveModulo(valueGlyphs.count)]
        }

        guard !baseGlyphs.isEmpty else { return " " }
        return baseGlyphs[hash.positiveModulo(baseGlyphs.count)]
    }

    private func positiveHash(column: Int, row: Int, tick: Int) -> Int {
        var value = column &* 73_856_093
        value ^= row &* 19_349_663
        value ^= tick &* 83_492_791
        value ^= value >> 13
        return abs(value)
    }
}

private extension Double {
    func positiveRemainder(dividingBy divisor: Double) -> Double {
        guard divisor > 0 else { return 0 }
        let remainder = truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }
}

private extension Int {
    func positiveModulo(_ divisor: Int) -> Int {
        guard divisor > 0 else { return 0 }
        let remainder = self % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}

private extension MatrixRainDepthLayer {
    var cacheSeed: Int {
        switch self {
        case .distant: return 11
        case .middle: return 23
        case .near: return 37
        }
    }
}
