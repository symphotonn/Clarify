import AppKit

final class OverlayPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: true
        )

        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        // Rounded corners
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = Constants.panelCornerRadius
        contentView?.layer?.masksToBounds = true

        // Allow key events for Esc dismissal
        acceptsMouseMovedEvents = true

        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
