import Foundation

final class FileDenSettings: ObservableObject {
    static let shared = FileDenSettings()

    @Published var autoZipOnShare: Bool {
        didSet { UserDefaults.standard.set(autoZipOnShare, forKey: "autoZipOnShare") }
    }

    // -1 means no shortcut set
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

    var hasShortcut: Bool { shortcutKeyCode >= 0 }

    private init() {
        autoZipOnShare = UserDefaults.standard.bool(forKey: "autoZipOnShare")
        let storedCode = UserDefaults.standard.object(forKey: "shortcutKeyCode")
        shortcutKeyCode = storedCode != nil ? UserDefaults.standard.integer(forKey: "shortcutKeyCode") : -1
        shortcutModifiers = UserDefaults.standard.integer(forKey: "shortcutModifiers")
        hotkeyActivationEnabled = UserDefaults.standard.bool(forKey: "hotkeyActivationEnabled")
        shakeActivationEnabled = UserDefaults.standard.bool(forKey: "shakeActivationEnabled")
        notchActivationEnabled = UserDefaults.standard.bool(forKey: "notchActivationEnabled")
    }
}
