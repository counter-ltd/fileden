import XCTest
import AppKit
@testable import FileDenAI

final class ExtractorTests: XCTestCase {

    // MARK: - Vision OCR (on-device, no Apple Intelligence needed)

    func testOCRReadsRenderedText() throws {
        guard let image = renderText("Invoice 2026") else {
            throw XCTSkip("couldn't render test image")
        }
        guard let recognized = OCRTextExtractor.recognize(image) else {
            throw XCTSkip("Vision returned no text on this host")
        }
        let lower = recognized.lowercased()
        XCTAssertTrue(lower.contains("invoice") || lower.contains("2026"),
                      "OCR should read the rendered text, got: \(recognized)")
    }

    private func renderText(_ text: String) -> CGImage? {
        let size = NSSize(width: 640, height: 200)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        (text as NSString).draw(at: NSPoint(x: 24, y: 80),
                                withAttributes: [.font: NSFont.systemFont(ofSize: 56),
                                                 .foregroundColor: NSColor.black])
        image.unlockFocus()
        var rect = CGRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    // MARK: - DOCX (WordprocessingML → text)

    func testDocxStripWordML() {
        let xml = """
        <w:document><w:body>
        <w:p><w:r><w:t>First paragraph &amp; more.</w:t></w:r></w:p>
        <w:p><w:r><w:t>Second</w:t><w:tab/><w:t>tabbed.</w:t></w:r></w:p>
        </w:body></w:document>
        """
        let text = DocxTextExtractor.stripWordML(xml)
        XCTAssertTrue(text.contains("First paragraph & more."))
        XCTAssertTrue(text.contains("Second\ttabbed."))
        XCTAssertFalse(text.contains("<w:"), "no tags should survive")
    }

    // MARK: - RTF

    func testRTFPlainText() throws {
        let rtf = #"{\rtf1\ansi\ansicpg1252 Hello bold world.}"#
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FileDenAI-rtf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("sample.rtf")
        try rtf.data(using: .utf8)!.write(to: url)

        let text = try XCTUnwrap(RTFTextExtractor.plainText(url))
        XCTAssertEqual(text.trimmingCharacters(in: .whitespacesAndNewlines), "Hello bold world.")
    }

    // MARK: - Format coverage

    func testSupportedExtensionsGoBeyondPDF() {
        for ext in ["pdf", "md", "txt", "html", "rtf", "docx", "csv", "json", "swift", "py"] {
            XCTAssertTrue(TextExtractor.canExtract(URL(fileURLWithPath: "/tmp/x.\(ext)")),
                          ".\(ext) should be searchable")
        }
        XCTAssertFalse(TextExtractor.canExtract(URL(fileURLWithPath: "/tmp/x.png")))
    }
}
