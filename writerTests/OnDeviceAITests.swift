import Foundation
import Testing
@testable import writer

struct OnDeviceAITests {
    @Test func appleIntelligenceNeedsNoKeyAndStaysOnThisMac() {
        #expect(!AIProvider.apple.needsKey && AIProvider.apple.isLocal && !AIProvider.apple.hasModels)
        #expect(AIProvider.anthropic.needsKey && !AIProvider.anthropic.isLocal)
    }

    @Test func turnsAwayWhatItCantDo() async {
        let client = AIClient(provider: .apple, model: "")
        // Too long for the on-device model: refused up front, with a reason.
        let book = String(repeating: "A sentence of a long book. ", count: 1000)
        await #expect(throws: AIError.self) { try await client.complete(system: "Read this.", prompt: book) }
        // Pictures aren't something it can read.
        await #expect(throws: AIError.self) {
            try await client.complete(system: "Describe.", prompt: "Alt text", image: (Data([1, 2, 3]), "image/png"))
        }
    }

    /// The real model. Only when asked (TEST_RUNNER_WREN_AI=1) and Apple Intelligence is on.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WREN_AI"] != nil && AIClient.onDeviceUnavailableReason == nil))
    func lineEditsComeBackAsNotes() async throws {
        let passage = "The rain that was falling was falling very hard and it was very loud on the roof of the house that she lived in."
        let (system, prompt) = AIEditor.lineEditPrompt(passage)
        let answer = try await AIClient(provider: .apple, model: "").complete(system: system, prompt: prompt)
        let edits = AIEditor.parseLineEdits(answer)
        try? answer.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("wren-ai.txt"), atomically: true, encoding: .utf8)
        #expect(!edits.isEmpty, "Got: \(answer)")
    }
}

struct LineEditPlacementTests {
    @Test func repeatedAndSelfQuotingEditsPlaceOneNoteEach() {
        let passage = "The rain fell on the roof of the house that she lived in. It was loud."
        let edits = [
            AIEditor.LineEdit(original: "on the roof of the house that she lived in.", suggestion: "on her roof.", reason: "Tighter."),
            AIEditor.LineEdit(original: "on her roof.", suggestion: "on the roof.", reason: "Quotes its own note."),
            AIEditor.LineEdit(original: "the house that she lived in", suggestion: "her house", reason: "Overlaps the first."),
            AIEditor.LineEdit(original: "It was loud.", suggestion: "It roared.", reason: "Vivid <<} {>>"),
            AIEditor.LineEdit(original: "It was loud.", suggestion: "It roared.", reason: "Again."),
        ]
        let (text, placed) = AIEditor.annotate(passage, with: edits)
        #expect(placed == 2)
        #expect(text.components(separatedBy: "{>>").count - 1 == 2)
        #expect(text.components(separatedBy: "<<}").count - 1 == 2, "A reason can't close or open a note")
        #expect(text.hasPrefix("The rain fell on the roof of the house that she lived in. {>>✎ on her roof. (Tighter.)<<}"))
    }
}
