import Foundation

/// A starting point for a single sheet. Guidance lives in margin notes (`{>>…<<}`): visible
/// while you write, listed in the Outline, and never exported.
struct SheetTemplate: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let tint: UInt32
    let summary: String
    let body: String
}

enum ProjectKind: String, Codable, CaseIterable {
    case book, blog, journal

    var label: String {
        switch self {
        case .book: "Book"
        case .blog: "Blog"
        case .journal: "Journal"
        }
    }
    var symbol: String {
        switch self {
        case .book: "book.closed"
        case .blog: "newspaper"
        case .journal: "calendar"
        }
    }
    var newItemLabel: String {
        switch self {
        case .book: "New Chapter"
        case .blog: "New Post"
        case .journal: "Today's Entry"
        }
    }
}

/// A starting point for a whole folder: its kind decides how it sorts, what "new" creates,
/// and whether it can be compiled into a manuscript.
struct ProjectTemplate: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let tint: UInt32
    let summary: String
    let kind: ProjectKind
    let goal: Int?
    /// Relative path → template body. Rendered with the project's name as the title.
    let files: [(path: String, body: String)]
}

enum Templates {
    // MARK: Rendering

    /// Fills `{{title}}`, `{{date}}`, `{{longdate}}` and `{{chapter}}`.
    static func render(_ body: String, title: String, date: Date = .now, chapter: Int? = nil) -> String {
        let iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.dateFormat = "yyyy-MM-dd"
        let quotedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        return body
            .replacingOccurrences(of: "\"{{title}}\"", with: "\"\(quotedTitle)\"")
            .replacingOccurrences(of: "{{title}}", with: title)
            .replacingOccurrences(of: "{{date}}", with: iso.string(from: date))
            .replacingOccurrences(of: "{{longdate}}", with: date.formatted(date: .complete, time: .omitted))
            .replacingOccurrences(of: "{{chapter}}", with: chapter.map(String.init) ?? "1")
    }

    // MARK: Sheets

    static let blank = SheetTemplate(id: "blank", name: "Blank", symbol: "doc", tint: 0x8E8E93,
                                     summary: "An empty page.", body: "")

    static let blogPost = SheetTemplate(id: "blog", name: "Blog Post", symbol: "newspaper", tint: 0xE8590C,
        summary: "Hook, problem, idea, steps and a call to action. Front matter included.",
        body: """
        ---
        title: "{{title}}"
        date: {{date}}
        tags: []
        draft: true
        ---

        {>>Hook: open with a question, a surprising fact or a tiny story. Two or three sentences that make people keep reading.<<}

        ## The problem

        {>>What is your reader struggling with? Show them you understand it.<<}

        ## The idea

        {>>Your one big insight. If the reader remembers one thing, it's this.<<}

        ## How to do it

        1.
        2.
        3.

        ## Wrapping up

        {>>One line that sums it up, then tell readers what to do next: try it, share it, subscribe.<<}
        """)

    static let newsletter = SheetTemplate(id: "newsletter", name: "Newsletter", symbol: "envelope.open", tint: 0x0A84A8,
        summary: "A friendly issue: a note, the main story, quick links and a sign-off.",
        body: """
        # {{title}}

        *{{longdate}}*

        Hi friends,

        {>>A personal note: what's been on your mind this week? Keep it short and warm.<<}

        ## This week's story

        {>>The main piece. One idea, told well.<<}

        ## Worth your time

        - [Link title](https://) — why it's worth reading
        - [Link title](https://) — why it's worth reading
        - [Link title](https://) — why it's worth reading

        ## One more thing

        {>>A question for readers, a small win, or something fun.<<}

        Until next time,
        """)

    static let essay = SheetTemplate(id: "essay", name: "Essay", symbol: "text.book.closed", tint: 0x5E5CE6,
        summary: "Thesis, three supporting points, a counterargument and a conclusion.",
        body: """
        # {{title}}

        {>>Introduction: set the scene, then state your thesis in one clear sentence.<<}

        ## First point

        {>>Your strongest argument, with evidence or an example.<<}

        ## Second point

        ## Third point

        ## But what about…

        {>>The best argument against you, and why your thesis still holds.<<}

        ## Conclusion

        {>>Don't just repeat yourself. Show why it matters.<<}
        """)

