import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// Blogs Wren can publish to directly, through each platform's official API.
enum PublishPlatform: String, CaseIterable, Identifiable, Codable {
    case ghost, wordpress, microblog, devto, hashnode

    var id: String { rawValue }
    var label: String {
        switch self {
        case .ghost: "Ghost"
        case .wordpress: "WordPress"
        case .microblog: "Micro.blog"
        case .devto: "DEV"
        case .hashnode: "Hashnode"
        }
    }
    var symbol: String {
        switch self {
        case .ghost: "g.circle"
        case .wordpress: "w.circle"
        case .microblog: "bubble.left"
        case .devto: "chevron.left.forwardslash.chevron.right"
        case .hashnode: "number"
        }
    }
    /// Whether the site address is asked for (and what it looks like).
    var sitePrompt: String? {
        switch self {
        case .ghost: "https://yourblog.ghost.io"
        case .wordpress: "https://yourblog.com"
        case .hashnode: "yourblog.hashnode.dev"
        case .microblog, .devto: nil
        }
    }
    var needsUsername: Bool { self == .wordpress }
    var secretLabel: String {
        switch self {
        case .ghost: "Admin API key"
        case .wordpress: "Application password"
        case .microblog: "App token"
        case .devto: "API key"
        case .hashnode: "Personal access token"
        }
    }
    var secretHelp: String {
        switch self {
        case .ghost: "Ghost Admin → Settings → Integrations → Add custom integration → Admin API key."
        case .wordpress: "WordPress → Users → Profile → Application Passwords. Use your username, not your email."
        case .microblog: "Micro.blog → Account → Edit Apps → Generate token."
        case .devto: "DEV → Settings → Extensions → DEV Community API Keys."
        case .hashnode: "Hashnode → Account settings → Developer → Generate new token."
        }
    }
    /// Platforms that host your images. The others need images that are already online.
    var uploadsImages: Bool { self == .ghost || self == .wordpress || self == .microblog }
}

struct PublishAccount: Codable, Identifiable, Hashable {
    var id = UUID()
    var platform: PublishPlatform
    var site: String = ""
    var username: String = ""

    var name: String {
        let host = site.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return host.isEmpty ? platform.label : "\(platform.label) · \(host)"
    }
    var keychainKey: String { "publish-\(id.uuidString)" }
    var secret: String? { Keychain.get(keychainKey) }

    /// The site without a trailing slash, with https:// added if it was left out.
    var baseURL: String {
        var value = site.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty, !value.contains("://") { value = "https://" + value }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }
}

/// A sheet ready to post: title split out, metadata and the duplicate title heading removed.
struct PreparedPost {
    var title: String
    var markdown: String
    var tags: [String]
    /// Local images and videos the post links to, by the path written in the Markdown.
    var localMedia: [(path: String, file: URL)]

