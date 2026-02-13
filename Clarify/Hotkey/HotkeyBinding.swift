import AppKit
import Carbon.HIToolbox

enum HotkeyKey: String, CaseIterable {
    case space
    case `return`
    case tab
    case slash
    case backslash
    case comma
    case period

    case a
    case b
    case c
    case d
    case e
    case f
    case g
    case h
    case i
    case j
    case k
    case l
    case m
    case n
    case o
    case p
    case q
    case r
    case s
    case t
    case u
    case v
    case w
    case x
    case y
    case z

    case zero
    case one
    case two
    case three
    case four
    case five
    case six
    case seven
    case eight
    case nine

    var displayName: String {
        switch self {
        case .space: return "Space"
        case .return: return "Return"
        case .tab: return "Tab"
        case .slash: return "/"
        case .backslash: return "\\"
        case .comma: return ","
        case .period: return "."
        case .a: return "A"
        case .b: return "B"
        case .c: return "C"
        case .d: return "D"
        case .e: return "E"
        case .f: return "F"
        case .g: return "G"
        case .h: return "H"
        case .i: return "I"
        case .j: return "J"
        case .k: return "K"
        case .l: return "L"
        case .m: return "M"
        case .n: return "N"
        case .o: return "O"
        case .p: return "P"
        case .q: return "Q"
        case .r: return "R"
        case .s: return "S"
        case .t: return "T"
        case .u: return "U"
        case .v: return "V"
        case .w: return "W"
        case .x: return "X"
        case .y: return "Y"
        case .z: return "Z"
        case .zero: return "0"
        case .one: return "1"
        case .two: return "2"
        case .three: return "3"
        case .four: return "4"
        case .five: return "5"
        case .six: return "6"
        case .seven: return "7"
        case .eight: return "8"
        case .nine: return "9"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .space: return UInt16(kVK_Space)
        case .return: return UInt16(kVK_Return)
        case .tab: return UInt16(kVK_Tab)
        case .slash: return UInt16(kVK_ANSI_Slash)
        case .backslash: return UInt16(kVK_ANSI_Backslash)
        case .comma: return UInt16(kVK_ANSI_Comma)
        case .period: return UInt16(kVK_ANSI_Period)
        case .a: return UInt16(kVK_ANSI_A)
        case .b: return UInt16(kVK_ANSI_B)
        case .c: return UInt16(kVK_ANSI_C)
        case .d: return UInt16(kVK_ANSI_D)
        case .e: return UInt16(kVK_ANSI_E)
        case .f: return UInt16(kVK_ANSI_F)
        case .g: return UInt16(kVK_ANSI_G)
        case .h: return UInt16(kVK_ANSI_H)
        case .i: return UInt16(kVK_ANSI_I)
        case .j: return UInt16(kVK_ANSI_J)
        case .k: return UInt16(kVK_ANSI_K)
        case .l: return UInt16(kVK_ANSI_L)
        case .m: return UInt16(kVK_ANSI_M)
        case .n: return UInt16(kVK_ANSI_N)
        case .o: return UInt16(kVK_ANSI_O)
        case .p: return UInt16(kVK_ANSI_P)
        case .q: return UInt16(kVK_ANSI_Q)
        case .r: return UInt16(kVK_ANSI_R)
        case .s: return UInt16(kVK_ANSI_S)
        case .t: return UInt16(kVK_ANSI_T)
        case .u: return UInt16(kVK_ANSI_U)
        case .v: return UInt16(kVK_ANSI_V)
        case .w: return UInt16(kVK_ANSI_W)
        case .x: return UInt16(kVK_ANSI_X)
        case .y: return UInt16(kVK_ANSI_Y)
        case .z: return UInt16(kVK_ANSI_Z)
        case .zero: return UInt16(kVK_ANSI_0)
        case .one: return UInt16(kVK_ANSI_1)
        case .two: return UInt16(kVK_ANSI_2)
        case .three: return UInt16(kVK_ANSI_3)
        case .four: return UInt16(kVK_ANSI_4)
        case .five: return UInt16(kVK_ANSI_5)
        case .six: return UInt16(kVK_ANSI_6)
        case .seven: return UInt16(kVK_ANSI_7)
        case .eight: return UInt16(kVK_ANSI_8)
        case .nine: return UInt16(kVK_ANSI_9)
        }
    }

    init?(keyCode: UInt16) {
        guard let match = Self.allCases.first(where: { $0.keyCode == keyCode }) else {
            return nil
        }
        self = match
    }
}

struct HotkeyBinding: Equatable, Sendable {
    var key: HotkeyKey
    var useOption: Bool
    var useCommand: Bool
    var useControl: Bool
    var useShift: Bool

    static let `default` = HotkeyBinding(
        key: .space,
        useOption: true,
        useCommand: false,
        useControl: false,
        useShift: false
    )

    static let relevantModifiers: CGEventFlags = [.maskAlternate, .maskCommand, .maskControl, .maskShift]

    var displayText: String {
        let parts = modifierSymbols + [key.displayName]
        return parts.joined(separator: " ")
    }

    var compactDisplayText: String {
        modifierSymbols.joined() + key.displayName
    }

    var eventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if useOption { flags.insert(.maskAlternate) }
        if useCommand { flags.insert(.maskCommand) }
        if useControl { flags.insert(.maskControl) }
        if useShift { flags.insert(.maskShift) }
        return flags
    }

    var hasAnyModifier: Bool {
        useOption || useCommand || useControl || useShift
    }

    func matches(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard keyCode == key.keyCode else { return false }
        let normalizedFlags = flags.intersection(Self.relevantModifiers)
        return normalizedFlags == eventFlags
    }

    static func from(event: NSEvent) -> HotkeyBinding? {
        guard let key = HotkeyKey(keyCode: UInt16(event.keyCode)) else {
            return nil
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return HotkeyBinding(
            key: key,
            useOption: flags.contains(.option),
            useCommand: flags.contains(.command),
            useControl: flags.contains(.control),
            useShift: flags.contains(.shift)
        )
    }

    private var modifierSymbols: [String] {
        var symbols: [String] = []
        if useControl { symbols.append("⌃") }
        if useOption { symbols.append("⌥") }
        if useShift { symbols.append("⇧") }
        if useCommand { symbols.append("⌘") }
        return symbols
    }
}
