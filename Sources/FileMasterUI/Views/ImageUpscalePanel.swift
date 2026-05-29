import SwiftUI
import AppKit

/// Interactive upscale controls shown in a popover off the actions menu.
///
/// Three aspect-preserving ways to specify the target: a **Factor** (2×, 4×…),
/// an exact **Width**, or fit the **Longest** side to a box. Pick the output
/// format (or keep the source) and, for lossy targets, a quality. The new pixel
/// size updates live — it's deterministic, so no re-encode is needed. Hands the
/// chosen ``ImageUpscale/Options`` back to the caller.
struct ImageUpscalePanel: View {
    let urls: [URL]
    let onUpscale: (ImageUpscale.Options) -> Void
    let onCancel: () -> Void

    private enum Axis: Hashable { case factor, width, longest }

    @State private var axis: Axis = .factor
    @State private var factor: Double = 2
    @State private var widthPx: Double = 2000
    @State private var longestPx: Double = 2000
    @State private var format: ImageConvert.Format? = nil   // nil = match source
    @State private var quality: Double = 0.92
    @State private var didInit = false

    /// Every still format this OS can write, for the format picker.
    private static let formats: [ImageConvert.Format] =
        ImageConvert.Format.allCases.filter { ImageConvert.canEncode($0) }

    private var first: URL { urls[0] }
    private var source: (pixels: CGSize, bytes: Int)? { ImageCompress.sourceInfo(first) }

    private var mode: ImageUpscale.Mode {
        switch axis {
        case .factor:  return .factor(factor)
        case .width:   return .width(Int(widthPx.rounded()))
        case .longest: return .longest(Int(longestPx.rounded()))
        }
    }

    private var options: ImageUpscale.Options {
        var o = ImageUpscale.Options()
        o.mode = mode
        o.format = format
        o.quality = quality
        return o
    }

    /// Whether the resolved output format honours the quality dial.
    private var lossy: Bool { ImageUpscale.outputFormat(for: first, override: format).isLossy }

    private var valueBinding: Binding<Double> {
        switch axis {
        case .factor:  return $factor
        case .width:   return $widthPx
        case .longest: return $longestPx
        }
    }

    private var unit: String { axis == .factor ? "×" : "px" }

    private var sliderRange: ClosedRange<Double> {
        if axis == .factor { return 1...8 }
        let dim = axis == .width ? (source?.pixels.width ?? 1000)
                                 : max(source?.pixels.width ?? 1000, source?.pixels.height ?? 1000)
        let base = max(dim, 16)
        return base...max(base * 4, base + 16)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Picker("", selection: $axis) {
                Text("Factor").tag(Axis.factor)
                Text("Width").tag(Axis.width)
                Text("Longest").tag(Axis.longest)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(axis == .factor ? "Scale" : "Target")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    TextField("", value: valueBinding, formatter: formatter)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                    Text(unit).font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(width: 18, alignment: .leading)
                }
                Slider(value: valueBinding, in: sliderRange)
            }

            HStack {
                Text("Format").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $format) {
                    Text("Match source").tag(ImageConvert.Format?.none)
                    ForEach(Self.formats, id: \.self) { f in
                        Text(f.label).tag(ImageConvert.Format?.some(f))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            if lossy {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Quality").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int((quality * 100).rounded()))%")
                            .font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
                    }
                    Slider(value: $quality, in: 0.05...1.0)
                }
            }

            Divider().opacity(0.5)
            resultRow

            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Upscale") { onUpscale(options) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear(perform: seedDefaults)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 10) {
            if let img = NSImage(contentsOf: first) {
                Image(nsImage: img)
                    .resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(urls.count == 1 ? first.lastPathComponent : "\(urls.count) images")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                if let s = source {
                    Text(dims(s.pixels)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Output readout

    @ViewBuilder
    private var resultRow: some View {
        HStack {
            Text("New size").font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            if let p = source?.pixels {
                let t = ImageUpscale.target(for: p, mode: mode)
                Text(dims(t))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.15), value: t.width)
                    .animation(.easeInOut(duration: 0.15), value: t.height)
            }
        }
    }

    // MARK: - Helpers

    /// Seed Width/Longest from the first image at 2× so the panel opens on a
    /// sensible enlargement regardless of which axis the user switches to.
    private func seedDefaults() {
        guard !didInit, let p = source?.pixels else { return }
        widthPx = Double(Int(p.width) * 2)
        longestPx = Double(Int(max(p.width, p.height)) * 2)
        didInit = true
    }

    private var formatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = axis == .factor ? 1 : 0
        f.minimum = axis == .factor ? 1 : 16
        return f
    }

    private func dims(_ s: CGSize) -> String { "\(Int(s.width))×\(Int(s.height))" }
}
