enum WelcomeContent {
    static let welcome = """
    # Welcome to Wren

    Wren is a writing app that gets out of your way, then cheers you on when you make progress. Everything you write is a **plain Markdown file** in a folder you own. No lock-in, no subscription.

    ## Start here

    - Press **⌘N** for a new sheet. The first line becomes its title.
    - Never used Markdown? You don't need to. Use the format bar at the top, select text for quick formatting, or type **/** on an empty line to add headings, lists, images and more.
    - Press **⌘K** to open the command palette. You can do almost anything from there.
    - Press **⌘⇧↩** for *Zen mode*: just you and the page.

    ## Write in flow

    - **Focus mode** (⌘⇧F) dims everything except the sentence or paragraph you're on.
    - **Typewriter mode** (⌘⇧T) keeps your line in the middle of the screen.
    - **Key sounds** add a soft, satisfying click to every keystroke. Turn them on in Settings.
    - Watch the little flame in the status bar. It grows as you build momentum. 🔥

    ## Stay motivated

    Set a **word goal** for this sheet in the inspector (⌘⌥I), and a **daily goal** for your streak. Hit either one and you'll get a little celebration. Start a **writing sprint** from the palette to race the clock.

    Open **Writing Journey** (⌘⇧J) to see your streak and a heatmap of every day you wrote.

    ## Write better

    The **Style Lens** (⌘⇧L) highlights adverbs, filler words, passive voice and repeated words, the way a good editor would. Try it on the sheet in the *Ideas* folder.

    ## Never lose a word

    Wren saves as you type. Take a **snapshot** (⌘⇧S) before a big rewrite and restore it any time from the inspector's History tab.

    ## Markdown at a glance

    You can write **bold**, *italic*, ==highlights==, ~~strikethrough~~, `inline code` and [links](https://example.com).

    > Quotes look like this.

    - [ ] Tasks look like this
    - [x] and can be checked off

    ---

    When you're done, export to **HTML** or **PDF**, or copy the HTML straight into your blog (⌘E).

    Happy writing. ✍️
    """

    static let whatsNew = """
    # New in Wren

    Seven features you won't find in any other writing app. Try each one right here, on this sheet.

    ## Flow Lock

    Your inner editor is the enemy of a first draft. Turn on **Flow Lock** (⌘⇧D) and Backspace still fixes typos in the word you're typing, but finished words get {--erased forever--} struck through instead. You keep moving forward, and decide later. When the draft is done, **Sweep** (⌥⌘⌫) clears every strike at once.

    Struck text is saved as standard CriticMarkup, so your file is still plain text.

    ## The Cutting Room Floor

    Select this whole paragraph and delete it. It isn't gone. Every passage you delete is quietly saved to the **Cutting Room** in the inspector, so you can cut boldly and drag your darlings back any time.

    ## Time Machine

    Wren records every pause in your typing. Open the **Time Machine** (⌘⇧Y) and press Space to watch this sheet write itself, then restore any moment you like.

    ## Rhythm

    Turn on the **Rhythm Gutter** (⌘⇧R) and look at the margin. Each bar is one sentence.

    This sentence is medium length. This sentence is medium length too. This one is also medium length. They all sound the same now.

    Now listen. Short. Then a sentence that takes its time, wandering through a clause or two, before it finally comes to rest. See the difference?

    ## Read Aloud

    Put your cursor anywhere and press ⌥⌘R. Wren reads your words in the best voice for your language and highlights each word as it goes. Your ear catches what your eye skims past.

    ## Storyboard

    Press ⌘⇧B. Every section of this sheet becomes a card. Drag the cards into a new order and the Markdown rewrites itself.

    ## Echoes and notes

    The Style Lens now spots **echoes**: when a distinctive word shows up again too soon, the echo stands out. Leave yourself a margin note with ⌘⇧M{>>like this one<<}, or type TK where a fact still needs checking. Both are listed in the Outline and left out of every export.
    """

    static let styleLensDemo = """
    # Try the Style Lens

    Press ⌘⇧L to turn on the Style Lens, then read this paragraph again.

    It was really a very dark night, and the the wind was howling loudly. The letter was written by someone who was just basically trying to quietly warn us. Honestly, it was kind of terrifying.

    Now rewrite it so the colors disappear:

    The night was black and the wind howled. Someone had written to warn us, and they had not dared to sign it.
    """
}
