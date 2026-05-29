// Reel showcase — compiled only in `--showcase` builds (FILEMASTER_SHOWCASE).
// See Makefile: `make showcase`. Never included in production builds.
//
// Captures the hidden 1080×1920 window via SCStream and writes an H.264/AAC
// MP4 to the Desktop. Ported from Clonk's reel recorder — every comment here
// encodes a bug we already paid for once (see private-resources/SHOWCASE.md).
//
// NOT @MainActor — see ReelScene.swift header for the macOS 26.5 rationale.
// AVAssetWriter access is serialized via a lock; NSWindow ops use
// `await MainActor.run` (the async executor path, not the broken sync check).

#if FILEMASTER_SHOWCASE

import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI

/// Minimal surface the recorder needs from a timeline driver, so it can record
/// either the portrait reel (`ReelDirector`) or the wide showcase (`WideDirector`).
protocol ReelControl: AnyObject {
    var cycleLength: Double { get }
    func start()
    func stop()
}

final class ReelRecorder: @unchecked Sendable {
    private let control: any ReelControl
    private let designSize: CGSize               // SwiftUI layout size (points)
    private let outputSize: CGSize               // captured pixel size
    private let fps: Int                         // capture / encode frame rate
    private let makeRootView: @MainActor () -> AnyView
    private let lock = NSLock()                  // guards writer / inputs
    private var captureWindow: NSWindow?
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private let sink = StreamSink()
    private var autoStopTask: Task<Void, Never>?
    private let sinkQueue = DispatchQueue(label: "ltd.anti.filemaster.reel.sink", qos: .userInitiated)
    private var sessionStarted = false   // protected by lock

    /// Called on the main actor once the MP4 is finalized and revealed in
    /// Finder. The automated runner uses it to quit; the manual UI ignores it.
    var onFinished: (@MainActor (URL?) -> Void)?

    /// - Parameters:
    ///   - control:   the timeline driver to start once capture is stable.
    ///   - designSize: the SwiftUI scene's natural layout size (e.g. 360×640).
    ///   - outputSize: the recorded video size (e.g. 1080×1920 or 1920×1080).
    ///   - rootView:  builds the scene view to host (captures its own director).
    init(control: any ReelControl,
         designSize: CGSize,
         outputSize: CGSize,
         fps: Int = 60,
         rootView: @escaping @MainActor () -> AnyView) {
        self.control = control
        self.designSize = designSize
        self.outputSize = outputSize
        self.fps = fps
        self.makeRootView = rootView
    }

