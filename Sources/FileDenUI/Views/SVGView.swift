import SwiftUI
import WebKit

/// Renders a self-contained SVG string inline using WKWebView.
struct SVGView: NSViewRepresentable {
    let svg: String

    func makeNSView(context: Context) -> WKWebView {
        let wv = WKWebView()
        wv.setValue(false, forKey: "drawsBackground")
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        let html = """
        <!DOCTYPE html><html><head>
        <style>*{margin:0;padding:0}html,body{width:100%;height:100%;background:transparent;overflow:hidden}svg{width:100%;height:100%;display:block}</style>
        </head><body>\(svg)</body></html>
        """
        wv.loadHTMLString(html, baseURL: nil)
    }
}
