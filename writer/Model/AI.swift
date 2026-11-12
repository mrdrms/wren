import Foundation
import FoundationModels

/// AI services you can connect with your own key, Ollama running on this Mac, or Apple
/// Intelligence, built in.
enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case apple, anthropic, openai, gemini, ollama

    var id: String { rawValue }
    var label: String {
        switch self {
        case .apple: "Apple Intelligence (on this Mac)"
        case .anthropic: "Anthropic (Claude)"
        case .openai: "OpenAI"
        case .gemini: "Google Gemini"
        case .ollama: "Ollama (on this Mac)"
        }
    }
    /// A sensible starting model; any model the service offers can be typed in instead.
    var defaultModel: String {
        switch self {
        case .apple: "on-device"
        case .anthropic: "claude-opus-5-5"
        case .openai: "gpt-5"
        case .gemini: "gemini-2.5-pro"
        case .ollama: "llama3.1"
        }
    }
    var needsKey: Bool { self != .ollama && self != .apple }
    /// Whether requests stay on this Mac.
    var isLocal: Bool { self == .ollama || self == .apple }
    /// Whether you can pick a model.
    var hasModels: Bool { self != .apple }
    var keychainKey: String { "ai-\(rawValue)" }
    var keyHelp: String {
        switch self {
        case .apple: "Built into Macs with Apple Intelligence: free, private, and nothing leaves this Mac. It's a small model, best for line edits and title ideas; a whole book is too long for it, and it can't look at pictures."
        case .anthropic: "Create a key at platform.claude.com → API Keys."
        case .openai: "Create a key at platform.openai.com → API keys."
        case .gemini: "Create a key in Google AI Studio → Get API key."
        case .ollama: "Install Ollama, then run “ollama pull llama3.1”. Nothing leaves this Mac."
        }
    }
}

enum AIError: LocalizedError {
    case missingKey(AIProvider), server(String), declined, empty

    var errorDescription: String? {
        switch self {
        case .missingKey(let provider): "Add your \(provider.label) key in Settings → AI."
        case .server(let message): message
        case .declined: "The model declined this request."
        case .empty: "The model returned nothing."
        }
    }
}

/// One request, one answer: Wren's AI features never run on their own or keep a conversation.
struct AIClient {
    let provider: AIProvider
    let model: String
    let key: String?
    /// How hard the model should think: "medium" for quick help, "high" for whole-book reads.
    var effort = "medium"

    init(provider: AIProvider, model: String, effort: String = "medium") {
        self.provider = provider
        self.model = model.trimmingCharacters(in: .whitespaces).isEmpty ? provider.defaultModel : model
        self.key = Keychain.get(provider.keychainKey)
        self.effort = effort
    }

