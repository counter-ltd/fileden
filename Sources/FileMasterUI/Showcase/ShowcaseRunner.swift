// Reel showcase — compiled only in `--showcase` builds (FILEMASTER_SHOWCASE).
// See Makefile: `make showcase`. Never included in production builds.
//
// The fully-automated path: launch FileMaster with `--showcase` and it records
// one full 9:16 cycle of the reel to ~/Desktop with zero further input, then
// reveals the MP4 in Finder and quits. No menu bar, no dens, no clicking —
// `make showcase` is the whole workflow.

#if FILEMASTER_SHOWCASE

import AppKit
import CoreGraphics
import SwiftUI

@MainActor
public enum ShowcaseRunner {
    /// True when this process was launched to record a reel. AppDelegate
    /// checks this before standing up the menu bar / den services.
    public static var isActive: Bool {
        CommandLine.arguments.contains("--showcase")
            || CommandLine.arguments.contains("--showcase-wide")
    }

    /// `--showcase-wide` records the 16:9 long-form feature tour instead of the
    /// 9:16 reel.
    private static var isWide: Bool {
        CommandLine.arguments.contains("--showcase-wide")
    }

    // Held for the process lifetime so neither is deallocated mid-recording.
    private static var control: AnyObject?
    private static var recorder: ReelRecorder?

    /// Kick off the automated recording. Call once from
    /// `applicationDidFinishLaunching` when `isActive` is true.
    public static func runAutomated() {
        // SCStream needs the Screen Recording TCC grant. Preflight first: if we
        // don't have it, trigger the system prompt and bail with a clear note —
        // the grant only takes effect on the next launch.
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            print("""

            ┌──────────────────────────────────────────────────────────────┐
            │  FileMaster needs Screen Recording permission to capture the   │
            │  showcase reel.                                                │
            │                                                                │
            │  System Settings ▸ Privacy & Security ▸ Screen Recording       │
            │  → enable FileMaster, then run `make showcase` again.          │
            └──────────────────────────────────────────────────────────────┘

            """)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
            return
        }

        let rec: ReelRecorder
        if isWide {
            print("● Recording FileMaster showcase (16:9, ~61 s)… the MP4 will open on your Desktop when done.")
            let d = WideDirector()
            control = d
            rec = ReelRecorder(
                control: d,
                designSize: CGSize(width: 640, height: 360),
                outputSize: CGSize(width: 1920, height: 1080),
                fps: 30,
                rootView: { [d] in AnyView(WideSceneViewBound(director: d)) }
            )
        } else {
            print("● Recording FileMaster reel (9:16, ~16 s)… the MP4 will open on your Desktop when done.")
            let d = ReelDirector()
            control = d
            rec = ReelRecorder(
                control: d,
                designSize: CGSize(width: 360, height: 640),
                outputSize: CGSize(width: 1080, height: 1920),
                rootView: { [d] in AnyView(ReelSceneViewBound(director: d)) }
            )
        }
        recorder = rec
        rec.onFinished = { url in
            if let url {
                print("✓ Saved \(url.path)")
            } else {
                print("✗ Recording failed — see Console for SCStream errors.")
            }
            // Let the Finder reveal settle before we exit.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NSApp.terminate(nil)
            }
        }
        Task { await rec.start() }
    }
}

#endif
