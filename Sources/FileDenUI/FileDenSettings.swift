import Foundation

/// User-tunable settings, persisted to `UserDefaults` and observed by SwiftUI.
///
/// Each property writes through to `UserDefaults` on `didSet`, so flipping a
/// setting from anywhere (the popover, code, defaults write) takes effect
/// immediately for every observer.
final class FileDenSettings: ObservableObject {
    static let shared = FileDenSettings()

    /// When true, sharing a folder skips the format prompt and always zips.
    @Published var autoZipOnShare: Bool {
        didSet { UserDefaults.standard.set(autoZipOnShare, forKey: "autoZipOnShare") }
    }

    /// macOS virtual keycode for the global new-den hotkey. `-1` = unset.
    @Published var shortcutKeyCode: Int {
        didSet { UserDefaults.standard.set(shortcutKeyCode, forKey: "shortcutKeyCode") }
    }

    @Published var shortcutModifiers: Int {
        didSet { UserDefaults.standard.set(shortcutModifiers, forKey: "shortcutModifiers") }
    }

    @Published var hotkeyActivationEnabled: Bool {
        didSet { UserDefaults.standard.set(hotkeyActivationEnabled, forKey: "hotkeyActivationEnabled") }
    }

    @Published var shakeActivationEnabled: Bool {
        didSet { UserDefaults.standard.set(shakeActivationEnabled, forKey: "shakeActivationEnabled") }
    }

    @Published var notchActivationEnabled: Bool {
        didSet { UserDefaults.standard.set(notchActivationEnabled, forKey: "notchActivationEnabled") }
    }

    /// Master switch for the offline Ask feature. When false, all Ask/Notebook
    /// affordances are hidden and nothing is indexed.
    @Published var aiEnabled: Bool {
        didSet { UserDefaults.standard.set(aiEnabled, forKey: "aiEnabled") }
    }

    /// When true (and the on-device LLM is available), Ask writes a grounded
    /// answer over the retrieved passages; when false, it shows passages only.
    @Published var aiSynthesisEnabled: Bool {
        didSet { UserDefaults.standard.set(aiSynthesisEnabled, forKey: "aiSynthesisEnabled") }
    }

    var hasShortcut: Bool { shortcutKeyCode >= 0 }

    private init() {
        autoZipOnShare = UserDefaults.standard.bool(forKey: "autoZipOnShare")
        let storedCode = UserDefaults.standard.object(forKey: "shortcutKeyCode")
        shortcutKeyCode = storedCode != nil ? UserDefaults.standard.integer(forKey: "shortcutKeyCode") : -1
        shortcutModifiers = UserDefaults.standard.integer(forKey: "shortcutModifiers")
        hotkeyActivationEnabled = UserDefaults.standard.bool(forKey: "hotkeyActivationEnabled")
        shakeActivationEnabled = UserDefaults.standard.bool(forKey: "shakeActivationEnabled")
        notchActivationEnabled = UserDefaults.standard.bool(forKey: "notchActivationEnabled")
        // Both default on: the feature is available out of the box.
        aiEnabled = UserDefaults.standard.object(forKey: "aiEnabled") as? Bool ?? true
        aiSynthesisEnabled = UserDefaults.standard.object(forKey: "aiSynthesisEnabled") as? Bool ?? true
    }
}
