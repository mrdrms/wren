import Foundation

/// Looks for things that shouldn't be published: keys, tokens, passwords and internal
/// addresses. Security write-ups often start from real notes; this catches what slipped through.
enum SecretScanner {
    struct Finding: Equatable {
        let kind: String
        let line: Int
        let range: NSRange
        /// The match with its middle masked, safe to show on screen.
        let preview: String
    }

    private static let rules: [(String, NSRegularExpression)] = [
        ("Private key", "-----BEGIN [A-Z ]*PRIVATE KEY-----"),
        ("AWS access key", "\\b(?:AKIA|ASIA)[0-9A-Z]{16}\\b"),
        ("GitHub token", "\\bgh[pousr]_[A-Za-z0-9]{30,}\\b"),
        ("Slack token", "\\bxox[abprs]-[A-Za-z0-9-]{10,}"),
        ("Stripe key", "\\b(?:sk|rk)_live_[A-Za-z0-9]{16,}\\b"),
        ("Google API key", "\\bAIza[0-9A-Za-z_-]{35}\\b"),
        ("JSON Web Token", "\\beyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}"),
        ("Password or secret", "(?i)\\b(?:api[_-]?key|secret|passw(?:or)?d|token|auth)\\b[\"']?\\s*[:=]\\s*[\"']?[^\\s\"'`]{8,}"),
        ("Internal IP address", "\\b(?:10\\.\\d{1,3}|192\\.168|172\\.(?:1[6-9]|2\\d|3[01]))\\.\\d{1,3}\\.\\d{1,3}\\b"),
    ].map { ($0.0, try! NSRegularExpression(pattern: $0.1)) }

    static func scan(_ text: String) -> [Finding] {
        let ns = text as NSString
        var findings: [Finding] = []
        var seen = Set<Int>()
        for (kind, regex) in rules {
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) where seen.insert(m.range.location).inserted {
                let line = ns.substring(to: m.range.location).reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
                findings.append(Finding(kind: kind, line: line, range: m.range, preview: mask(ns.substring(with: m.range))))
            }
        }
        return findings.sorted { $0.range.location < $1.range.location }
    }

    /// "AKIAIOSFODNN7EXAMPLE" → "AKIA…MPLE".
    static func mask(_ secret: String) -> String {
        guard secret.count > 10 else { return String(repeating: "•", count: secret.count) }
        return String(secret.prefix(4)) + "…" + String(secret.suffix(4))
    }
}
