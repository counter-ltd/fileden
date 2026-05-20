import SwiftUI
import AppKit

struct ShareButtonView: NSViewRepresentable {
    var title: String? = nil
    let onTap: (NSView) -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.target = context.coordinator
        button.action = #selector(Coordinator.tapped(_:))
        if let title {
            button.title = title
            button.bezelStyle = .inline
            button.contentTintColor = .secondaryLabelColor
            button.font = .systemFont(ofSize: 12, weight: .medium)
        } else {
            button.bezelStyle = .circular
            button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share")
            button.imageScaling = .scaleProportionallyDown
            button.contentTintColor = .secondaryLabelColor
        }
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        if let title, nsView.title != title {
            nsView.title = title
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    class Coordinator: NSObject {
        let onTap: (NSView) -> Void
        init(onTap: @escaping (NSView) -> Void) { self.onTap = onTap }

        @objc func tapped(_ sender: NSButton) { onTap(sender) }
    }
}