    func complete(system: String, prompt: String, image: (data: Data, mime: String)? = nil) async throws -> String {
        if provider == .apple { return try await Self.onDevice(system: system, prompt: prompt, image: image) }
        if provider.needsKey && (key ?? "").isEmpty { throw AIError.missingKey(provider) }
        let request = try makeRequest(system: system, prompt: prompt, image: image)
        // Ollama is local; everything else carries a key and must not follow redirects elsewhere.
        let (data, response) = try await (provider == .ollama ? Self.session : Safety.credentialSession).data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.server("No response from \(provider.label).") }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else { throw AIError.server(errorMessage(json, status: http.statusCode)) }
        let text = try parse(json)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.empty }
        return text
    }

    /// Apple's on-device model. It reads a few pages at a time, so longer requests are turned
    /// away up front with a clear reason instead of failing after a wait.
    static let onDeviceLimit = 12_000

    static var onDeviceUnavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return "This Mac can't run Apple Intelligence. Choose another service in Settings → AI."
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in System Settings, or choose another service in Settings → AI."
        case .unavailable(.modelNotReady): return "Apple Intelligence is still getting ready. Try again in a little while."
        case .unavailable: return "Apple Intelligence isn't available right now."
        }
    }

    private static func onDevice(system: String, prompt: String, image: (data: Data, mime: String)?) async throws -> String {
        if let reason = onDeviceUnavailableReason { throw AIError.server(reason) }
        if image != nil {
            throw AIError.server("Apple Intelligence can't look at pictures. Choose another service in Settings → AI to write alt text.")
        }
        guard system.count + prompt.count <= onDeviceLimit else {
            throw AIError.server("That's more than Apple Intelligence can read at once (a few pages). Try a shorter passage, or choose another service in Settings → AI for whole-book reads.")
        }
        do {
            let session = LanguageModelSession(instructions: system)
            let text = try await session.respond(to: prompt).content
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.empty }
            return text
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize:
                throw AIError.server("That's more than Apple Intelligence can read at once. Try a shorter passage.")
            case .guardrailViolation, .refusal:
                throw AIError.declined
            default:
                throw AIError.server("Apple Intelligence couldn't finish: \(error.localizedDescription)")
            }
        }
    }

    /// Whole-book requests can take minutes.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 900
        return URLSession(configuration: configuration)
    }()

    private func makeRequest(system: String, prompt: String, image: (data: Data, mime: String)?) throws -> URLRequest {
        let key = key ?? ""
        var request: URLRequest
        switch provider {
        case .apple:
            // Never sent anywhere: on-device requests don't go through here.
            throw AIError.server("Apple Intelligence runs on this Mac.")
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
            // If a safety check declines (dark fiction can trip one), retry on Anthropic's
            // recommended model for that case instead of failing.
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            var content: [[String: Any]] = []
            if let image {
                content.append(["type": "image", "source": ["type": "base64", "media_type": image.mime, "data": image.data.base64EncodedString()]])
            }
            content.append(["type": "text", "text": prompt])
            request.jsonBody([
                "model": model,
                "max_tokens": 16000,
                "system": system,
                "messages": [["role": "user", "content": content]],
                "output_config": ["effort": effort],
                "fallbacks": "default",
            ])
        case .openai:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            var content: [[String: Any]] = [["type": "text", "text": prompt]]
            if let image {
                content.append(["type": "image_url", "image_url": ["url": "data:\(image.mime);base64,\(image.data.base64EncodedString())"]])
            }
            request.jsonBody(["model": model, "messages": [["role": "system", "content": system], ["role": "user", "content": content]]])
        case .gemini:
            let name = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
            request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(name):generateContent")!)
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            var parts: [[String: Any]] = [["text": prompt]]
            if let image { parts.append(["inline_data": ["mime_type": image.mime, "data": image.data.base64EncodedString()]]) }
            request.jsonBody(["system_instruction": ["parts": [["text": system]]], "contents": [["role": "user", "parts": parts]]])
        case .ollama:
            // 127.0.0.1 rather than localhost: plain HTTP to an IP address is allowed.
            request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/chat")!)
            var user: [String: Any] = ["role": "user", "content": prompt]
            if let image { user["images"] = [image.data.base64EncodedString()] }
            request.jsonBody(["model": model, "stream": false, "messages": [["role": "system", "content": system], user]])
        }
        request.httpMethod = "POST"
        return request
    }

    private func parse(_ json: [String: Any]) throws -> String {
        switch provider {
        case .apple:
            return ""
        case .anthropic:
            if json["stop_reason"] as? String == "refusal" { throw AIError.declined }
            let blocks = json["content"] as? [[String: Any]] ?? []
            return blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        case .openai:
            return (((json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String) ?? ""
        case .gemini:
            let parts = (((json["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
            return parts.compactMap { $0["text"] as? String }.joined()
        case .ollama:
            return ((json["message"] as? [String: Any])?["content"] as? String) ?? ""
        }
    }

    private func errorMessage(_ json: [String: Any], status: Int) -> String {
        let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? (json["error"] as? String)
        switch status {
        case 401, 403: return "\(provider.label) didn't accept the key (\(status)). Check it in Settings → AI."
        case 404: return "\(provider.label) doesn't know the model “\(model)”." + (message.map { " \($0)" } ?? "")
        case 429: return "\(provider.label) is rate-limiting this key. Try again in a minute."
        default: return message.map { "\(provider.label): \($0)" } ?? "\(provider.label) answered with an error (\(status))."
        }
    }
}

/// Wren's AI is an editor, not a ghostwriter: it suggests, questions and summarizes, and
/// every suggestion lands as a margin note you can keep or delete.
enum AIEditor {
    static let editorVoice = """
    You are a thoughtful, experienced editor helping a writer with their own work. Never rewrite \
    the piece or write new material for it. Respect the writer's voice and style; suggest, don't impose. \
    Be specific and concise, and point to exact passages.
    """

    struct LineEdit: Decodable {
        let original: String
        let suggestion: String
        let reason: String
    }

    static func lineEditPrompt(_ passage: String) -> (system: String, prompt: String) {
        (editorVoice, """
        Line-edit this passage. Find up to 8 places where a sentence could be clearer, tighter or more vivid. \
        For each, quote the original wording exactly as it appears (a phrase or one sentence), give a suggested \
        replacement and a short reason (under 12 words). If the passage is already strong, return fewer or none.

        Answer with only a JSON array, no other text: \
        [{"original": "...", "suggestion": "...", "reason": "..."}]

        Passage:
        <<<
        \(passage)
        >>>
        """)
    }

    /// Pulls the JSON array out of an answer, even if the model wrapped it in prose or a code fence.
    static func parseLineEdits(_ answer: String) -> [LineEdit] {
        guard let start = answer.firstIndex(of: "["), let end = answer.lastIndex(of: "]"), start < end,
              let data = String(answer[start...end]).data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([LineEdit].self, from: data)) ?? []
    }

    /// The passage with each suggestion as a margin note right after the words it's about.
    /// Edits are matched against the passage as written, never against notes already added, and
    /// each place gets at most one note, so a model that repeats itself can't stack or nest notes.
    static func annotate(_ passage: String, with edits: [LineEdit]) -> (text: String, placed: Int) {
        func clean(_ s: String) -> String {
            s.replacingOccurrences(of: "<<}", with: "").replacingOccurrences(of: "{>>", with: "")
                .replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        }
        var notes: [(at: String.Index, note: String)] = []
        var taken: [Range<String.Index>] = []
        for edit in edits {
            let original = edit.original, suggestion = clean(edit.suggestion)
            guard !original.isEmpty, !suggestion.isEmpty, suggestion != original,
                  let range = passage.range(of: original), !taken.contains(where: { $0.overlaps(range) }) else { continue }
            taken.append(range)
            let reason = clean(edit.reason)
            notes.append((range.upperBound, " {>>✎ \(suggestion)\(reason.isEmpty ? "" : " (\(reason))")<<}"))
        }
        var result = passage
        // From the end, so earlier positions stay valid.
        for item in notes.sorted(by: { $0.at > $1.at }) { result.insert(contentsOf: item.note, at: item.at) }
        return (result, notes.count)
    }

    static func critiquePrompt(title: String, text: String) -> (system: String, prompt: String) {
        (editorVoice, """
        Give an editor's read of this piece, “\(title)”. In Markdown, under short headings: what works (2–3 points), \
        then what to look at — pacing, clarity, structure, dialogue or argument, whichever apply — with the passages \
        concerned quoted briefly. End with the single most valuable next revision. Under 400 words.

        <<<
        \(text)
        >>>
        """)
    }

    static func continuityPrompt(book: String, chapters: [(title: String, text: String)]) -> (system: String, prompt: String) {
        let manuscript = chapters.enumerated().map { "=== Chapter file \($0.offset + 1): \($0.element.title) ===\n\($0.element.text)" }
            .joined(separator: "\n\n")
        return (editorVoice, """
        You are checking the continuity of the book “\(book)”. Read every chapter, then list contradictions between \
        them: names or spellings that change, ages, dates and timelines that don't add up, facts or descriptions \
        that conflict, objects or characters that appear or vanish without explanation. For each, name the chapters \
        and quote the conflicting lines. Only list real inconsistencies; if you find none, say so. Use Markdown.

        \(manuscript)
        """)
    }

    static func synopsisPrompt(book: String, chapters: [(title: String, text: String)]) -> (system: String, prompt: String) {
        let manuscript = chapters.enumerated().map { "=== \($0.element.title) ===\n\($0.element.text)" }.joined(separator: "\n\n")
        return (editorVoice + " Here you summarize the writer's own book; summarizing is not writing new material.", """
        Write a one-page synopsis of “\(book)” the way agents and editors ask for it: present tense, third person, \
        the main characters only, the whole arc including the ending. About 500 words, plain paragraphs, no headings.

        \(manuscript)
        """)
    }

    static func titlesPrompt(text: String) -> (system: String, prompt: String) {
        (editorVoice, """
        Suggest 10 titles for this piece, true to its voice: a mix of plain, intriguing and specific. \
        Answer with only a Markdown list, one title per line, no commentary.

        <<<
        \(text)
        >>>
        """)
    }

    static let altTextPrompt = (system: "You write image descriptions for screen readers.",
                                prompt: "Write alt text for this image: one plain sentence under 20 words describing what it shows. Answer with only the sentence.")
}
