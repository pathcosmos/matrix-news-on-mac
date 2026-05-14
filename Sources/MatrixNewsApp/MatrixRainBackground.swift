import SwiftUI

#if SWIFT_PACKAGE
import MatrixNewsCore
#endif

struct MatrixRainBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let glyphComposer = MatrixRainGlyphComposer()

    var body: some View {
        GeometryReader { proxy in
            let plan = MatrixRainRenderPlan(size: proxy.size)

            ZStack {
                Canvas(rendersAsynchronously: true) { context, _ in
                    drawBase(in: context, size: plan.size)
                    drawScanlines(in: context, size: plan.size, spacing: plan.scanlineSpacing)
                    drawVignette(in: context, size: plan.size)
                }

                TimelineView(.periodic(from: .now, by: 1.0 / MatrixRainRenderPlan.targetFramesPerSecond)) { timeline in
                    Canvas(rendersAsynchronously: true) { context, _ in
                        let seconds = plan.animationSeconds(
                            rawSeconds: timeline.date.timeIntervalSinceReferenceDate,
                            reduceMotion: reduceMotion
                        )
                        var textCache = MatrixRainGlyphTextCache(context: context)

                        drawRain(
                            in: context,
                            size: plan.size,
                            seconds: seconds,
                            plan: plan,
                            textCache: &textCache
                        )
                    }
                }
            }
        }
    }

    private func drawBase(in context: GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(
            Path(rect),
            with: .color(Color(red: 0.0, green: 0.018, blue: 0.006))
        )

        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [
                    .black.opacity(0.72),
                    Color(red: 0.0, green: 0.08, blue: 0.025).opacity(0.40),
                    .black.opacity(0.86)
                ]),
                startPoint: CGPoint(x: size.width * 0.5, y: 0),
                endPoint: CGPoint(x: size.width * 0.5, y: size.height)
            )
        )
    }

    private func drawRain(
        in context: GraphicsContext,
        size: CGSize,
        seconds: TimeInterval,
        plan: MatrixRainRenderPlan,
        textCache: inout MatrixRainGlyphTextCache
    ) {
        for layerPlan in plan.layers {
            drawLayer(
                layerPlan,
                in: context,
                size: size,
                seconds: seconds,
                plan: plan,
                textCache: &textCache
            )
        }
    }

    private func drawLayer(
        _ layerPlan: MatrixRainLayerRenderPlan,
        in context: GraphicsContext,
        size: CGSize,
        seconds: TimeInterval,
        plan: MatrixRainRenderPlan,
        textCache: inout MatrixRainGlyphTextCache
    ) {
        let layer = layerPlan.layer
        let profile = MatrixRainCinematicProfile(layer: layer)
        let columnWidth = CGFloat(layer.columnWidth)
        let rowHeight = CGFloat(layer.rowHeight)

        for columnPlan in layerPlan.sampledColumns {
            let column = columnPlan.column
            let motion = columnPlan.motion
            let x = CGFloat(column) * columnWidth
                + columnWidth * 0.5
                + motion.xOffset(seconds: seconds, columnWidth: columnWidth)

            for distance in layerPlan.visibleTailDistances {
                let alpha = profile.opacity(distanceFromHead: distance)
                guard alpha > 0.026 else { continue }

                let row = motion.row(
                    distanceFromHead: distance,
                    seconds: seconds,
                    rows: layerPlan.rows
                )
                let y = motion.yPosition(
                    distanceFromHead: distance,
                    seconds: seconds,
                    rowHeight: rowHeight,
                    rows: layerPlan.rows,
                    tailLength: layer.tailLength
                )
                guard y > -rowHeight * 2, y < size.height + rowHeight * 2 else {
                    continue
                }
                let orientation = MatrixGlyphOrientation.orientation(
                    column: column,
                    row: row
                )

                drawGlyph(
                    String(
                        glyphComposer.glyph(
                            column: column,
                            row: row,
                            seconds: seconds,
                            valueBlendIntensity: plan.valueBlendIntensity
                        )
                    ),
                    distance: distance,
                    layer: layer,
                    headGlowOpacity: layerPlan.headGlowOpacity,
                    headGlowRadius: layerPlan.headGlowRadius,
                    alpha: alpha,
                    orientation: orientation,
                    at: CGPoint(x: x, y: y),
                    in: context,
                    textCache: &textCache
                )
            }
        }
    }

    private func drawGlyph(
        _ glyph: String,
        distance: Int,
        layer: MatrixRainDepthLayer,
        headGlowOpacity: Double,
        headGlowRadius: Double,
        alpha: Double,
        orientation: MatrixGlyphOrientation,
        at point: CGPoint,
        in context: GraphicsContext,
        textCache: inout MatrixRainGlyphTextCache
    ) {
        let isHead = distance == 0
        let tone = MatrixRainGlyphTone(distance: distance)
        let fontSize = CGFloat(layer.fontSize) * (isHead ? 1.08 : 1)
        let text = textCache.resolvedText(
            glyph: glyph,
            layer: layer,
            tone: tone,
            fontSize: fontSize,
            isGlow: false
        )

        if isHead, headGlowOpacity > 0 {
            let glowText = textCache.resolvedText(
                glyph: glyph,
                layer: layer,
                tone: tone,
                fontSize: fontSize,
                isGlow: true
            )
            drawTransformed(
                glowText,
                opacity: min(headGlowOpacity, alpha * 0.52),
                at: point,
                orientation: orientation,
                blurRadius: CGFloat(headGlowRadius),
                in: context
            )
        }

        drawTransformed(
            text,
            opacity: alpha,
            at: point,
            orientation: orientation,
            blurRadius: nil,
            in: context
        )
    }

    private func drawTransformed(
        _ text: GraphicsContext.ResolvedText,
        opacity: Double,
        at point: CGPoint,
        orientation: MatrixGlyphOrientation,
        blurRadius: CGFloat?,
        in context: GraphicsContext
    ) {
        guard opacity > 0.001 else { return }

        var glyphContext = context
        glyphContext.opacity = opacity
        if let blurRadius {
            glyphContext.addFilter(.blur(radius: blurRadius))
        }
        glyphContext.translateBy(x: point.x, y: point.y)
        glyphContext.scaleBy(x: CGFloat(orientation.xScale), y: CGFloat(orientation.yScale))
        glyphContext.draw(text, at: .zero, anchor: .center)
    }

    private func drawScanlines(in context: GraphicsContext, size: CGSize, spacing: CGFloat) {
        var y: CGFloat = 0
        while y <= size.height {
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            let opacity = 0.008 + 0.008 * (0.5 + 0.5 * sin(Double(y) * 0.017))
            context.stroke(line, with: .color(.green.opacity(opacity)), lineWidth: 0.5)
            y += spacing
        }
    }

    private func drawVignette(in context: GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(
            Path(rect),
            with: .radialGradient(
                Gradient(colors: [
                    .clear,
                    .black.opacity(0.58)
                ]),
                center: CGPoint(x: size.width * 0.5, y: size.height * 0.46),
                startRadius: min(size.width, size.height) * 0.20,
                endRadius: max(size.width, size.height) * 0.72
            )
        )
    }
}

