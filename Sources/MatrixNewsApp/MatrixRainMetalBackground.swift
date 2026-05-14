import SwiftUI

#if SWIFT_PACKAGE
import MatrixNewsCore
#endif

#if os(macOS)
import AppKit
import CoreText
import Metal
import MetalKit
#endif

enum MatrixRainRendererBackend: Equatable {
    case metal
    case canvas
}

enum MatrixRainRendererSelector {
    static func backend(platformSupportsMetalView: Bool, metalAvailable: Bool) -> MatrixRainRendererBackend {
        platformSupportsMetalView && metalAvailable ? .metal : .canvas
    }

    static var currentBackend: MatrixRainRendererBackend {
        #if os(macOS)
        backend(platformSupportsMetalView: true, metalAvailable: MatrixRainMetalRenderer.systemSupportsRenderer)
        #else
        .canvas
        #endif
    }
}

struct MatrixRainMetalPlaybackPolicy: Equatable, Sendable {
    static let activeFramesPerSecond = 60
    static let fallbackFramesPerSecond = 30
    static let occludedFramesPerSecond = 1

    var framesPerSecond: Int
    var isPaused: Bool
    var drawsOnDemand: Bool

    static func resolve(
        reduceMotion: Bool,
        applicationActive _: Bool,
        windowVisible: Bool,
        performanceFallback: Bool
    ) -> MatrixRainMetalPlaybackPolicy {
        if reduceMotion {
            return MatrixRainMetalPlaybackPolicy(
                framesPerSecond: occludedFramesPerSecond,
                isPaused: true,
                drawsOnDemand: true
            )
        }

        if !windowVisible {
            return MatrixRainMetalPlaybackPolicy(
                framesPerSecond: occludedFramesPerSecond,
                isPaused: false,
                drawsOnDemand: false
            )
        }

        return MatrixRainMetalPlaybackPolicy(
            framesPerSecond: performanceFallback ? fallbackFramesPerSecond : activeFramesPerSecond,
            isPaused: false,
            drawsOnDemand: false
        )
    }

    func animationSeconds(rawSeconds: TimeInterval) -> TimeInterval {
        guard !isPaused else { return 0 }
        let fps = Double(max(1, framesPerSecond))
        return floor(rawSeconds * fps) / fps
    }

    func animationSeconds(now: TimeInterval, start: TimeInterval) -> TimeInterval {
        animationSeconds(rawSeconds: max(0, now - start))
    }
}

enum MatrixRainMetalGlyphStyle: CaseIterable, Hashable, Sendable {
    case body
    case head
    case headGlow

    var atlasStyleID: UInt32 {
        switch self {
        case .body: return 0
        case .head: return 1
        case .headGlow: return 2
        }
    }
}

struct MatrixRainGlyphAtlasEntry: Equatable {
    var uvRect: CGRect
    var pixelRect: CGRect
    var pointSize: CGSize
    var fontSize: CGFloat
    var isBold: Bool
    var isGlow: Bool
}

struct MatrixRainGlyphAtlasLayout {
    static let cellEdge: CGFloat = 48
    static let columnCount = 32
    static let cellInset: CGFloat = 0.5
    static let styleCount = MatrixRainMetalGlyphStyle.allCases.count
    static let layerCount = MatrixRainDepthLayer.allCases.count

    var textureSize: CGSize
    var glyphs: [Character]
    private var entries: [MatrixRainGlyphAtlasKey: MatrixRainGlyphAtlasEntry]
    private var glyphIndices: [Character: UInt32]

