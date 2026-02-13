import AppKit
import SwiftUI

@MainActor
final class PanelController {
    private var panel: OverlayPanel?
    private let appState: AppState
    private var clickOutsideMonitor: Any?
    private var escMonitor: Any?

    init(appState: AppState) {
        self.appState = appState
    }

    func show(at anchorPoint: CGPoint) {
        removeMonitors()

        let estimatedHeight: CGFloat = 200
        let frame = PanelPositioner.frame(anchorPoint: anchorPoint, contentHeight: estimatedHeight)

        if panel == nil {
            panel = OverlayPanel(contentRect: frame)
        }

        let hostingView = NSHostingView(
            rootView: ExplanationView()
                .environment(appState)
        )

        panel?.contentView = hostingView
        panel?.setFrame(frame, display: true)
        panel?.alphaValue = 0

        panel?.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Constants.fadeInDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().alphaValue = 1
        }

        installMonitors()
    }

    func hide() {
        removeMonitors()

        guard let panel else { return }

        let hostingView = panel.contentView
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Constants.fadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            if let layer = hostingView?.layer {
                let scale = CABasicAnimation(keyPath: "transform.scale")
                scale.fromValue = 1.0
                scale.toValue = 0.98
                scale.duration = Constants.fadeOutDuration
                scale.timingFunction = CAMediaTimingFunction(name: .easeIn)
                scale.isRemovedOnCompletion = false
                scale.fillMode = .forwards
                layer.add(scale, forKey: "dismissScale")
            }
        }, completionHandler: { [weak panel] in
            MainActor.assumeIsolated {
                panel?.orderOut(nil)
                panel?.contentView?.layer?.removeAnimation(forKey: "dismissScale")
            }
        })
    }

    func updateFrame(contentHeight: CGFloat) {
        guard let panel, let _ = panel.screen ?? NSScreen.main else { return }
        let currentOrigin = panel.frame.origin
        let anchorPoint = CGPoint(x: currentOrigin.x + panel.frame.width / 2,
                                  y: currentOrigin.y + panel.frame.height)
        let newFrame = PanelPositioner.frame(anchorPoint: anchorPoint, contentHeight: contentHeight)
        panel.setFrame(newFrame, display: true, animate: true)
    }

    // MARK: - Event Monitors

    private func installMonitors() {
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self, let panel = self.panel else { return }
                let locationInScreen = event.locationInWindow
                if !panel.frame.contains(locationInScreen) {
                    self.appState.dismiss()
                }
            }
        }

        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor [weak self] in
                    self?.appState.dismiss()
                }
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
    }
}
