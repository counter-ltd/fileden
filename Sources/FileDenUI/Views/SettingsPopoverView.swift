import SwiftUI
import AppKit
import FileDenCore
import FileDenAI

struct SettingsPopoverView: View {
    @ObservedObject private var settings = FileDenSettings.shared
    @State private var selectedTab = SettingsTab.settings
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var fullDiskAccessGranted = SettingsPopoverView.checkFullDiskAccess()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 12)

            tabContent
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            accessibilityGranted = AXIsProcessTrusted()
            fullDiskAccessGranted = Self.checkFullDiskAccess()
        }
        .animation(.easeInOut(duration: 0.15), value: settings.hotkeyActivationEnabled)
        .animation(.easeInOut(duration: 0.15), value: settings.shakeActivationEnabled)
    }

    private var tabContent: some View {
        switch selectedTab {
        case .settings:
            return AnyView(settingsTab)
        case .intelligence:
            return AnyView(intelligenceTab)
        case .permissions:
            return AnyView(permissionsTab)
        case .about:
            return AnyView(aboutTab)
        }
    }

    private var settingsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingRow(
                title: "Auto-ZIP when sharing folders",
                subtitle: "Skip the share format prompt — always zip.",
                isOn: $settings.autoZipOnShare
            )

            Divider()

            activationSection
        }
    }

    // MARK: - Intelligence tab

    private var intelligenceTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingRow(
                title: "Enable Ask (offline AI)",
                subtitle: "Search and ask questions about your documents — fully offline, on this Mac.",
                isOn: $settings.aiEnabled
            )

            if settings.aiEnabled {
                Divider()

                settingRow(
                    title: "Written answers",
                    subtitle: "Summarize and answer in prose. Off shows the source passages only.",
                    isOn: $settings.aiSynthesisEnabled
                )

                intelligenceStatus

                Divider()

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Search index")
                            .font(.system(size: 13))
                        Text("Cached text and embeddings for indexed files.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear", action: clearIndex)
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: settings.aiEnabled)
    }

    @ViewBuilder private var intelligenceStatus: some View {
        let status = llmStatus
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: status.ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(status.ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(status.ok ? "On-device model ready" : "Written answers unavailable")
                    .font(.system(size: 12, weight: .semibold))
                Text(status.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !status.ok {
                    Button("Open System Settings", action: openIntelligenceSettings)
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
            }
            Spacer()
        }
    }

    private var llmStatus: (ok: Bool, detail: String) {
        if #available(macOS 26, *) {
            if FoundationModelsAnswerProvider.isAvailable {
                return (true, "Answers are written on-device with Apple Intelligence. Retrieval and citations work regardless.")
            }
            return (false, FoundationModelsAnswerProvider.unavailabilityReason
                    ?? "The on-device model is unavailable. Ask still finds and cites source passages.")
        }
        return (false, "Written answers need macOS 26 with Apple Intelligence. Ask still finds and cites source passages.")
    }

    private func openIntelligenceSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.AppleIntelligence-Settings.extension")
            ?? URL(string: "x-apple.systempreferences:")!
        NSWorkspace.shared.open(url)
    }

    private func clearIndex() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: Paths.indices, includingPropertiesForKeys: nil) else { return }
        for item in items { try? fm.removeItem(at: item) }
    }

    private var permissionsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            permissionSection(
                title: "Accessibility",
                systemImage: "lock.shield",
                description: "Hotkey and shake activation require Accessibility access to work globally.",
                statusIcon: accessibilityGranted ? "checkmark.seal.fill" : "xmark.seal.fill",
                statusText: accessibilityGranted ? "Granted" : "Not granted",
                statusColor: accessibilityGranted ? .green : .red,
                actionTitle: "Grant Access",
                action: grantAccessibilityAccess
            )

            Divider()

            permissionSection(
                title: "Full Disk Access",
                systemImage: "externaldrive.badge.person.crop",
                description: "If you want FileDen to access protected folders when sharing, enable Full Disk Access for FileDen.",
                statusIcon: fullDiskAccessGranted ? "checkmark.seal.fill" : "xmark.seal.fill",
                statusText: fullDiskAccessGranted ? "Granted" : "Not granted",
                statusColor: fullDiskAccessGranted ? .green : .red,
                actionTitle: fullDiskAccessGranted ? nil : "Grant Access",
                action: fullDiskAccessGranted ? nil : grantFullDiskAccess
            )

            Divider()

            Text("If the status does not update, open System Settings → Privacy & Security and enable FileDen for the relevant section.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionSection(
        title: String,
        systemImage: String,
        description: String,
        statusIcon: String,
        statusText: String,
        statusColor: Color,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)

            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: 8) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                Text(statusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(statusColor)
                Spacer()
                if let title = actionTitle, let action = action {
                    Button(title, action: action)
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
            }
        }
    }

    private func grantFullDiskAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            fullDiskAccessGranted = Self.checkFullDiskAccess()
        }
    }

    static func checkFullDiskAccess() -> Bool {
        let candidates = [
            "~/Library/Safari/Bookmarks.plist",
            "~/Library/Safari/CloudTabs.db",
            "~/Library/Mail/V10/MailData/Accounts.plist",
            "/Library/Application Support/com.apple.TCC/TCC.db"
        ]
        for c in candidates {
            let path = (c as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: path)
            if let handle = try? FileHandle(forReadingFrom: url) {
                try? handle.close()
                return true
            }
        }
        return false
    }

    private func grantAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            accessibilityGranted = AXIsProcessTrusted()
            if accessibilityGranted {
                GlobalShortcutManager.shared.updateMonitor()
                ShakeDetector.shared.updateMonitor()
            }
        }
    }

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "FileDen")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Divider()

            Text("FileDen makes folder sharing faster and more convenient by zipping folders automatically and letting you open a new Den with a hotkey or mouse shake.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Activation section

    private var activationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Den Activation")
                        .font(.system(size: 13))
                    Text("How to open a new Den.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                activationMenu
            }

            if settings.hotkeyActivationEnabled {
                hotkeyRow
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var activationMenu: some View {
        Menu {
            Toggle(isOn: $settings.hotkeyActivationEnabled) {
                Label("Hotkey", systemImage: "keyboard")
            }
            Toggle(isOn: $settings.shakeActivationEnabled) {
                Label("Mouse Shake", systemImage: "arrow.left.and.right")
            }
            Toggle(isOn: $settings.notchActivationEnabled) {
                Label("Notch Drop", systemImage: "rectangle.topthird.inset.filled")
            }
        } label: {
            HStack(spacing: 3) {
                Text(activationSummary)
                    .font(.system(size: 12))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var activationSummary: String {
        let parts = [
            settings.hotkeyActivationEnabled ? "Hotkey" : nil,
            settings.shakeActivationEnabled  ? "Shake"  : nil,
            settings.notchActivationEnabled  ? "Notch"  : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? "None" : parts.joined(separator: ", ")
    }

    // MARK: - Hotkey row

    private var hotkeyRow: some View {
        HStack {
            Text("Shortcut")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            ShortcutRecorderView()
                .frame(width: 96, height: 22)
        }
    }

    // MARK: - Toggle row

    private func settingRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case settings
        case intelligence
        case permissions
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .settings: return "Settings"
            case .intelligence: return "AI"
            case .permissions: return "Permissions"
            case .about: return "About"
            }
        }
    }
}