    init(text: String, fallbackTitle: String, folder: URL?) {
        let cleaned = Ghost.clean(text)
        let fields = FrontMatter.fields(cleaned)
        var body = FrontMatter.strip(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        var title = fields["title"].flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle
        // Platforms show the title themselves; a leading "# Title" would repeat it.
        if let firstLine = body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first,
           firstLine.hasPrefix("# ") {
            let heading = firstLine.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if fields["title"] == nil { title = heading }
            if heading == title { body = String(body.dropFirst(firstLine.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        self.title = title
        self.markdown = body
        self.tags = (fields["tags"] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .filter { !$0.isEmpty }
        var media: [(String, URL)] = []
        for reference in MarkdownImage.references(in: body) where !media.contains(where: { $0.0 == reference.path }) {
            if let file = MarkdownImage.resolve(reference.path, relativeTo: folder), file.isFileURL,
               FileManager.default.fileExists(atPath: file.path) {
                media.append((reference.path, file))
            }
        }
        self.localMedia = media
    }

    func replacingMedia(_ uploaded: [String: String]) -> String {
        var result = markdown
        for (local, remote) in uploaded { result = result.replacingOccurrences(of: "](\(local))", with: "](\(remote))") }
        return result
    }

    /// Body without local media, for platforms that can't host it (the links would break).
    var markdownWithoutLocalMedia: String {
        var result = markdown
        for item in localMedia {
            result = result.replacingOccurrences(of: #"!\[[^\]\n]*\]\("# + NSRegularExpression.escapedPattern(for: item.path) + #"(?:\s+"[^"\n]*")?\)"#,
                                                 with: "", options: .regularExpression)
        }
        return result
    }
}

enum PublishError: LocalizedError {
    case missingSecret, badSite, server(String)

    var errorDescription: String? {
        switch self {
        case .missingSecret: "This account has no key saved. Add it again in Settings → Publishing."
        case .badSite: "The site address doesn't look right."
        case .server(let message): message
        }
    }
}

/// Talks to each platform's official API. Every call is a plain HTTPS request; keys are read
/// from the Keychain at the moment of publishing.
enum Publisher {
    /// Posts `post` and returns its web address when the platform reports one.
    static func publish(_ post: PreparedPost, to account: PublishAccount, asDraft: Bool) async throws -> URL? {
        guard let secret = account.secret, !secret.isEmpty else { throw PublishError.missingSecret }
        var uploaded: [String: String] = [:]
        if account.platform.uploadsImages {
            for item in post.localMedia {
                uploaded[item.path] = try await uploadMedia(item.file, to: account, secret: secret)
            }
        }
        let markdown = account.platform.uploadsImages ? post.replacingMedia(uploaded) : post.markdownWithoutLocalMedia
        switch account.platform {
        case .ghost: return try await ghostPost(post, markdown: markdown, account: account, secret: secret, draft: asDraft)
        case .wordpress: return try await wordPressPost(post, markdown: markdown, account: account, secret: secret, draft: asDraft)
        case .microblog: return try await microblogPost(post, markdown: markdown, secret: secret, draft: asDraft)
        case .devto: return try await devPost(post, markdown: markdown, secret: secret, draft: asDraft)
        case .hashnode: return try await hashnodePost(post, markdown: markdown, account: account, secret: secret, draft: asDraft)
        }
    }

    private static func uploadMedia(_ file: URL, to account: PublishAccount, secret: String) async throws -> String {
        let data = try Data(contentsOf: file)
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        switch account.platform {
        case .ghost:
            var request = try ghostRequest(account, path: "images/upload/", secret: secret)
            let form = Multipart(fields: ["purpose": "image", "ref": file.lastPathComponent], file: (file.lastPathComponent, mime, data))
            form.apply(to: &request)
            let json = try await send(request)
            guard let url = ((json["images"] as? [[String: Any]])?.first?["url"]) as? String else { throw PublishError.server("Ghost didn't return the image address.") }
            return url
        case .wordpress:
            guard let endpoint = URL(string: account.baseURL + "/wp-json/wp/v2/media") else { throw PublishError.badSite }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue(basicAuth(account.username, secret), forHTTPHeaderField: "Authorization")
            request.setValue(mime, forHTTPHeaderField: "Content-Type")
            request.setValue("attachment; filename=\"\(file.lastPathComponent)\"", forHTTPHeaderField: "Content-Disposition")
            request.httpBody = data
            let json = try await send(request)
            guard let url = json["source_url"] as? String else { throw PublishError.server("WordPress didn't return the image address.") }
            return url
        case .microblog:
            var request = URLRequest(url: URL(string: "https://micro.blog/micropub/media")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            Multipart(fields: [:], file: (file.lastPathComponent, mime, data)).apply(to: &request)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let location = http.value(forHTTPHeaderField: "Location") else { throw PublishError.server("Micro.blog didn't accept the image.") }
            return location
        case .devto, .hashnode:
            return file.absoluteString
        }
    }

    // MARK: Ghost

    /// Admin API tokens are short-lived JWTs signed with the secret half of "id:secret".
    static func ghostToken(apiKey: String, now: Date = .now) throws -> String {
        let parts = apiKey.split(separator: ":")
        guard parts.count == 2, let secret = Data(hex: String(parts[1])) else { throw PublishError.server("A Ghost Admin API key looks like id:secret.") }
        func encode(_ object: [String: Any]) -> String {
            (try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys))?.base64URL ?? ""
        }
        let iat = Int(now.timeIntervalSince1970)
        let unsigned = encode(["alg": "HS256", "typ": "JWT", "kid": String(parts[0])]) + "." + encode(["iat": iat, "exp": iat + 300, "aud": "/admin/"])
        let signature = HMAC<SHA256>.authenticationCode(for: Data(unsigned.utf8), using: SymmetricKey(data: secret))
        return unsigned + "." + Data(signature).base64URL
    }

    private static func ghostRequest(_ account: PublishAccount, path: String, secret: String) throws -> URLRequest {
        guard let url = URL(string: account.baseURL + "/ghost/api/admin/" + path) else { throw PublishError.badSite }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Ghost \(try ghostToken(apiKey: secret))", forHTTPHeaderField: "Authorization")
        request.setValue("v5.0", forHTTPHeaderField: "Accept-Version")
        return request
    }

    private static func ghostPost(_ post: PreparedPost, markdown: String, account: PublishAccount, secret: String, draft: Bool) async throws -> URL? {
        var request = try ghostRequest(account, path: "posts/?source=html", secret: secret)
        let body: [String: Any] = ["posts": [[
            "title": post.title,
            "html": MarkdownHTML.convert(markdown),
            "status": draft ? "draft" : "published",
            "tags": post.tags.map { ["name": $0] },
        ]]]
        request.jsonBody(body)
        let json = try await send(request)
        return ((json["posts"] as? [[String: Any]])?.first?["url"] as? String).flatMap(URL.init(string:))
    }

    // MARK: WordPress

    private static func basicAuth(_ user: String, _ password: String) -> String {
        "Basic " + Data("\(user):\(password.replacingOccurrences(of: " ", with: ""))".utf8).base64EncodedString()
    }

    private static func wordPressPost(_ post: PreparedPost, markdown: String, account: PublishAccount, secret: String, draft: Bool) async throws -> URL? {
        guard let url = URL(string: account.baseURL + "/wp-json/wp/v2/posts") else { throw PublishError.badSite }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(basicAuth(account.username, secret), forHTTPHeaderField: "Authorization")
        request.jsonBody(["title": post.title, "content": MarkdownHTML.convert(markdown), "status": draft ? "draft" : "publish"])
        let json = try await send(request)
        return (json["link"] as? String).flatMap(URL.init(string:))
    }

    // MARK: Micro.blog (Micropub)

    private static func microblogPost(_ post: PreparedPost, markdown: String, secret: String, draft: Bool) async throws -> URL? {
        var request = URLRequest(url: URL(string: "https://micro.blog/micropub")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        var fields = [("h", "entry"), ("name", post.title), ("content", markdown)]
        if draft { fields.append(("post-status", "draft")) }
        fields += post.tags.map { ("category[]", $0) }
        request.httpBody = fields.map { "\($0.0)=\(formEncode($0.1))" }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PublishError.server("No response from Micro.blog.") }
        guard (200..<300).contains(http.statusCode) else { throw PublishError.server(serverMessage(data, status: http.statusCode)) }
        return http.value(forHTTPHeaderField: "Location").flatMap(URL.init(string:))
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: DEV

    private static func devPost(_ post: PreparedPost, markdown: String, secret: String, draft: Bool) async throws -> URL? {
        var request = URLRequest(url: URL(string: "https://dev.to/api/articles")!)
        request.httpMethod = "POST"
        request.setValue(secret, forHTTPHeaderField: "api-key")
        // DEV allows four tags, lowercase letters and numbers only.
        let tags = post.tags.map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }.filter { !$0.isEmpty }.prefix(4)
        request.jsonBody(["article": ["title": post.title, "body_markdown": markdown, "published": !draft, "tags": Array(tags)]])
        let json = try await send(request)
        return (json["url"] as? String).flatMap(URL.init(string:))
    }

    // MARK: Hashnode (GraphQL)

    private static func hashnodePost(_ post: PreparedPost, markdown: String, account: PublishAccount, secret: String, draft: Bool) async throws -> URL? {
        let host = account.baseURL.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        guard !host.isEmpty else { throw PublishError.badSite }
        let lookup = try await hashnode(secret, query: "query Publication($host: String!) { publication(host: $host) { id } }",
                                        variables: ["host": host])
        guard let publicationID = ((lookup["publication"] as? [String: Any])?["id"]) as? String else {
            throw PublishError.server("Hashnode couldn't find a blog at \(host).")
        }
        let input: [String: Any] = ["title": post.title, "contentMarkdown": markdown, "publicationId": publicationID]
        if draft {
            _ = try await hashnode(secret, query: "mutation CreateDraft($input: CreateDraftInput!) { createDraft(input: $input) { draft { id } } }",
                                   variables: ["input": input])
            return URL(string: "https://hashnode.com/drafts")
        }
        var publishInput = input
        publishInput["tags"] = [] as [Any]
        let result = try await hashnode(secret, query: "mutation PublishPost($input: PublishPostInput!) { publishPost(input: $input) { post { url } } }",
                                        variables: ["input": publishInput])
        return (((result["publishPost"] as? [String: Any])?["post"] as? [String: Any])?["url"] as? String).flatMap(URL.init(string:))
    }

    private static func hashnode(_ token: String, query: String, variables: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://gql.hashnode.com")!)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.jsonBody(["query": query, "variables": variables])
        let json = try await send(request)
        if let errors = json["errors"] as? [[String: Any]], let message = errors.first?["message"] as? String {
            throw PublishError.server("Hashnode: \(message)")
        }
        return json["data"] as? [String: Any] ?? [:]
    }

    // MARK: HTTP

    private static func send(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PublishError.server("No response from the server.") }
        guard (200..<300).contains(http.statusCode) else { throw PublishError.server(serverMessage(data, status: http.statusCode)) }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// The most useful line from an error response.
    private static func serverMessage(_ data: Data, status: Int) -> String {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = (json?["message"] as? String)
            ?? ((json?["errors"] as? [[String: Any]])?.first?["message"] as? String)
            ?? (json?["error"] as? String)
        switch status {
        case 401, 403: return "The site refused the key (\(status)). Check it in Settings → Publishing." + (message.map { " \($0)" } ?? "")
        case 404: return "Nothing found at that address (404). Check the site address."
        default: return message ?? "The server answered with an error (\(status))."
        }
    }
}

/// A multipart/form-data body with one file.
private struct Multipart {
    let fields: [String: String]
    let file: (name: String, mime: String, data: Data)
    private let boundary = "wren-\(UUID().uuidString)"

    func apply(to request: inout URLRequest) {
        var body = Data()
        func add(_ string: String) { body.append(Data(string.utf8)) }
        for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
            add("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n")
        }
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(file.name)\"\r\nContent-Type: \(file.mime)\r\n\r\n")
        body.append(file.data)
        add("\r\n--\(boundary)--\r\n")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
    }
}

extension URLRequest {
    mutating func jsonBody(_ object: [String: Any]) {
        setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpBody = try? JSONSerialization.data(withJSONObject: object)
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