    init(glyphComposer: MatrixRainGlyphComposer) {
        var glyphSet = Set(glyphComposer.baseGlyphs)
        glyphSet.formUnion(glyphComposer.valueFragments.joined())
        glyphs = glyphSet.sorted { String($0) < String($1) }
        let entryCount = max(1, glyphs.count * MatrixRainDepthLayer.allCases.count * MatrixRainMetalGlyphStyle.allCases.count)
        let rows = Int(ceil(Double(entryCount) / Double(Self.columnCount)))
        let textureWidth = CGFloat(Self.columnCount) * Self.cellEdge
        let textureHeight = CGFloat(rows) * Self.cellEdge

        textureSize = CGSize(width: textureWidth, height: textureHeight)
        entries = [:]
        entries.reserveCapacity(entryCount)
        glyphIndices = Dictionary(
            uniqueKeysWithValues: glyphs.enumerated().map { offset, glyph in
                (glyph, UInt32(offset))
            }
        )

        var index = 0
        for glyph in glyphs {
            for layer in MatrixRainDepthLayer.allCases {
                for style in MatrixRainMetalGlyphStyle.allCases {
                    let column = index % Self.columnCount
                    let row = index / Self.columnCount
                    let pixelRect = CGRect(
                        x: CGFloat(column) * Self.cellEdge,
                        y: CGFloat(row) * Self.cellEdge,
                        width: Self.cellEdge,
                        height: Self.cellEdge
                    )
                    let uvRect = CGRect(
                        x: (pixelRect.minX + Self.cellInset) / textureWidth,
                        y: (pixelRect.minY + Self.cellInset) / textureHeight,
                        width: (pixelRect.width - Self.cellInset * 2) / textureWidth,
                        height: (pixelRect.height - Self.cellInset * 2) / textureHeight
                    )
                    let key = MatrixRainGlyphAtlasKey(glyph: glyph, layer: layer, style: style)
                    entries[key] = MatrixRainGlyphAtlasEntry(
                        uvRect: uvRect,
                        pixelRect: pixelRect,
                        pointSize: pixelRect.size,
                        fontSize: Self.fontSize(for: layer, style: style),
                        isBold: style != .body,
                        isGlow: style == .headGlow
                    )
                    index += 1
                }
            }
        }
    }

    func entry(
        for glyph: Character,
        layer: MatrixRainDepthLayer,
        style: MatrixRainMetalGlyphStyle
    ) -> MatrixRainGlyphAtlasEntry? {
        entries[MatrixRainGlyphAtlasKey(glyph: glyph, layer: layer, style: style)]
    }

    func glyphIndex(for glyph: Character) -> UInt32? {
        glyphIndices[glyph]
    }

    private static func fontSize(for layer: MatrixRainDepthLayer, style: MatrixRainMetalGlyphStyle) -> CGFloat {
        let baseSize = CGFloat(layer.fontSize)
        switch style {
        case .body:
            return baseSize
        case .head, .headGlow:
            return baseSize * 1.08
        }
    }
}

private struct MatrixRainGlyphAtlasKey: Hashable {
    var glyph: Character
    var layerID: Int
    var style: MatrixRainMetalGlyphStyle

    init(glyph: Character, layer: MatrixRainDepthLayer, style: MatrixRainMetalGlyphStyle) {
        self.glyph = glyph
        layerID = layer.metalAtlasLayerID
        self.style = style
    }
}

private extension MatrixRainDepthLayer {
    var metalAtlasLayerID: Int {
        switch self {
        case .distant: return 0
        case .middle: return 1
        case .near: return 2
        }
    }
}

struct MatrixRainMetalStaticInstancePlan {
    var instances: [MatrixRainMetalStaticInstance]
    var baseGlyphAtlasIndices: [UInt32]
    var valueGlyphAtlasIndices: [UInt32]

    var requiresPerFrameCPUInstanceBuild: Bool { false }

    init(
        renderPlan: MatrixRainRenderPlan,
        glyphComposer: MatrixRainGlyphComposer,
        atlasLayout: MatrixRainGlyphAtlasLayout? = nil
    ) {
        let layout = atlasLayout ?? MatrixRainGlyphAtlasLayout(glyphComposer: glyphComposer)
        baseGlyphAtlasIndices = glyphComposer.baseGlyphs.compactMap { layout.glyphIndex(for: $0) }
        valueGlyphAtlasIndices = Array(glyphComposer.valueFragments.joined()).compactMap {
            layout.glyphIndex(for: $0)
        }
        instances = []
        instances.reserveCapacity(renderPlan.estimatedMetalInstances)

        for layerPlan in renderPlan.layers {
            Self.appendInstances(
                for: layerPlan,
                to: &instances
            )
        }
    }

