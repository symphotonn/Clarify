import SwiftUI
import AppKit

struct VisualEffectBackground: NSViewRepresentable {
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
