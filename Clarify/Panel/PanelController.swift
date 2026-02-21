import AppKit
import SwiftUI

@MainActor
final class PanelController {
    private var panel: OverlayPanel?
    private let appState: AppState
    private var clickOutsideMonitor: Any?
    private var keyDownMonitor: Any?
    private lazy var panelKeyEventTap = PanelKeyEventTap { [weak self] keyCode, flags in
        guard let self else { return false }
        return MainActor.assumeIsolated {
            self.appState.handleGlobalPanelKeyDown(keyCode: keyCode, flags: flags)
        }
    }

    init(appState: AppState) {
        self.appState = appState
    }

    func show(at anchorPoint: CGPoint) {
        removeMonitors()

        let estimatedHeight: CGFloat = Constants.resultPanelMinHeight
        let frame = PanelPositioner.frame(anchorPoint: anchorPoint, contentHeight: estimatedHeight)

        if panel == nil {
            panel = OverlayPanel(contentRect: frame)
        }

        let theme = appState.settingsManager?.currentTheme ?? .system
        let hostingView = NSHostingView(
            rootView: ExplanationView()
                .environment(appState)
                .environment(\.clarifyTheme, theme)
        )

        panel?.contentView = hostingView
        panel?.setFrame(frame, display: true)
        panel?.deactivateForInput()
        panel?.alphaValue = 0

        // Start scaled down for entrance animation
        if let layer = panel?.contentView?.layer {
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            let bounds = panel?.contentView?.bounds ?? .zero
            layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            layer.setAffineTransform(CGAffineTransform(scaleX: Constants.scaleFrom, y: Constants.scaleFrom))
        }

        // Keep the source app focused so selected text remains available for AX capture.
        panel?.orderFront(nil)
        panelKeyEventTap.start()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Constants.fadeInDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().alphaValue = 1
            if let layer = panel?.contentView?.layer {
                let scale = CABasicAnimation(keyPath: "transform.scale")
                scale.fromValue = Constants.scaleFrom
                scale.toValue = Constants.scaleTo
                scale.duration = Constants.fadeInDuration
                scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
                scale.isRemovedOnCompletion = true
                layer.add(scale, forKey: "entranceScale")
                layer.setAffineTransform(.identity)
            }
        }

        installMonitors()
    }

    func hide() {
        removeMonitors()
        panelKeyEventTap.stop()

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
                panel?.deactivateForInput()
                panel?.orderOut(nil)
                panel?.contentView?.layer?.removeAnimation(forKey: "dismissScale")
            }
        })
    }

    func activateForChat() {
        guard let panel else { return }
        panel.activateForInput()
        updateFrame(contentHeight: Constants.chatPanelMaxHeight, maxHeight: Constants.chatPanelMaxHeight)
    }

    func deactivateFromChat(contentHeight: CGFloat = Constants.resultPanelMinHeight) {
        guard let panel else { return }
        panel.deactivateForInput()
        updateFrame(contentHeight: contentHeight)
    }

    func updateFrame(contentHeight: CGFloat, maxHeight: CGFloat = Constants.panelMaxHeight) {
        guard let panel, let _ = panel.screen ?? NSScreen.main else { return }
        let currentOrigin = panel.frame.origin
        let anchorPoint = CGPoint(
            x: currentOrigin.x + panel.frame.width / 2,
            y: currentOrigin.y + panel.frame.height
        )
        let newFrame = PanelPositioner.frame(
            anchorPoint: anchorPoint,
            contentHeight: contentHeight,
            maxHeight: maxHeight
        )
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
                    guard self.appState.shouldDismissOnOutsideClick else { return }
                    self.appState.dismiss()
                }
            }
        }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.appState.handlePanelKeyDown(event) {
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
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
    }
}

private final class PanelKeyEventTap {
    private let lock = NSLock()
    private let onKeyDown: (_ keyCode: UInt16, _ flags: CGEventFlags) -> Bool
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isEnabled = false

    init(onKeyDown: @escaping (_ keyCode: UInt16, _ flags: CGEventFlags) -> Bool) {
        self.onKeyDown = onKeyDown
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }

        isEnabled = true

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let interceptor = Unmanaged<PanelKeyEventTap>.fromOpaque(userInfo).takeUnretainedValue()
                return interceptor.handleEvent(type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            isEnabled = false
            #if DEBUG
            print("[Clarify] Failed to install panel key event tap.")
            #endif
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.eventTap = eventTap
        self.runLoopSource = source
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }

        isEnabled = false
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }

        isEnabled = false

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }

        if let eventTap = eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let shouldReenable = isEnabled
            let eventTap = self.eventTap
            lock.unlock()

            if shouldReenable, let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        let shouldHandle = isEnabled
        lock.unlock()
        guard shouldHandle else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if onKeyDown(keyCode, event.flags) {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    deinit {
        invalidate()
    }
}
