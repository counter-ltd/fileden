import Foundation
import AppKit

public struct ShelfItem: Identifiable, Sendable {
    public let id: UUID
    public let url: URL

    public init(url: URL) {
        self.id = UUID()
        self.url = url
    }

    public var name: String { url.lastPathComponent }

    @MainActor
    public var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}
