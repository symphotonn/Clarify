import AppKit
import Carbon.HIToolbox

final class HotkeyManager: @unchecked Sendable {
    typealias HotkeyHandler = (_ isDoublePress: Bool) -> Void
    typealias RegistrationStatusHandler = (_ issue: String?) -> Void

    private static let hotKeySignature: OSType = 0x434C5259 // CLRY
    private static let hotKeyIdentifier: UInt32 = 1

    private let handler: HotkeyHandler
    private let doublePressDetector = DoublePressDetector()
    private let lock = NSLock()
    private var hotkey: HotkeyBinding
    private var isHandlingEnabled = true
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    var onRegistrationStatusChanged: RegistrationStatusHandler?

    init(hotkey: HotkeyBinding, handler: @escaping HotkeyHandler) {
        self.hotkey = hotkey
        self.handler = handler
    }

    func updateHotkey(_ hotkey: HotkeyBinding) {
        lock.lock()
        self.hotkey = hotkey
        lock.unlock()
        doublePressDetector.reset()
        registerHotkey()
    }

    func start() {
        installEventHandlerIfNeeded()
        registerHotkey()
    }

    func stop() {
        unregisterHotkey()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    func setHandlingEnabled(_ isEnabled: Bool) {
        lock.lock()
        isHandlingEnabled = isEnabled
        lock.unlock()

        if !isEnabled {
            doublePressDetector.reset()
        }
    }

    fileprivate func handleHotkeyEvent(_ event: EventRef?) -> OSStatus {
        guard let event else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }

        guard hotKeyID.signature == Self.hotKeySignature, hotKeyID.id == Self.hotKeyIdentifier else {
            return OSStatus(eventNotHandledErr)
        }

        lock.lock()
        let shouldHandle = isHandlingEnabled
        lock.unlock()
        guard shouldHandle else {
            return noErr
        }

        let isDoublePress = doublePressDetector.recordPress()
        handler(isDoublePress)
        return noErr
    }

    static func isHotkeyMatch(keyCode: UInt16, flags: CGEventFlags, hotkey: HotkeyBinding) -> Bool {
        hotkey.matches(keyCode: keyCode, flags: flags)
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            carbonHotkeyCallback,
            1,
            &eventSpec,
            refcon,
            &eventHandlerRef
        )

        if status != noErr {
            print("[Clarify] Failed to install hotkey event handler. OSStatus=\(status)")
            onRegistrationStatusChanged?("Hotkey listener unavailable (OSStatus \(status)). Restart the app and check Accessibility permissions.")
        }
    }

    private func registerHotkey() {
        unregisterHotkey()

        guard eventHandlerRef != nil else { return }

        let hotkey: HotkeyBinding
        lock.lock()
        hotkey = self.hotkey
        lock.unlock()

        let hotKeyID = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: Self.hotKeyIdentifier
        )

        let status = RegisterEventHotKey(
            UInt32(hotkey.key.keyCode),
            Self.carbonModifiers(for: hotkey),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            hotKeyRef = nil
            print("[Clarify] Failed to register hotkey \(hotkey.displayText). OSStatus=\(status). The shortcut may conflict with a system or app shortcut.")
            onRegistrationStatusChanged?("Shortcut \(hotkey.displayText) is unavailable (OSStatus \(status)). It may conflict with another shortcut.")
        } else {
            onRegistrationStatusChanged?(nil)
        }
    }

    private func unregisterHotkey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private static func carbonModifiers(for hotkey: HotkeyBinding) -> UInt32 {
        var modifiers: UInt32 = 0
        if hotkey.useCommand { modifiers |= UInt32(cmdKey) }
        if hotkey.useOption { modifiers |= UInt32(optionKey) }
        if hotkey.useControl { modifiers |= UInt32(controlKey) }
        if hotkey.useShift { modifiers |= UInt32(shiftKey) }
        return modifiers
    }
}

private func carbonHotkeyCallback(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else {
        return OSStatus(eventNotHandledErr)
    }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    return manager.handleHotkeyEvent(event)
}
