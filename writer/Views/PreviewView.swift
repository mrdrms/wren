import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

enum PreviewMode: String, CaseIterable, Identifiable {
    case off, split, full
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: "Write"
        case .split: "Side by Side"
        case .full: "Preview"
        }
    }
    var symbol: String {
        switch self {
        case .off: "doc.text"
        case .split: "rectangle.split.2x1"
        case .full: "eye"
        }
    }
}

/// The post as readers will see it, in the chosen blog style, updating as you type.
struct PreviewPane: View {
    @Environment(AppModel.self) private var model
    @AppStorage("previewPhone") private var phone = false

    var body: some View {
        let prefs = model.prefs
        ZStack(alignment: .bottom) {
            Group {
                if phone {
                    BlogPreview(markdown: model.text, title: model.currentTitle, folder: model.loadedURL?.deletingLastPathComponent(),
                                style: prefs.blogStyle, follow: model.previewMode == .split ? model.caretFraction : nil)
                        .frame(width: 390)
                        .clipShape(.rect(cornerRadius: 36))
                        .overlay(RoundedRectangle(cornerRadius: 36).strokeBorder(.primary.opacity(0.25), lineWidth: 6))
                        .shadow(color: .black.opacity(0.2), radius: 24, y: 10)
                        .padding(.top, 20)
                        .padding(.bottom, 80)
                        .frame(maxWidth: .infinity)
                        .background(.background.secondary)
                } else {
                    BlogPreview(markdown: model.text, title: model.currentTitle, folder: model.loadedURL?.deletingLastPathComponent(),
                                style: prefs.blogStyle, follow: model.previewMode == .split ? model.caretFraction : nil)
                }
            }

            HStack(spacing: 10) {
                // This isn't a second way to see formatting: it's the post as readers get it.
                Label("Reader preview", systemImage: "eye")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                if model.previewMode == .full {
                    Button { model.setPreview(.off) } label: {
                        Label("Write", systemImage: "pencil")
                    }
                    .buttonStyle(.glass)
                    .help("Back to writing (Esc)")
                }

                Picker("Style", selection: Bindable(prefs).blogStyle) {
                    ForEach(BlogStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .help(prefs.blogStyle.blurb + ". Exports use this style too.")

                Picker("Device", selection: $phone) {
                    Image(systemName: "desktopcomputer").tag(false).help("Desktop")
                    Image(systemName: "iphone").tag(true).help("Phone")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                if model.pomodoro.isActive {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        PomodoroChip()
                    }
                }

                Button { model.toggleZen() } label: {
                    Image(systemName: model.zen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.glass)
                .help(model.zen ? "Leave Zen (Esc)" : "Read it alone: hide everything else (⌘⇧↩)")

                Button {
                    model.export("blog")
                } label: {
                    Label("Export for Blog", systemImage: "shippingbox")
                }
                .buttonStyle(.glassProminent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .themedGlass(in: .capsule)
            .padding(.bottom, 18)
        }
        // Solid, edge to edge: the preview shows the published page, not the atmosphere.
        .background(prefs.blogStyle.pageBackground(dark: prefs.theme.isDark).ignoresSafeArea())
    }
}

struct BlogPreview: NSViewRepresentable {
    let markdown: String
    let title: String
    let folder: URL?
    let style: BlogStyle
    /// Where the caret sits (0…1); the preview keeps that part of the post in view.
    let follow: Double?

    static let scheme = "wren-asset"

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(context.coordinator.assets, forURLScheme: Self.scheme)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.assets.folder = folder
        coordinator.follow = follow
        // Rendering on every keystroke is cheap, but give fast typists a beat.
        coordinator.schedule(webView: webView, markdown: markdown, title: title, style: style)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let assets = AssetSchemeHandler()
        var follow: Double?
        private var loadedStyle: BlogStyle?
        private var isLoaded = false
        private var pendingBody: String?
        private var lastBody: String?
        private var renderTask: Task<Void, Never>?

        func schedule(webView: WKWebView, markdown: String, title: String, style: BlogStyle) {
            renderTask?.cancel()
            let immediate = loadedStyle != style
            renderTask = Task { [weak self, weak webView] in
                if !immediate { try? await Task.sleep(for: .milliseconds(150)) }
                guard !Task.isCancelled, let self, let webView else { return }
                self.render(webView: webView, markdown: markdown, title: title, style: style)
            }
        }

        private func render(webView: WKWebView, markdown: String, title: String, style: BlogStyle) {
            let body = Self.rewriteAssets(BlogRenderer.body(markdown: Ghost.clean(markdown)))
            if loadedStyle != style {
                loadedStyle = style
                isLoaded = false
                lastBody = body
                webView.loadHTMLString(MarkdownHTML.document(title: title, body: body, style: style) + Self.script,
                                       // An https origin keeps embeds such as YouTube happy; media is served via our scheme.
                                       baseURL: URL(string: "https://preview.wren.local/"))
                return
            }
            guard body != lastBody else { return }
            lastBody = body
            guard isLoaded else { pendingBody = body; return }
            push(body, to: webView)
        }

        private func push(_ body: String, to webView: WKWebView) {
            guard let json = try? JSONEncoder().encode([body]), let array = String(data: json, encoding: .utf8) else { return }
            let follow = self.follow.map { String(format: "%.4f", $0) } ?? "null"
            webView.evaluateJavaScript("wrenUpdate(\(array)[0], \(follow))")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            if let pending = pendingBody {
                pendingBody = nil
                push(pending, to: webView)
            }
        }

        /// Web and mail links open in your browser; the preview itself never navigates away.
        /// Other kinds of link (file:, app URL schemes) are ignored: they could open an app.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            let url = action.request.url
            if action.navigationType == .linkActivated {
                // In-page anchors (footnotes and their back-links) scroll the preview itself.
                if let url, url.host == "preview.wren.local", url.fragment != nil, url.path.isEmpty || url.path == "/" {
                    return decisionHandler(.allow)
                }
                if let url, Safety.isSafeLink(url) { NSWorkspace.shared.open(url) }
                decisionHandler(.cancel)
            } else if action.targetFrame?.isMainFrame == false {
                decisionHandler(.allow) // embeds such as YouTube load in their own frame
            } else {
                // The main frame only ever shows the page Wren loads into it.
                decisionHandler(url?.host == "preview.wren.local" || url?.scheme == "about" ? .allow : .cancel)
            }
        }

        private static let srcRegex = try! NSRegularExpression(pattern: "(<(?:img|video)[^>]*?src=\")([^\"]+)\"")

        /// Relative media paths are served from the sheet's folder through our private scheme.
        static func rewriteAssets(_ html: String) -> String {
            let result = NSMutableString(string: html)
            for m in srcRegex.matches(in: html, range: NSRange(location: 0, length: result.length)).reversed() {
                let src = result.substring(with: m.range(at: 2))
                guard !src.contains("://"), !src.hasPrefix("data:") else { continue }
                let path = src.hasPrefix("/") ? "file" + src : src
                result.replaceCharacters(in: m.range(at: 2), with: "\(BlogPreview.scheme)://local/\(path)")
            }
            return result as String
        }

        /// Swaps only the blocks that changed, so embeds don't reload on every keystroke,
        /// and keeps the part of the post you're editing in view.
        static let script = """
        <script>
        function wrenUpdate(html, follow) {
          const next = document.createElement('div');
          next.innerHTML = html;
          const root = document.getElementById('wren-content');
          const fresh = Array.from(next.childNodes), old = Array.from(root.childNodes);
          for (let i = 0; i < Math.max(fresh.length, old.length); i++) {
            if (i >= fresh.length) { root.removeChild(old[i]); continue; }
            if (i >= old.length) { root.appendChild(fresh[i]); continue; }
            if (!old[i].isEqualNode(fresh[i])) root.replaceChild(fresh[i], old[i]);
          }
          if (follow !== null) {
            const target = (document.documentElement.scrollHeight - innerHeight) * follow;
            if (target < scrollY + 40 || target > scrollY + innerHeight - 80) {
              window.scrollTo({ top: target - innerHeight * 0.3, behavior: 'smooth' });
            }
          }
        }
        </script>
        """
    }
}

/// Serves `wren-asset://local/<path>` from the current sheet's folder.
final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {
    var folder: URL?

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let path = String(url.path.dropFirst())
        let file: URL? = path.hasPrefix("file/")
            ? URL(fileURLWithPath: String(path.dropFirst(4)))
            : folder?.appendingPathComponent(path).standardizedFileURL
        // Images and videos only: the page can't use this to read your other files.
        guard let file, Safety.isMediaFile(file), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": mime, "Content-Length": "\(data.count)", "Accept-Ranges": "none"])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}
