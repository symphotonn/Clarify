import Foundation

@Observable
final class SettingsManager {
    private enum Keys {
        static let apiKey = "apiKey"
        static let modelName = "modelName"
        static let hotkeyKey = "hotkeyKey"
        static let hotkeyUseOption = "hotkeyUseOption"
        static let hotkeyUseCommand = "hotkeyUseCommand"
        static let hotkeyUseControl = "hotkeyUseControl"
        static let hotkeyUseShift = "hotkeyUseShift"
    }

    private let defaults: UserDefaults
    var onHotkeyChanged: ((HotkeyBinding) -> Void)?
    private var isBulkUpdatingHotkey = false
    private var isInitializing = true
    private(set) var isAPIKeyFromEnvironment: Bool
    private(set) var isModelFromEnvironment: Bool
    private(set) var lastSavedAt: Date?
    private(set) var lastSavedMessage: String = "Not saved yet"

    var apiKey: String {
        didSet {
            defaults.set(apiKey, forKey: Keys.apiKey)
            if !isInitializing {
                isAPIKeyFromEnvironment = false
                markSaved("API key saved")
            }
        }
    }

    var modelName: String {
        didSet {
            defaults.set(modelName, forKey: Keys.modelName)
            if !isInitializing {
                isModelFromEnvironment = false
                markSaved("Model saved")
            }
        }
    }

    var hotkeyKey: HotkeyKey {
        didSet {
            persistHotkeyChangeIfNeeded()
        }
    }

    var hotkeyUseOption: Bool {
        didSet {
            persistHotkeyChangeIfNeeded()
        }
    }

    var hotkeyUseCommand: Bool {
        didSet {
            persistHotkeyChangeIfNeeded()
        }
    }

    var hotkeyUseControl: Bool {
        didSet {
            persistHotkeyChangeIfNeeded()
        }
    }

    var hotkeyUseShift: Bool {
        didSet {
            persistHotkeyChangeIfNeeded()
        }
    }

    var hotkeyBinding: HotkeyBinding {
        HotkeyBinding(
            key: hotkeyKey,
            useOption: hotkeyUseOption,
            useCommand: hotkeyUseCommand,
            useControl: hotkeyUseControl,
            useShift: hotkeyUseShift
        )
    }

    func updateHotkeyBinding(_ binding: HotkeyBinding) {
        isBulkUpdatingHotkey = true
        hotkeyKey = binding.key
        hotkeyUseOption = binding.useOption
        hotkeyUseCommand = binding.useCommand
        hotkeyUseControl = binding.useControl
        hotkeyUseShift = binding.useShift
        isBulkUpdatingHotkey = false
        persistHotkeyChangeIfNeeded()
    }

    init(defaults: UserDefaults? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) {
        let resolvedDefaults = Self.resolveDefaults(custom: defaults)
        self.defaults = resolvedDefaults

        if defaults == nil, !Self.isRunningUnitTests {
            Self.clearLikelyTestPollution(in: resolvedDefaults)
        }

        self.isAPIKeyFromEnvironment = false
        self.isModelFromEnvironment = false

        let storedAPIKey = resolvedDefaults.string(forKey: Keys.apiKey)?.trimmed() ?? ""
        let envAPIKey = environment[Constants.devAPIKeyEnvVar]?.trimmed() ?? ""
        // Prefer explicitly saved Settings value; use environment key as fallback.
        if !storedAPIKey.isEmpty {
            self.apiKey = storedAPIKey
        } else if !envAPIKey.isEmpty {
            self.isAPIKeyFromEnvironment = true
            self.apiKey = envAPIKey
        } else {
            self.apiKey = ""
        }

        let storedModel = resolvedDefaults.string(forKey: Keys.modelName)?.trimmed() ?? ""
        let envModel = environment[Constants.devModelEnvVar]?.trimmed() ?? ""
        // Same precedence for model: user-saved setting first.
        if !storedModel.isEmpty {
            self.modelName = storedModel
        } else if !envModel.isEmpty {
            self.isModelFromEnvironment = true
            self.modelName = envModel
        } else {
            self.modelName = Constants.defaultModel
        }

        if let keyRaw = resolvedDefaults.string(forKey: Keys.hotkeyKey),
           let key = HotkeyKey(rawValue: keyRaw) {
            self.hotkeyKey = key
        } else {
            self.hotkeyKey = HotkeyBinding.default.key
        }

        self.hotkeyUseOption = resolvedDefaults.object(forKey: Keys.hotkeyUseOption) as? Bool ?? HotkeyBinding.default.useOption
        self.hotkeyUseCommand = resolvedDefaults.object(forKey: Keys.hotkeyUseCommand) as? Bool ?? HotkeyBinding.default.useCommand
        self.hotkeyUseControl = resolvedDefaults.object(forKey: Keys.hotkeyUseControl) as? Bool ?? HotkeyBinding.default.useControl
        self.hotkeyUseShift = resolvedDefaults.object(forKey: Keys.hotkeyUseShift) as? Bool ?? HotkeyBinding.default.useShift

        isInitializing = false
    }

    private func persistHotkeyChangeIfNeeded() {
        guard !isBulkUpdatingHotkey else { return }
        defaults.set(hotkeyKey.rawValue, forKey: Keys.hotkeyKey)
        defaults.set(hotkeyUseOption, forKey: Keys.hotkeyUseOption)
        defaults.set(hotkeyUseCommand, forKey: Keys.hotkeyUseCommand)
        defaults.set(hotkeyUseControl, forKey: Keys.hotkeyUseControl)
        defaults.set(hotkeyUseShift, forKey: Keys.hotkeyUseShift)
        markSaved("Hotkey saved")
        onHotkeyChanged?(hotkeyBinding)
    }

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static func resolveDefaults(custom: UserDefaults?) -> UserDefaults {
        if let custom {
            return custom
        }

        guard isRunningUnitTests else {
            return .standard
        }

        let suiteName = "Clarify.Tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName) ?? .standard
    }

    private static func clearLikelyTestPollution(in defaults: UserDefaults) {
        let storedAPIKey = defaults.string(forKey: Keys.apiKey)?.trimmed() ?? ""
        let storedModel = defaults.string(forKey: Keys.modelName)?.trimmed() ?? ""

        if storedAPIKey == "test-key" {
            defaults.removeObject(forKey: Keys.apiKey)
        }

        if storedModel == "test-model" {
            defaults.removeObject(forKey: Keys.modelName)
        }
    }

    private func markSaved(_ message: String) {
        lastSavedAt = Date()
        lastSavedMessage = message
    }
}

private extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
