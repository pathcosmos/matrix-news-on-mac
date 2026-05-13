import SwiftUI

#if os(macOS)
import AppKit

struct MacWindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ChromeConfigurationView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Self.configure(nsView.window)
    }

    private static func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true

        if #available(macOS 11.0, *) {
            window.toolbarStyle = .unifiedCompact
        }

        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
    }

    private final class ChromeConfigurationView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async {
                MacWindowChromeConfigurator.configure(self.window)
            }
        }
    }
}

extension View {
    func matrixMacWindowChrome() -> some View {
        background {
            MacWindowChromeConfigurator()
                .allowsHitTesting(false)
        }
    }
}
#else
extension View {
    func matrixMacWindowChrome() -> some View {
        self
    }
}
#endif
