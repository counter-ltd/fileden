import SwiftUI
import AppKit
import FileDenUI

@main
struct FileDenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
