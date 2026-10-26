import Foundation

/// A starting point for a single sheet. Guidance lives in margin notes (`{>>…<<}`): visible
/// while you write, listed in the Outline, and never exported.
struct SheetTemplate: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let tint: UInt32
    let summary: String
    var category: TemplateCategory = .general
    let body: String
}

/// How the gallery groups sheet templates.
enum TemplateCategory: String, CaseIterable {
    case general = "Start Fresh"
    case book = "Books & Fiction"
    case articles = "Articles & Posts"
    case personal = "Personal"
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
        category: .articles,
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
        category: .articles,
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
        category: .articles,
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
        category: .articles,
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

    static let shortStory = SheetTemplate(id: "story", name: "Short Story", symbol: "sparkles", tint: 0xAF52DE,
        summary: "A scene-by-scene shape: opening image, turn, climax and resolution.",
        category: .book,
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
        summary: "Scenes split by breaks, each with a goal, an obstacle and an outcome, plus a hook.",
        category: .book,
        body: """
        # Chapter {{chapter}}

        {>>Chapter purpose: what changes for the story by the end of this chapter? If nothing changes, cut or merge it.<<}

        {>>Scene 1. Point of view: whose eyes are we in? Goal: what do they want right now? Obstacle: what's in the way? Outcome: usually "no, and…" or "yes, but…".<<}

        * * *

        {>>Scene 2. The reaction: how does the character feel about what just happened, and what do they decide to do next?<<}

        {>>Hook: end on a question, a reveal or a decision that pulls readers into the next chapter.<<}
        """)

    static let journal = SheetTemplate(id: "journal", name: "Journal Entry", symbol: "sun.max", tint: 0xFF9F0A,
        summary: "Today's date, three prompts and a line for gratitude.",
        category: .personal,
        body: """
        # {{longdate}}

        **On my mind:**

        **What happened today:**

        **What I learned:**

        **Grateful for:**
        """)

    static let character = SheetTemplate(id: "character", name: "Character Profile", symbol: "person.text.rectangle", tint: 0x64D2FF,
        summary: "Wants, needs, flaws and voice for a character in your story.",
        category: .book,
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
        category: .book,
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

    static let scene = SheetTemplate(id: "scene", name: "Scene", symbol: "film", tint: 0xD9480F,
        summary: "One scene, built to move: goal, conflict, a turn and what it leaves behind.",
        category: .book,
        body: """
        # {{title}}

        {>>Where and when: one sentence. Then drop us in late, as close to the conflict as you can.<<}

        {>>Goal: what does the point-of-view character want in this scene?<<}

        {>>Conflict: who or what pushes back? Let it escalate at least once.<<}

        {>>The turn: something changes. A secret comes out, a plan fails, a choice is made.<<}

        {>>Aftermath: what's different now, and what does it set up?<<}
        """)

    static let setting = SheetTemplate(id: "setting", name: "Setting", symbol: "map", tint: 0x5F7A4F,
        summary: "A place in your story: the senses, the rules and what it means to the people there.",
        category: .book,
        body: """
        # {{title}}

        **Where it is:**

        **When we see it:** {>>Time of day, season, era.<<}

        **First impression:** {>>What a newcomer notices in the first five seconds.<<}

        ## The senses

        - **Sight:**
        - **Sound:**
        - **Smell:**
        - **Touch:**

        ## Rules

        {>>Who's in charge here, what's forbidden, what it costs to live here.<<}

        ## What it means

        {>>Why this place matters to your characters. Safety, danger, memory, longing?<<}
        """)

    static let synopsis = SheetTemplate(id: "synopsis", name: "Synopsis", symbol: "doc.plaintext", tint: 0x8E6E53,
        summary: "The whole story in a page, ending included, the way agents and editors ask for it.",
        category: .book,
        body: """
        # {{title}}: Synopsis

        {>>Present tense, third person, about one page. Name only the characters that matter, and give away the ending.<<}

        {>>Setup: who is the protagonist, what do they want, and what's wrong in their world?<<}

        {>>The inciting incident, and the choice that pulls them into the story.<<}

        {>>The middle: the biggest complications, and the midpoint that raises the stakes.<<}

        {>>The crisis: the lowest point, and the hard choice it forces.<<}

        {>>The climax and resolution: how it ends, and how the protagonist has changed.<<}
        """)

    static let queryLetter = SheetTemplate(id: "query", name: "Query Letter", symbol: "envelope", tint: 0x0A84A8,
        summary: "Pitch your book to agents: hook, story, the details and a short bio.",
        category: .book,
        body: """
        Dear {>>Agent's name. Always personalize it.<<},

        {>>Why them: one sentence on why your book fits their list.<<}

        {>>The hook and story: two or three short paragraphs. Who your protagonist is, what they want, what stands in the way, and what they stand to lose. Don't give away the ending.<<}

        *{{title}}* is a {>>genre<<} novel complete at {>>word count<<} words. It will appeal to readers of {>>two recent comparable titles<<}.

        {>>About you: a few sentences. Writing credits, or why you're the person to write this book.<<}

        Thank you for your time and consideration.

        Best wishes,
        """)

    static let sheets: [SheetTemplate] = [blank, chapter, scene, character, setting, outline, synopsis, queryLetter, shortStory,
                                          blogPost, howTo, essay, newsletter, journal]

    // MARK: Projects

    static let projects: [ProjectTemplate] = [
        ProjectTemplate(id: "novel", name: "Novel", symbol: "book.closed.fill", tint: 0xB5651D,
            summary: "Numbered chapters, plus an outline, synopsis, character and setting notes. 80,000-word goal; compiles to Word or PDF.",
            kind: .book, goal: 80_000,
            files: [
                ("01 Chapter One.md", chapter.body.replacingOccurrences(of: "{{chapter}}", with: "1")),
                ("02 Chapter Two.md", chapter.body.replacingOccurrences(of: "{{chapter}}", with: "2")),
                ("03 Chapter Three.md", chapter.body.replacingOccurrences(of: "{{chapter}}", with: "3")),
                ("Notes/Outline.md", outline.body),
                ("Notes/Synopsis.md", synopsis.body),
                ("Notes/Main Character.md", character.body.replacingOccurrences(of: "{{title}}", with: "Main Character")),
                ("Notes/Setting.md", setting.body.replacingOccurrences(of: "{{title}}", with: "Main Setting")),
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
    /// How the book prints: trim size, margins, page numbers. Remembered per book.
    var layout: BookSettings?

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
