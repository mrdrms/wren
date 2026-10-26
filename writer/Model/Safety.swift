import Foundation

/// The rules for what Wren will open, follow or send, in one place.
nonisolated enum Safety {
    /// Links Wren opens or keeps in exports. Others (file:, javascript:, app URL schemes)
    /// could run something or open an app, so they're refused.
    static func isSafeLink(_ url: URL) -> Bool {
        ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "")
    }

    /// An href for exported HTML: web, mail, in-page and relative links stay; anything else
    /// becomes inert.
    static func safeHref(_ href: String) -> String {
        let decoded = href.replacingOccurrences(of: "&amp;", with: "&")
        guard let colon = decoded.firstIndex(of: ":") else { return href } // relative or #anchor
        let scheme = decoded[..<colon].lowercased()
        // A colon after a slash, ? or # belongs to the path, not a scheme.
        if scheme.contains(where: { "/?#".contains($0) }) { return href }
        return ["http", "https", "mailto"].contains(scheme) ? href : "#"
    }

    /// Only real image and video files are ever uploaded, embedded or packed. A Markdown file
    /// from someone else can't make Wren send your other files that way.
    static func isMediaFile(_ url: URL) -> Bool {
        url.isFileURL && ImageImporter.mediaExtensions.contains(url.pathExtension.lowercased())
            && FileManager.default.fileExists(atPath: url.path)
    }

    /// A session for requests that carry a key: it won't follow a redirect to another host
    /// or from https down to http, where the key would leak.
    static let credentialSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 900
        return URLSession(configuration: configuration, delegate: SameHostRedirects(), delegateQueue: nil)
    }()

    private final class SameHostRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            let from = task.originalRequest?.url, to = request.url
            guard let from, let to, from.host?.lowercased() == to.host?.lowercased(),
                  !(from.scheme == "https" && to.scheme != "https") else { return nil }
            return request
        }
    }
}