    func start() async {
        // 1. NSWindow must be created on main thread. Capture both the window
        //    and its windowNumber inside MainActor.run (windowNumber is
        //    main-actor isolated).
        let (win, windowNumber) = await MainActor.run { () -> (NSWindow, Int) in
            let w = self.makeCaptureWindow()
            return (w, w.windowNumber)
        }
        captureWindow = win

        // 2. Locate the matching SCWindow by ID (titles are unreliable for
        //    borderless windows).
        guard let content = try? await SCShareableContent.current,
              let scWin = content.windows.first(where: { $0.windowID == windowNumber })
        else {
            await MainActor.run { win.close() }
            await MainActor.run { self.onFinished?(nil) }
            return
        }

        // 3. Output URL on Desktop.
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Desktop/FileMaster-Reel-\(fmt.string(from: .now)).mp4")

        // 4. AVAssetWriter setup. 15 Mbps is plenty for 1080p and leaves the
        //    encoder headroom under capture load.
        guard let assetWriter = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            await MainActor.run { win.close() }
            await MainActor.run { self.onFinished?(nil) }
            return
        }
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width), AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 15_000_000,
                AVVideoMaxKeyFrameIntervalKey: fps,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: fps,
            ],
        ]
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 192_000,
        ]
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vIn.expectsMediaDataInRealTime = true
        let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        aIn.expectsMediaDataInRealTime = true
        assetWriter.add(vIn); assetWriter.add(aIn)

        installWriter(assetWriter, video: vIn, audio: aIn)

        // 5. SCStream — sink runs on our dedicated queue and calls append()
        //    directly, no Swift Concurrency hop.
        let filter = SCContentFilter(desktopIndependentWindow: scWin)
        let config = SCStreamConfiguration()
        config.width = Int(outputSize.width); config.height = Int(outputSize.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.scalesToFit = true
        config.showsCursor = false
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = false
        config.sampleRate = 44_100
        config.channelCount = 2

        sink.onSample = { [weak self] buf in
            self?.append(buf)
        }
        let st = SCStream(filter: filter, configuration: config, delegate: nil)
        try? st.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sinkQueue)
        try? st.addStreamOutput(sink, type: .audio,  sampleHandlerQueue: sinkQueue)
        assetWriter.startWriting()
        // Bring capture up FIRST so the SCStream pipeline is emitting frames
        // before the director's t=0 events fire — otherwise the opening
        // typewriter beat gets eaten by the ~0.3–0.8 s SCStream warm-up.
        try? await st.startCapture()
        stream = st
        // Let the capture pipeline fully stabilise before the timeline begins.
        // The first ~1 s of frames after startCapture() is warm-up; starting the
        // director immediately means that warm-up eats the intro — including the
        // file-drop animation — so the recording opens with files already
        // stacked. Holding here guarantees the whole timeline lands on tape.
        try? await Task.sleep(for: .seconds(1.3))
        await MainActor.run { self.control.start() }

        // 6. Auto-stop after one full cycle + 1.0 s buffer so the bumper's
        //    final frames and audio fade are guaranteed to land in the MP4.
        let duration = control.cycleLength + 1.0
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            await self?.stop()
        }
    }

    func stop() async {
        autoStopTask?.cancel(); autoStopTask = nil
        if let st = stream { try? await st.stopCapture() }
        stream = nil

        // stopCapture() returns before all queued sinkQueue blocks execute.
        // Drain them before marking inputs finished, or the tail frames drop.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sinkQueue.async { cont.resume() }
        }

        let w = finalizeWriter()
        var outputURL: URL?
        if let w {
            await w.finishWriting()
            outputURL = w.outputURL
            NSWorkspace.shared.activateFileViewerSelecting([w.outputURL])
        }

        if let win = captureWindow {
            await MainActor.run { win.close() }
            captureWindow = nil
        }

        let finalURL = outputURL
        await MainActor.run { self.onFinished?(finalURL) }
    }

    // NSLock can't be touched directly from async contexts in Swift 6, so both
    // writer mutations go through these sync helpers.
    private func installWriter(_ w: AVAssetWriter, video: AVAssetWriterInput, audio: AVAssetWriterInput) {
        lock.lock()
        defer { lock.unlock() }
        writer = w; videoInput = video; audioInput = audio
        sessionStarted = false
    }

    private func finalizeWriter() -> AVAssetWriter? {
        lock.lock()
        defer { lock.unlock() }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        let w = writer
        writer = nil; videoInput = nil; audioInput = nil
        return w
    }

    // Fire-and-forget cancel from the UI button.
    func stopSync() {
        Task { await self.stop() }
    }

    private func append(_ buf: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let writer, CMSampleBufferDataIsReady(buf) else { return }

        let isAudio = CMSampleBufferGetFormatDescription(buf).map {
            CMFormatDescriptionGetMediaType($0) == kCMMediaType_Audio
        } ?? false

        guard writer.status == .writing else { return }

        // Seed the session with the FIRST sample's PTS, never .zero — otherwise
        // the MP4 gets a multi-second leading gap or fails to encode.
        if !sessionStarted {
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(buf))
            sessionStarted = true
        }

        if isAudio {
            if audioInput?.isReadyForMoreMediaData == true { audioInput?.append(buf) }
        } else {
            guard CMSampleBufferGetImageBuffer(buf) != nil else { return }
            if videoInput?.isReadyForMoreMediaData == true { videoInput?.append(buf) }
        }
    }

    // The hidden capture NSWindow that hosts the bound scene. Parked at
    // x=50_000 — fully off any display so it never flashes, but
    // orderFrontRegardless() keeps CoreAnimation compositing its layer tree so
    // SCStream can still capture it. The scene lays out at `designSize`, then a
    // uniform scale blows it up to the recorded `outputSize`.
    @MainActor
    private func makeCaptureWindow() -> NSWindow {
        let win = NSWindow(
            contentRect: NSRect(x: 50_000, y: 0, width: outputSize.width, height: outputSize.height),
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        win.collectionBehavior = [.stationary, .ignoresCycle, .canJoinAllSpaces]
        win.ignoresMouseEvents = true
        win.isReleasedWhenClosed = false
        win.backgroundColor = .black

        let scale = outputSize.width / designSize.width
        let host = NSHostingView(
            rootView: makeRootView()
                .frame(width: designSize.width, height: designSize.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: outputSize.width, height: outputSize.height, alignment: .topLeading)
        )
        win.contentView = host
        win.orderFrontRegardless()
        return win
    }
}

// SCStream delivers samples on our `sinkQueue`. The shim just forwards to the
// recorder; the recorder takes a lock to serialize writer access.
private final class StreamSink: NSObject, SCStreamOutput, @unchecked Sendable {
    var onSample: ((CMSampleBuffer) -> Void)?
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        if type == .screen, CMSampleBufferGetImageBuffer(sampleBuffer) == nil { return }
        onSample?(sampleBuffer)
    }
}

#endif
