import AVFoundation
import Foundation
import NaturalLanguage

/// Reads the sheet aloud from the caret, reporting each spoken word's range in the document.
final class ReadAloud: NSObject, AVSpeechSynthesizerDelegate {
    var onWord: ((NSRange) -> Void)?
    var onFinish: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var offset = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, from location: Int) {
        synthesizer.stopSpeaking(at: .immediate)
        let ns = text as NSString
        let start = ns.paragraphRange(for: NSRange(location: min(location, ns.length), length: 0)).location
        offset = start
        let utterance = AVSpeechUtterance(string: Self.speakable(ns.substring(from: start)))
        utterance.voice = Self.bestVoice(for: text)
        utterance.rate = 0.5
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Hides Markdown symbols, struck text and margin notes from the voice while keeping
    /// every character in place, so spoken ranges map 1:1 onto the document.
    static func speakable(_ text: String) -> String {
        let s = NSMutableString(string: text)
        let patterns = ["\\{--[\\s\\S]*?--\\}", "\\{>>[\\s\\S]*?<<\\}", "\\]\\([^)\\n]*\\)", "[#*_=~>`\\[\\]{}|]"]
        for pattern in patterns {
            let regex = try! NSRegularExpression(pattern: pattern)
            for m in regex.matches(in: s as String, range: NSRange(location: 0, length: s.length)) {
                s.replaceCharacters(in: m.range, with: String(repeating: " ", count: m.range.length))
            }
        }
        return s as String
    }

    /// The highest-quality installed voice for the language the sheet is written in.
    private static func bestVoice(for text: String) -> AVSpeechSynthesisVoice? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(2000)))
        let language = recognizer.dominantLanguage?.rawValue ?? Locale.current.language.languageCode?.identifier ?? "en"
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language) }
        let preferredRegion = Locale.current.region?.identifier
        return candidates.max { a, b in
            if a.quality != b.quality { return a.quality.rawValue < b.quality.rawValue }
            return !(a.language.hasSuffix(preferredRegion ?? "")) && b.language.hasSuffix(preferredRegion ?? "")
        } ?? AVSpeechSynthesisVoice(language: language)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.onWord?(NSRange(location: characterRange.location + self.offset, length: characterRange.length))
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in if !self.synthesizer.isSpeaking { self.onFinish?() } }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in if !self.synthesizer.isSpeaking { self.onFinish?() } }
    }
}
