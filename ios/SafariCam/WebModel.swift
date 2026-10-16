import WebKit
import SwiftUI
import UniformTypeIdentifiers

final class WebModel: NSObject, ObservableObject {
    let webView: WKWebView
    @Published var address = ""
    @Published var canGoBack = false
    @Published var hasPDF = false

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        hasPDF = savedPDF.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        if let last = UserDefaults.standard.string(forKey: "lastURL"), let u = URL(string: last) {
            webView.load(URLRequest(url: u))
        } else if hasPDF, let pdf = savedPDF {
            loadPDF(pdf)
        }
    }

    /// 検索語ならGoogle検索、URLっぽければそのまま開く
    func go(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let urlStr: String
        if t.hasPrefix("http://") || t.hasPrefix("https://") {
            urlStr = t
        } else if !t.contains(" ") && t.contains(".") {
            urlStr = "https://" + t
        } else {
            let q = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t
            urlStr = "https://www.google.com/search?q=" + q
        }
        if let u = URL(string: urlStr) { webView.load(URLRequest(url: u)) }
    }

    func openMap() { go("https://www.google.com/maps") }

    var savedPDF: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("manual.pdf")
    }

    func importPDF(_ picked: URL) {
        guard let dest = savedPDF else { return }
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: picked, to: dest)
            hasPDF = true
            loadPDF(dest)
        } catch { }
    }

    func openSavedPDF() { if hasPDF, let p = savedPDF { loadPDF(p) } }

    private func loadPDF(_ url: URL) {
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        UserDefaults.standard.removeObject(forKey: "lastURL")
    }
}

extension WebModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        canGoBack = webView.canGoBack
        if let u = webView.url, !u.isFileURL {
            address = u.absoluteString
            UserDefaults.standard.set(u.absoluteString, forKey: "lastURL")
        } else {
            address = ""
        }
    }
}

struct WebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let p = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: false)
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick) }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(_ f: @escaping (URL) -> Void) { onPick = f }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let u = urls.first { onPick(u) }
        }
    }
}