    static let howTo = SheetTemplate(id: "howto", name: "How-To Guide", symbol: "list.number", tint: 0x34C759,
        summary: "What you'll need, numbered steps, tips and troubleshooting.",
        body: """
        ---
        title: "{{title}}"
        date: {{date}}
        ---

        {>>One sentence: what the reader will be able to do by the end.<<}

        ## What you'll need

        -
        -

        ## Steps

        1. **First step.** Explain it simply.
        2. **Second step.**
        3. **Third step.**

        ## Tips

        > {>>The one thing people usually get wrong.<<}

        ## Troubleshooting

        **It didn't work?**
        """)

    static let review = SheetTemplate(id: "review", name: "Review", symbol: "star.leadinghalf.filled", tint: 0xFFB800,
        summary: "For a product, book or film: verdict, pros and cons, who it's for.",
        body: """
        ---
        title: "{{title}}"
        date: {{date}}
        rating: 4/5
        ---

        **The verdict:** {>>Your opinion in one sentence. Busy readers stop here.<<}

        ## What it is

        ## What I loved

        -
        -

        ## What could be better

        -

        ## Who it's for

        {>>Who should get it, and who should skip it?<<}
        """)

    static let shortStory = SheetTemplate(id: "story", name: "Short Story", symbol: "sparkles", tint: 0xAF52DE,
        summary: "A scene-by-scene shape: opening image, turn, climax and resolution.",
        body: """
        # {{title}}

        {>>Opening image: drop us into a moment. Who wants what?<<}

        ---

        {>>The turn: something changes, and the character can't go back.<<}

        ---

        {>>The climax: the hardest choice your character makes.<<}

        ---

        {>>Resolution: what's different now? End on an image, not an explanation.<<}
        """)

    static let chapter = SheetTemplate(id: "chapter", name: "Book Chapter", symbol: "book.pages", tint: 0xB5651D,
        summary: "A chapter with a scene goal, conflict and a hook into the next one.",
        body: """
        # Chapter {{chapter}}

        {>>Scene goal: what does the point-of-view character want in this chapter?<<}

        {>>Conflict: what stands in the way?<<}

        {>>Hook: end on a question, a reveal or a decision that pulls readers into the next chapter.<<}
        """)

    static let journal = SheetTemplate(id: "journal", name: "Journal Entry", symbol: "sun.max", tint: 0xFF9F0A,
        summary: "Today's date, three prompts and a line for gratitude.",
        body: """
        # {{longdate}}

        **On my mind:**

        **What happened today:**

        **What I learned:**

        **Grateful for:**
        """)

    static let poem = SheetTemplate(id: "poem", name: "Poem", symbol: "leaf", tint: 0xFF6482,
        summary: "A quiet page with room for stanzas.",
        body: """
        # {{title}}

        {>>Start with an image you can see, hear or touch. Trust the line breaks.<<}

        """)

    static let character = SheetTemplate(id: "character", name: "Character Profile", symbol: "person.text.rectangle", tint: 0x64D2FF,
        summary: "Wants, needs, flaws and voice for a character in your story.",
        body: """
        # {{title}}

        **Role in the story:**

        **What they want:** {>>The goal they'd tell you about.<<}

        **What they need:** {>>The truth they don't see yet.<<}

        **Their flaw:**

        **How they talk:**

        **A secret:**

        ## Backstory

        ## Arc

        {>>Who are they at the start, and who are they at the end?<<}
        """)

    static let outline = SheetTemplate(id: "outline", name: "Story Outline", symbol: "list.bullet.indent", tint: 0x30B0C7,
        summary: "Three acts with the key beats every story needs.",
        body: """
        # {{title}} — Outline

        ## Act One: Setup

        - **Opening image:**
        - **Inciting incident:**
        - **The decision:** {>>The hero chooses to enter the new world.<<}

        ## Act Two: Confrontation

        - **Fun and games:**
        - **Midpoint:** {>>A false victory or a false defeat that raises the stakes.<<}
        - **Bad guys close in:**
        - **All is lost:**

        ## Act Three: Resolution

        - **The new plan:**
        - **Climax:**
        - **Final image:** {>>Mirror the opening image to show how things changed.<<}
        """)

    static let sheets: [SheetTemplate] = [blank, blogPost, newsletter, essay, howTo, review, shortStory, chapter, journal, poem, character, outline]

