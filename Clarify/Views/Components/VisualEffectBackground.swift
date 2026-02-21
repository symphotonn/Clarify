import SwiftUI
import AppKit

struct VisualEffectBackground: View {
    @Environment(\.clarifyTheme) private var theme

    var body: some View {
        if theme.useVibrancy {
            VibrancyView()
        } else {
            RoundedRectangle(cornerRadius: Constants.panelCornerRadius)
                .fill(theme.background)
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
                .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
        }
    }
}

private struct VibrancyView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = Constants.panelCornerRadius
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