    private static func appendInstances(
        for layerPlan: MatrixRainLayerRenderPlan,
        to instances: inout [MatrixRainMetalStaticInstance]
    ) {
        let layer = layerPlan.layer
        let profile = MatrixRainCinematicProfile(layer: layer)

        for columnPlan in layerPlan.sampledColumns {
            let motion = columnPlan.motion.metalParameters()

            for distance in layerPlan.visibleTailDistances {
                let alpha = profile.opacity(distanceFromHead: distance)
                let style: MatrixRainMetalGlyphStyle = distance == 0 ? .head : .body
                instances.append(
                    instance(
                        layerPlan: layerPlan,
                        column: columnPlan.column,
                        distance: distance,
                        motion: motion,
                        style: style,
                        color: glyphColor(distance: distance, opacity: alpha)
                    )
                )

                if distance == 0, layerPlan.headGlowOpacity > 0 {
                    instances.append(
                        instance(
                            layerPlan: layerPlan,
                            column: columnPlan.column,
                            distance: distance,
                            motion: motion,
                            style: .headGlow,
                            color: headGlowColor(
                                opacity: min(layerPlan.headGlowOpacity, alpha * 0.52)
                            )
                        )
                    )
                }
            }
        }
    }

    private static func instance(
        layerPlan: MatrixRainLayerRenderPlan,
        column: Int,
        distance: Int,
        motion: MatrixRainColumnMetalMotionParameters,
        style: MatrixRainMetalGlyphStyle,
        color: SIMD4<Float>
    ) -> MatrixRainMetalStaticInstance {
        let layer = layerPlan.layer
        return MatrixRainMetalStaticInstance(
            column: Float(column),
            distance: Float(distance),
            rows: Float(layerPlan.rows),
            tailLength: Float(layer.tailLength),
            columnWidth: Float(layer.columnWidth),
            rowHeight: Float(layer.rowHeight),
            speedRowsPerSecond: Float(motion.speedRowsPerSecond),
            phaseRows: Float(motion.phaseRows),
            gapRows: Float(motion.gapRows),
            driftPhase: Float(motion.driftPhase),
            driftRate: Float(motion.driftRate),
            driftMagnitude: Float(motion.driftMagnitude),
            layerID: Float(layer.metalAtlasLayerID),
            styleID: Float(style.atlasStyleID),
            color: color,
            size: SIMD2(Float(MatrixRainGlyphAtlasLayout.cellEdge), Float(MatrixRainGlyphAtlasLayout.cellEdge)),
            padding: .zero
        )
    }

    private static func glyphColor(distance: Int, opacity: Double) -> SIMD4<Float> {
        let rgb: SIMD3<Float>
        if distance == 0 {
            rgb = SIMD3(0.91, 1.0, 0.82)
        } else if distance <= 3 {
            rgb = SIMD3(0.58, 1.0, 0.48)
        } else {
            rgb = SIMD3(0.08, 0.90, 0.22)
        }

        return SIMD4(rgb.x, rgb.y, rgb.z, Float(opacity))
    }

    private static func headGlowColor(opacity: Double) -> SIMD4<Float> {
        SIMD4(0.72, 1.0, 0.62, Float(opacity))
    }
}

struct MatrixRainMetalStaticInstance {
    var column: Float
    var distance: Float
    var rows: Float
    var tailLength: Float
    var columnWidth: Float
    var rowHeight: Float
    var speedRowsPerSecond: Float
    var phaseRows: Float
    var gapRows: Float
    var driftPhase: Float
    var driftRate: Float
    var driftMagnitude: Float
    var layerID: Float
    var styleID: Float
    var color: SIMD4<Float>
    var size: SIMD2<Float>
    var padding: SIMD2<Float>
}

#if os(macOS)
struct MetalMatrixRainBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MatrixRainMetalView(reduceMotion: reduceMotion)
    }
}

private struct MatrixRainMetalView: NSViewRepresentable {
    var reduceMotion: Bool
    var performanceFallback = false

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        guard let view = context.coordinator.makeMetalView(
            reduceMotion: reduceMotion,
            performanceFallback: performanceFallback
        ) else {
            return NSHostingView(rootView: CanvasMatrixRainBackground())
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? MTKView else { return }
        context.coordinator.update(
            view,
            reduceMotion: reduceMotion,
            performanceFallback: performanceFallback
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var metalView: MTKView?
        private var renderer: MatrixRainMetalRenderer?
        private var reduceMotion = false
        private var performanceFallback = false

        override init() {
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applicationStateDidChange),
                name: NSApplication.didBecomeActiveNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applicationStateDidChange),
                name: NSApplication.didResignActiveNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowOcclusionDidChange(_:)),
                name: NSWindow.didChangeOcclusionStateNotification,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func makeMetalView(reduceMotion: Bool, performanceFallback: Bool) -> MTKView? {
            guard let device = MTLCreateSystemDefaultDevice() else { return nil }

            let view = MTKView(frame: .zero, device: device)
            view.colorPixelFormat = .bgra8Unorm
            view.clearColor = MTLClearColorMake(0, 0.018, 0.006, 1)
            view.depthStencilPixelFormat = .invalid
            view.framebufferOnly = true
            view.autoResizeDrawable = true

            do {
                let renderer = try MatrixRainMetalRenderer(device: device)
                self.renderer = renderer
                metalView = view
                view.delegate = renderer
                update(view, reduceMotion: reduceMotion, performanceFallback: performanceFallback)
                return view
            } catch {
                return nil
            }
        }