private struct MatrixRainGlyphTextCache {
    private var context: GraphicsContext
    private var texts: [MatrixRainGlyphTextKey: GraphicsContext.ResolvedText] = [:]

    init(context: GraphicsContext) {
        self.context = context
    }

    mutating func resolvedText(
        glyph: String,
        layer: MatrixRainDepthLayer,
        tone: MatrixRainGlyphTone,
        fontSize: CGFloat,
        isGlow: Bool
    ) -> GraphicsContext.ResolvedText {
        let key = MatrixRainGlyphTextKey(
            glyph: glyph,
            layerID: layer.cacheID,
            tone: tone,
            isGlow: isGlow
        )
        if let text = texts[key] {
            return text
        }

        let text = context.resolve(
            Text(glyph)
                .font(.system(size: fontSize, weight: tone.fontWeight(isGlow: isGlow), design: .monospaced))
                .foregroundStyle(tone.color(isGlow: isGlow))
        )
        texts[key] = text
        return text
    }
}

private struct MatrixRainGlyphTextKey: Hashable {
    var glyph: String
    var layerID: Int
    var tone: MatrixRainGlyphTone
    var isGlow: Bool
}

private enum MatrixRainGlyphTone: Hashable {
    case head
    case hotTrail
    case trail

    init(distance: Int) {
        if distance == 0 {
            self = .head
        } else if distance <= 3 {
            self = .hotTrail
        } else {
            self = .trail
        }
    }

    func fontWeight(isGlow: Bool) -> Font.Weight {
        self == .head || isGlow ? .bold : .regular
    }

    func color(isGlow: Bool) -> Color {
        if isGlow {
            return Color(red: 0.72, green: 1.0, blue: 0.62)
        }

        switch self {
        case .head:
            return Color(red: 0.91, green: 1.0, blue: 0.82)
        case .hotTrail:
            return Color(red: 0.58, green: 1.0, blue: 0.48)
        case .trail:
            return Color(red: 0.08, green: 0.90, blue: 0.22)
        }
    }
}

private extension MatrixRainDepthLayer {
    var cacheID: Int {
        switch self {
        case .distant: return 0
        case .middle: return 1
        case .near: return 2
        }
    }

}
