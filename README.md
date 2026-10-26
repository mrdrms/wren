# Wren

A calm, beautiful Markdown writing app for macOS. Your writing stays as plain `.md` files in folders you own: no lock-in, no subscription.

## Highlights

- **Atmospheres**: write inside a living scene (Sakura, Starlight, Bamboo, Fireflies, Tide, Washi, Stone Garden, Terminal) or a plain white or black page.
- **Plain Markdown editor** with a live, side-by-side or full **preview** in four blog styles (Classic, Modern, Editorial, Mono, Terminal).
- **Format bar, selection bubble and `/` slash commands** for people who've never typed Markdown; optional live formatting.
- **Focus tools**: Zen mode, focus dimming, typewriter scrolling, a Pomodoro timer and writing sprints.
- **Flow Lock**: finished words get struck through instead of deleted, so you keep moving.
- **Never lose words**: autosave, snapshots, a Time Machine that replays every edit, and a Cutting Room Floor for deleted passages.
- **Write better**: Style Lens (adverbs, filler, passive voice, echoes), a Rhythm gutter for sentence length, and Read Aloud.
- **Projects**: book (numbered chapters, word goal, compile to Word/PDF/HTML/Markdown), blog and journal, plus 12 sheet templates.
- **Publish**: images, video and YouTube embeds; export to HTML, PDF, Word or a ready-to-upload blog folder, with a secret scanner that warns about API keys, tokens and internal IPs first.
- **Motivation**: daily goals, streaks and a Writing Garden that grows a plant for every day you write.

## Building

Requires **Xcode 26** (macOS 26 SDK). Open `writer.xcodeproj` and run the `writer` scheme, or from the command line:

```sh
xcodebuild -project writer.xcodeproj -scheme writer build
xcodebuild -project writer.xcodeproj -scheme writer test -only-testing:writerTests
```