        func update(_ view: MTKView, reduceMotion: Bool, performanceFallback: Bool) {
            self.reduceMotion = reduceMotion
            self.performanceFallback = performanceFallback
            applyCurrentPolicy(to: view)
        }

        @objc private func applicationStateDidChange() {
            guard let metalView else { return }
            applyCurrentPolicy(to: metalView)
        }

        @objc private func windowOcclusionDidChange(_ notification: Notification) {
            guard let window = notification.object as? NSWindow, window == metalView?.window else { return }
            guard let metalView else { return }
            applyCurrentPolicy(to: metalView)
        }

        private func applyCurrentPolicy(to view: MTKView) {
            let windowVisible = view.window?.occlusionState.contains(.visible) ?? true
            let policy = MatrixRainMetalPlaybackPolicy.resolve(
                reduceMotion: reduceMotion,
                applicationActive: NSApplication.shared.isActive,
                windowVisible: windowVisible,
                performanceFallback: performanceFallback
            )

            view.preferredFramesPerSecond = policy.framesPerSecond
            view.enableSetNeedsDisplay = policy.drawsOnDemand
            view.isPaused = policy.isPaused
            renderer?.updatePlaybackPolicy(policy)

            if policy.drawsOnDemand {
                view.draw()
            }
        }
    }
}

private final class MatrixRainMetalRenderer: NSObject, MTKViewDelegate {
    static let systemSupportsRenderer: Bool = {
        guard let device = MTLCreateSystemDefaultDevice(),
              device.makeCommandQueue() != nil else {
            return false
        }
        return (try? device.makeLibrary(source: shaderSource, options: nil)) != nil
    }()

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let backgroundPipeline: MTLRenderPipelineState
    private let glyphPipeline: MTLRenderPipelineState
    private let samplerState: MTLSamplerState
    private let glyphAtlas: MatrixRainGlyphAtlas
    private let glyphComposer = MatrixRainGlyphComposer()
    private var playbackPolicy = MatrixRainMetalPlaybackPolicy.resolve(
        reduceMotion: false,
        applicationActive: true,
        windowVisible: true,
        performanceFallback: false
    )
    private var cachedPlan: MatrixRainRenderPlan?
    private var cachedStaticPlan: MatrixRainMetalStaticInstancePlan?
    private var staticInstanceBuffer: MTLBuffer?
    private var baseGlyphIndexBuffer: MTLBuffer?
    private var valueGlyphIndexBuffer: MTLBuffer?
    private let animationStartSeconds = ProcessInfo.processInfo.systemUptime

    init(device: MTLDevice) throws {
        self.device = device
        guard let commandQueue = device.makeCommandQueue() else {
            throw MatrixRainMetalRendererError.commandQueueUnavailable
        }
        self.commandQueue = commandQueue

        let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        guard let backgroundVertex = library.makeFunction(name: "matrixRainBackgroundVertex"),
              let backgroundFragment = library.makeFunction(name: "matrixRainBackgroundFragment"),
              let glyphVertex = library.makeFunction(name: "matrixRainGlyphVertex"),
              let glyphFragment = library.makeFunction(name: "matrixRainGlyphFragment") else {
            throw MatrixRainMetalRendererError.shaderFunctionUnavailable
        }

        let backgroundDescriptor = MTLRenderPipelineDescriptor()
        backgroundDescriptor.vertexFunction = backgroundVertex
        backgroundDescriptor.fragmentFunction = backgroundFragment
        backgroundDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        backgroundPipeline = try device.makeRenderPipelineState(descriptor: backgroundDescriptor)

        let glyphDescriptor = MTLRenderPipelineDescriptor()
        glyphDescriptor.vertexFunction = glyphVertex
        glyphDescriptor.fragmentFunction = glyphFragment
        glyphDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        glyphDescriptor.colorAttachments[0].isBlendingEnabled = true
        glyphDescriptor.colorAttachments[0].rgbBlendOperation = .add
        glyphDescriptor.colorAttachments[0].alphaBlendOperation = .add
        glyphDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        glyphDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        glyphDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        glyphDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        glyphPipeline = try device.makeRenderPipelineState(descriptor: glyphDescriptor)

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let samplerState = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw MatrixRainMetalRendererError.samplerUnavailable
        }
        self.samplerState = samplerState
        glyphAtlas = try MatrixRainGlyphAtlas(device: device, glyphComposer: glyphComposer)

