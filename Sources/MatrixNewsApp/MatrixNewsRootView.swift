import SwiftUI

#if SWIFT_PACKAGE
import MatrixNewsCore
#endif

struct MatrixNewsRootView: View {
    @EnvironmentObject private var model: NewsViewModel

    var body: some View {
        ZStack {
            MatrixRainBackground()
                .ignoresSafeArea()

            TypewriterNewsView(
                items: model.passiveDisplayItems,
                playbackRevision: model.playbackRevision
            )

            VStack(spacing: 0) {
                MatrixChromeBar()
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(Color(red: 0.76, green: 1.0, blue: 0.77))
    }
}

private struct MatrixChromeBar: View {
    @EnvironmentObject private var model: NewsViewModel

    var body: some View {
        HStack(spacing: 14) {
            Text("MATRIX NEWS")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))

            Divider()
                .frame(height: 18)
                .overlay(.green.opacity(0.38))

            Text("MBC")
                .foregroundStyle(.green.opacity(0.82))

            Text("LATEST")
                .foregroundStyle(.white.opacity(0.66))

            Spacer(minLength: 0)

            Text("\(model.passiveDisplayItems.count)/50")
                .foregroundStyle(.green.opacity(0.78))

            Text(statusText)
                .foregroundStyle(.white.opacity(0.56))
        }
        .font(.system(size: 13, weight: .medium, design: .monospaced))
        .lineLimit(1)
        .frame(height: 52)
        .padding(.trailing, 18)
        .padding(.leading, leadingPadding)
        .background {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color(red: 0.0, green: 0.035, blue: 0.012).opacity(0.96),
                        .black.opacity(0.74),
                        .black.opacity(0.16),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                MatrixChromeGlyphStrip()
                    .opacity(0.24)

                LinearGradient(
                    colors: [.green.opacity(0.18), .clear, .green.opacity(0.10)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 1)
                .padding(.bottom, 7)
            }
            .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.green.opacity(0.12))
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .green.opacity(0.42), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
    }

    private var statusText: String {
        model.passiveDisplayItems.isEmpty ? "STANDBY" : "LIVE"
    }

    private var leadingPadding: CGFloat {
        #if os(macOS)
        return 96
        #else
        return 18
        #endif
    }
}

private struct MatrixChromeGlyphStrip: View {
    private let rows = [
        "0101 SYS MBC LATEST 1010 FEED OK",
        "1100 DATA STREAM 0011 LIVE 0101",
        "0010 NEWS CACHE 50/50 1110"
    ]

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    Text(repeating(row, toFill: proxy.size.width))
                        .font(.system(size: 8 + CGFloat(index), weight: .medium, design: .monospaced))
                        .foregroundStyle(index == 0 ? .white.opacity(0.42) : .green.opacity(0.54))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .offset(x: CGFloat(index * 23))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .clipped()
        }
        .allowsHitTesting(false)
    }

    private func repeating(_ value: String, toFill width: CGFloat) -> String {
        let repeats = max(2, Int(width / 190) + 2)
        return Array(repeating: value, count: repeats).joined(separator: "   ")
    }
}