    // MARK: Projects

    static let projects: [ProjectTemplate] = [
        ProjectTemplate(id: "novel", name: "Novel", symbol: "book.closed.fill", tint: 0xB5651D,
            summary: "Numbered chapters, character and setting notes, an outline and an 80,000-word goal. Compiles to Word or PDF.",
            kind: .book, goal: 80_000,
            files: [
                ("01 Chapter One.md", chapter.body.replacingOccurrences(of: "{{chapter}}", with: "1")),
                ("02 Chapter Two.md", chapter.body.replacingOccurrences(of: "{{chapter}}", with: "2")),
                ("03 Chapter Three.md", chapter.body.replacingOccurrences(of: "{{chapter}}", with: "3")),
                ("Notes/Outline.md", outline.body),
                ("Notes/Main Character.md", character.body.replacingOccurrences(of: "{{title}}", with: "Main Character")),
                ("Notes/Setting.md", "# Setting\n\n**Where:** \n\n**When:** \n\n**What it feels like to be there:** \n\n{>>Smells, sounds, weather, rules. The details that make a place real.<<}\n"),
            ]),
        ProjectTemplate(id: "nonfiction", name: "Non-fiction Book", symbol: "books.vertical.fill", tint: 0x5E5CE6,
            summary: "Introduction, chapters and a conclusion, plus a research folder and a 60,000-word goal.",
            kind: .book, goal: 60_000,
            files: [
                ("01 Introduction.md", "# Introduction\n\n{>>The promise of the book: what will readers know or be able to do by the end?<<}\n"),
                ("02 Chapter One.md", "# Chapter 1\n\n{>>One big idea per chapter. Open with a story, explain the idea, end with how to apply it.<<}\n"),
                ("03 Chapter Two.md", "# Chapter 2\n\n"),
                ("04 Conclusion.md", "# Conclusion\n\n{>>Bring it together and send readers off with one clear next step.<<}\n"),
                ("Notes/Research.md", "# Research\n\n- [Source](https://) — what it says\n"),
                ("Notes/Book Proposal.md", "# {{title}}\n\n**One-line pitch:** \n\n**Who it's for:** \n\n**Why me:** \n\n**Comparable books:** \n"),
            ]),
        ProjectTemplate(id: "blog-project", name: "Blog", symbol: "newspaper.fill", tint: 0xE8590C,
            summary: "A home for your posts. New posts start with front matter and today's date, ready for Export for Blog.",
            kind: .blog, goal: nil,
            files: [("Hello World.md", blogPost.body.replacingOccurrences(of: "{{title}}", with: "Hello, world"))]),
        ProjectTemplate(id: "journal-project", name: "Journal", symbol: "calendar", tint: 0xFF9F0A,
            summary: "One page per day. \"Today's Entry\" opens today's page, or starts it.",
            kind: .journal, goal: nil,
            files: []),
    ]
}

/// Project settings stored beside the files in a hidden `.wren-project.json`.
struct ProjectInfo: Codable, Equatable {
    var kind: ProjectKind
    var goal: Int?
    var author: String?

    static let fileName = ".wren-project.json"

    static func load(from folder: URL) -> ProjectInfo? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(ProjectInfo.self, from: data)
    }

    func save(to folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: folder.appendingPathComponent(Self.fileName), options: .atomic)
    }
}

/// Book chapters are ordered by a number at the start of their file name ("03 The Storm.md").
enum Chapters {
    private static let numberPrefix = try! NSRegularExpression(pattern: "^(\\d+)\\s*[-–.]?\\s*")

    static func number(of url: URL) -> Int? {
        let name = url.deletingPathExtension().lastPathComponent
        guard let m = numberPrefix.firstMatch(in: name, range: NSRange(location: 0, length: (name as NSString).length)) else { return nil }
        return Int((name as NSString).substring(with: m.range(at: 1)))
    }

    /// The name without its number: "03 The Storm" → "The Storm".
    static func baseName(of url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let stripped = numberPrefix.stringByReplacingMatches(in: name, range: NSRange(location: 0, length: (name as NSString).length), withTemplate: "")
        return stripped.isEmpty ? name : stripped
    }

    static func fileName(number: Int, base: String, ext: String = "md") -> String {
        String(format: "%02d %@.%@", number, base, ext)
    }
}