        super.init()
    }

    func updatePlaybackPolicy(_ policy: MatrixRainMetalPlaybackPolicy) {
        playbackPolicy = policy
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        cachedPlan = nil
        cachedStaticPlan = nil
        staticInstanceBuffer = nil
        baseGlyphIndexBuffer = nil
        valueGlyphIndexBuffer = nil
    }

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        let drawableSize = view.drawableSize
        guard drawableSize.width > 1, drawableSize.height > 1 else {
            encoder.endEncoding()
            commandBuffer.commit()
            return
        }

        let boundsSize = view.bounds.size
        let planSize = boundsSize.width > 1 && boundsSize.height > 1 ? boundsSize : drawableSize
        let scaleX = drawableSize.width / max(1, planSize.width)
        let scaleY = drawableSize.height / max(1, planSize.height)
        let plan = renderPlan(size: planSize)
        let seconds = playbackPolicy.animationSeconds(
            now: ProcessInfo.processInfo.systemUptime,
            start: animationStartSeconds
        )
        var uniforms = MatrixRainMetalUniforms(
            viewportSize: SIMD2(Float(drawableSize.width), Float(drawableSize.height)),
            pointScale: SIMD2(Float(scaleX), Float(scaleY)),
            scanlineSpacing: Float(plan.scanlineSpacing * scaleY),
            time: Float(seconds),
            valueBlendThreshold: Float(plan.metalValueBlendThreshold),
            baseGlyphCount: Float(max(1, glyphComposer.baseGlyphs.count)),
            valueGlyphCount: Float(max(1, glyphComposer.valueFragments.joined().count)),
            atlasColumnCount: Float(MatrixRainGlyphAtlasLayout.columnCount),
            atlasCellEdge: Float(MatrixRainGlyphAtlasLayout.cellEdge),
            atlasWidth: Float(glyphAtlas.layout.textureSize.width),
            atlasHeight: Float(glyphAtlas.layout.textureSize.height),
            atlasInset: Float(MatrixRainGlyphAtlasLayout.cellInset),
            atlasStyleCount: Float(MatrixRainGlyphAtlasLayout.styleCount),
            atlasLayerCount: Float(MatrixRainGlyphAtlasLayout.layerCount),
            padding: .zero
        )

        encoder.setRenderPipelineState(backgroundPipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<MatrixRainMetalUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MatrixRainMetalUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        let staticPlan = staticPlan(for: plan)
        ensureStaticBuffers(staticPlan: staticPlan)
        if !staticPlan.instances.isEmpty,
           let instanceBuffer = staticInstanceBuffer,
           let baseGlyphIndexBuffer,
           let valueGlyphIndexBuffer {
            encoder.setRenderPipelineState(glyphPipeline)
            encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<MatrixRainMetalUniforms>.stride, index: 1)
            encoder.setVertexBuffer(baseGlyphIndexBuffer, offset: 0, index: 2)
            encoder.setVertexBuffer(valueGlyphIndexBuffer, offset: 0, index: 3)
            encoder.setFragmentTexture(glyphAtlas.texture, index: 0)
            encoder.setFragmentSamplerState(samplerState, index: 0)
            encoder.drawPrimitives(
                type: .triangleStrip,
                vertexStart: 0,
                vertexCount: 4,
                instanceCount: staticPlan.instances.count
            )
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func renderPlan(size: CGSize) -> MatrixRainRenderPlan {
        if let cachedPlan, cachedPlan.size == size {
            return cachedPlan
        }

        let plan = MatrixRainRenderPlan(size: size)
        cachedPlan = plan
        return plan
    }

    private func staticPlan(for renderPlan: MatrixRainRenderPlan) -> MatrixRainMetalStaticInstancePlan {
        if let cachedStaticPlan, cachedPlan?.size == renderPlan.size {
            return cachedStaticPlan
        }

        let staticPlan = MatrixRainMetalStaticInstancePlan(
            renderPlan: renderPlan,
            glyphComposer: glyphComposer,
            atlasLayout: glyphAtlas.layout
        )
        cachedStaticPlan = staticPlan
        return staticPlan
    }

    private func ensureStaticBuffers(staticPlan: MatrixRainMetalStaticInstancePlan) {
        guard staticInstanceBuffer == nil else { return }

        staticInstanceBuffer = makeBuffer(from: staticPlan.instances)
        baseGlyphIndexBuffer = makeBuffer(from: staticPlan.baseGlyphAtlasIndices)
        valueGlyphIndexBuffer = makeBuffer(from: staticPlan.valueGlyphAtlasIndices)
    }

    private func makeBuffer<Element>(from values: [Element]) -> MTLBuffer? {
        guard !values.isEmpty else { return nil }

        return values.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return nil }
            return device.makeBuffer(
                bytes: baseAddress,
                length: bytes.count,
                options: .storageModeShared
            )
        }
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 viewportSize;
        float2 pointScale;
        float scanlineSpacing;
        float time;
        float valueBlendThreshold;
        float baseGlyphCount;
        float valueGlyphCount;
        float atlasColumnCount;
        float atlasCellEdge;
        float atlasWidth;
        float atlasHeight;
        float atlasInset;
        float atlasStyleCount;
        float atlasLayerCount;
        float2 padding;
    };

    struct BackgroundOut {
        float4 position [[position]];
    };

    vertex BackgroundOut matrixRainBackgroundVertex(uint vertexID [[vertex_id]]) {
        float2 positions[3] = {
            float2(-1.0, -1.0),
            float2(3.0, -1.0),
            float2(-1.0, 3.0)
        };

        BackgroundOut out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        return out;
    }

    fragment float4 matrixRainBackgroundFragment(
        BackgroundOut in [[stage_in]],
        constant Uniforms &uniforms [[buffer(0)]]
    ) {
        float2 viewport = max(uniforms.viewportSize, float2(1.0, 1.0));
        float2 p = clamp(in.position.xy / viewport, float2(0.0), float2(1.0));
        float3 top = float3(0.0, 0.018, 0.006) * 0.28;
        float3 mid = float3(0.0, 0.080, 0.025) * 0.46;
        float3 bottom = float3(0.0, 0.006, 0.002);
        float3 color = mix(top, mid, smoothstep(0.0, 0.48, p.y));
        color = mix(color, bottom, smoothstep(0.46, 1.0, p.y));

        float aspect = viewport.x / viewport.y;
        float2 centered = (p - float2(0.5, 0.46)) * float2(aspect, 1.0);
        float vignette = smoothstep(0.20, 0.72, length(centered));
        color = mix(color, float3(0.0), vignette * 0.58);

        float spacing = max(1.0, uniforms.scanlineSpacing);
        float line = 1.0 - smoothstep(0.0, 0.72, fmod(in.position.y, spacing));
        float shimmer = 0.010 + 0.008 * (0.5 + 0.5 * sin(in.position.y * 0.017));
        color += float3(0.0, 1.0, 0.25) * line * shimmer;

        return float4(color, 1.0);
    }

    struct Instance {
        float column;
        float distance;
        float rows;
        float tailLength;
        float columnWidth;
        float rowHeight;
        float speedRowsPerSecond;
        float phaseRows;
        float gapRows;
        float driftPhase;
        float driftRate;
        float driftMagnitude;
        float layerID;
        float styleID;
        float4 color;
        float2 size;
        float2 padding;
    };

    struct GlyphOut {
        float4 position [[position]];
        float2 uv;
        float4 color;
    };

    uint positiveHash(int column, int row, int tick) {
        uint value = uint(column) * 73856093u;
        value ^= uint(row) * 19349663u;
        value ^= uint(tick) * 83492791u;
        value ^= value >> 13u;
        return value;
    }

    uint orientationHash(int column, int row) {
        uint value = uint(column) * 73856093u;
        value ^= uint(row) * 19349663u;
        value ^= value >> 13u;
        return value;
    }

    float positiveRemainder(float value, float divisor) {
        if (divisor <= 0.0) {
            return 0.0;
        }
        float remainder = fmod(value, divisor);
        return remainder >= 0.0 ? remainder : remainder + divisor;
    }

    int positiveModulo(int value, int divisor) {
        if (divisor <= 0) {
            return 0;
        }
        int remainder = value % divisor;
        return remainder >= 0 ? remainder : remainder + divisor;
    }

    vertex GlyphOut matrixRainGlyphVertex(
        uint vertexID [[vertex_id]],
        uint instanceID [[instance_id]],
        const device Instance *instances [[buffer(0)]],
        constant Uniforms &uniforms [[buffer(1)]],
        const device uint *baseGlyphIndices [[buffer(2)]],
        const device uint *valueGlyphIndices [[buffer(3)]]
    ) {
        float2 corners[4] = {
            float2(-0.5, -0.5),
            float2(0.5, -0.5),
            float2(-0.5, 0.5),
            float2(0.5, 0.5)
        };
        float2 uvCorners[4] = {
            float2(0.0, 0.0),
            float2(1.0, 0.0),
            float2(0.0, 1.0),
            float2(1.0, 1.0)
        };

        Instance instance = instances[instanceID];
        float cycleRows = max(1.0, instance.rows + instance.gapRows);
        float headProgress = positiveRemainder(
            instance.phaseRows + uniforms.time * instance.speedRowsPerSecond,
            cycleRows
        );
        int row = positiveModulo(
            int(floor(headProgress)) + int(round(instance.distance)),
            int(max(1.0, instance.rows))
        );
        int column = int(round(instance.column));
        int tick = int(floor(uniforms.time * 2.0));
        uint hash = positiveHash(column, row, tick);
        uint glyphIndex = baseGlyphIndices[hash % uint(max(1.0, uniforms.baseGlyphCount))];
        if (uniforms.valueGlyphCount > 0.0 && (hash % 97u) < uint(uniforms.valueBlendThreshold)) {
            uint valueIndex = (hash / 97u + uint(max(0, row)) + uint(max(0, tick))) % uint(max(1.0, uniforms.valueGlyphCount));
            glyphIndex = valueGlyphIndices[valueIndex];
        }

        uint styleID = uint(max(0.0, instance.styleID));
        uint layerID = uint(max(0.0, instance.layerID));
        uint atlasIndex = (glyphIndex * uint(uniforms.atlasLayerCount) + layerID) * uint(uniforms.atlasStyleCount) + styleID;
        float2 cellOrigin = float2(
            float(atlasIndex % uint(uniforms.atlasColumnCount)) * uniforms.atlasCellEdge,
            float(atlasIndex / uint(uniforms.atlasColumnCount)) * uniforms.atlasCellEdge
        );
        float2 uvOrigin = (cellOrigin + uniforms.atlasInset) / float2(uniforms.atlasWidth, uniforms.atlasHeight);
        float2 uvSize = (float2(uniforms.atlasCellEdge - uniforms.atlasInset * 2.0)) / float2(uniforms.atlasWidth, uniforms.atlasHeight);

        float x = instance.column * instance.columnWidth
            + instance.columnWidth * 0.5
            + sin(uniforms.time * instance.driftRate + instance.driftPhase) * instance.columnWidth * instance.driftMagnitude;
        float y = (headProgress + instance.distance - instance.tailLength) * instance.rowHeight;

        uint orientation = orientationHash(column, row);
        float2 orientationScale = float2((orientation % 29u) == 0u ? -1.0 : 1.0, (orientation % 997u) == 0u ? -1.0 : 1.0);
        float2 pixel = float2(x, y) * uniforms.pointScale
            + corners[vertexID] * instance.size * uniforms.pointScale * orientationScale;
        float2 viewport = max(uniforms.viewportSize, float2(1.0, 1.0));
        float2 clip = float2(
            pixel.x / viewport.x * 2.0 - 1.0,
            1.0 - pixel.y / viewport.y * 2.0
        );

        GlyphOut out;
        out.position = float4(clip, 0.0, 1.0);
        out.uv = uvOrigin + uvCorners[vertexID] * uvSize;
        out.color = instance.color;
        return out;
    }

    fragment float4 matrixRainGlyphFragment(
        GlyphOut in [[stage_in]],
        texture2d<float> atlas [[texture(0)]],
        sampler atlasSampler [[sampler(0)]]
    ) {
        float alpha = atlas.sample(atlasSampler, in.uv).a * in.color.a;
        return float4(in.color.rgb, alpha);
    }
    """
}

private struct MatrixRainMetalUniforms {
    var viewportSize: SIMD2<Float>
    var pointScale: SIMD2<Float>
    var scanlineSpacing: Float
    var time: Float
    var valueBlendThreshold: Float
    var baseGlyphCount: Float
    var valueGlyphCount: Float
    var atlasColumnCount: Float
    var atlasCellEdge: Float
    var atlasWidth: Float
    var atlasHeight: Float
    var atlasInset: Float
    var atlasStyleCount: Float
    var atlasLayerCount: Float
    var padding: SIMD2<Float>
}

private enum MatrixRainMetalRendererError: Error {
    case commandQueueUnavailable
    case samplerUnavailable
    case shaderFunctionUnavailable
}

private enum MatrixRainMetalColor {
    static func glyph(distance: Int, opacity: Double) -> SIMD4<Float> {
        let rgb: SIMD3<Float>
        if distance == 0 {
            rgb = SIMD3(0.91, 1.0, 0.82)
        } else if distance <= 3 {
            rgb = SIMD3(0.58, 1.0, 0.48)
        } else {
            rgb = SIMD3(0.08, 0.90, 0.22)
        }

        return SIMD4(rgb.x, rgb.y, rgb.z, Float(opacity))
    }

    static func headGlow(opacity: Double) -> SIMD4<Float> {
        SIMD4(0.72, 1.0, 0.62, Float(opacity))
    }
}

private final class MatrixRainGlyphAtlas {
    let layout: MatrixRainGlyphAtlasLayout
    let texture: MTLTexture

    init(device: MTLDevice, glyphComposer: MatrixRainGlyphComposer) throws {
        let atlasLayout = MatrixRainGlyphAtlasLayout(glyphComposer: glyphComposer)
        layout = atlasLayout

        let width = Int(atlasLayout.textureSize.width.rounded(.up))
        let height = Int(atlasLayout.textureSize.height.rounded(.up))
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        pixels.withUnsafeMutableBytes { rawBuffer in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return
            }

            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            context.setAllowsFontSmoothing(true)
            context.setShouldSmoothFonts(true)

            var glyphSet = Set(glyphComposer.baseGlyphs)
            glyphSet.formUnion(glyphComposer.valueFragments.joined())

            for glyph in glyphSet {
                for layer in MatrixRainDepthLayer.allCases {
                    for style in MatrixRainMetalGlyphStyle.allCases {
                        guard let entry = atlasLayout.entry(for: glyph, layer: layer, style: style) else {
                            continue
                        }
                        Self.drawGlyph(glyph, entry: entry, layer: layer, in: context)
                    }
                }
            }
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw MatrixRainGlyphAtlasError.textureUnavailable
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: bytesPerRow
        )
        self.texture = texture
    }

    private static func drawGlyph(
        _ glyph: Character,
        entry: MatrixRainGlyphAtlasEntry,
        layer: MatrixRainDepthLayer,
        in context: CGContext
    ) {
        let rect = entry.pixelRect.integral
        let fontWeight: NSFont.Weight = entry.isBold ? .bold : .regular
        let font = NSFont.monospacedSystemFont(ofSize: entry.fontSize, weight: fontWeight)
        let color = NSColor.white.withAlphaComponent(entry.isGlow ? 0.88 : 1.0)
        let attributed = NSAttributedString(
            string: String(glyph),
            attributes: [
                .font: font,
                .foregroundColor: color
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

        context.saveGState()
        context.clip(to: rect)
        if entry.isGlow {
            context.setShadow(
                offset: .zero,
                blur: CGFloat(layer.glowRadius) * 1.35,
                color: NSColor.white.withAlphaComponent(0.82).cgColor
            )
        }
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = CGPoint(
            x: (rect.width - lineWidth) * 0.5,
            y: (rect.height - ascent - descent) * 0.5 + descent
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

private enum MatrixRainGlyphAtlasError: Error {
    case textureUnavailable
}
#endif
