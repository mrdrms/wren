import SwiftUI

// MARK: Publish

/// Post the open sheet to one of your blogs, or copy it for Substack and Medium.
struct PublishSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var accountID: UUID?
    @State private var asDraft = true
    @State private var working = false
    @State private var outcome: Result<URL?, Error>?

    var body: some View {
        let accounts = model.prefs.publishAccounts
        let post = PreparedPost(text: model.text, fallbackTitle: model.currentTitle, folder: model.loadedURL?.deletingLastPathComponent())
        let account = accounts.first { $0.id == accountID } ?? accounts.first
        VStack(alignment: .leading, spacing: 16) {
            Label("Publish", systemImage: "paperplane").font(.title2.weight(.bold))

            VStack(alignment: .leading, spacing: 4) {
                Text(post.title).font(.system(.title3, design: .serif).weight(.semibold))
                Text("\(TextStats.contentWords(post.markdown).formatted()) words"
                     + (post.tags.isEmpty ? "" : " · tags: \(post.tags.joined(separator: ", "))")
                     + (post.localMedia.isEmpty ? "" : " · \(post.localMedia.count) image\(post.localMedia.count == 1 ? "" : "s")"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    if accounts.isEmpty {
                        Text("Connect Ghost, WordPress, Micro.blog, DEV or Hashnode to publish in one click.")
                            .foregroundStyle(.secondary)
                        SettingsLink { Text("Add a Blog in Settings…") }
                    } else {
                        Picker("Blog", selection: Binding(get: { account?.id }, set: { accountID = $0 })) {
                            ForEach(accounts) { Text($0.name).tag(Optional($0.id)) }
                        }
                        Picker("As", selection: $asDraft) {
                            Text("Draft").tag(true)
                            Text("Published post").tag(false)
                        }
                        .pickerStyle(.segmented)
                        if let account, !account.platform.uploadsImages, !post.localMedia.isEmpty {
                            Label("\(account.platform.label) can't host images from your Mac, so they'll be left out. Use images that are already online.",
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Substack and Medium").font(.callout.weight(.semibold))
                    Text("They don't allow apps to post for you, so copy the post with its formatting and paste it into their editor. Put the title in their title field.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Copy for Substack or Medium") {
                        dismiss()
                        model.export("rich")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            if let outcome {
                switch outcome {
                case .success(let url):
                    Label(asDraft ? "Saved as a draft." : "Published.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    if let url { Link("Open \(url.host() ?? "post")", destination: url) }
                case .failure(let error):
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).textSelection(.enabled)
                }
            }

            HStack {
                if working { ProgressView().controlSize(.small); Text("Publishing…").foregroundStyle(.secondary) }
                Spacer()
                Button("Close", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(asDraft ? "Save Draft" : "Publish") {
                    guard let account else { return }
                    working = true
                    outcome = nil
                    Task {
                        do {
                            outcome = .success(try await Publisher.publish(post, to: account, asDraft: asDraft))
                        } catch {
                            outcome = .failure(error)
                        }
                        working = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
                .disabled(account == nil || working)
            }
        }
        .padding(22)
        .frame(width: 480)
    }
}

struct PublishingSettings: View {
    @Environment(AppModel.self) private var model
    @State private var platform = PublishPlatform.ghost
    @State private var site = ""
    @State private var username = ""
    @State private var secret = ""

    var body: some View {
        @Bindable var prefs = model.prefs
        Form {
            Section("Your blogs") {
                if prefs.publishAccounts.isEmpty {
                    Text("None yet. Add one below.").foregroundStyle(.secondary)
                }
                ForEach(prefs.publishAccounts) { account in
                    HStack {
                        Label(account.name, systemImage: account.platform.symbol)
                        Spacer()
                        Button("Remove", role: .destructive) {
                            Keychain.delete(account.keychainKey)
                            prefs.publishAccounts.removeAll { $0.id == account.id }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Section("Add a blog") {
                Picker("Platform", selection: $platform) {
                    ForEach(PublishPlatform.allCases) { Text($0.label).tag($0) }
                }
                if let prompt = platform.sitePrompt {
                    TextField("Site", text: $site, prompt: Text(prompt))
                }
                if platform.needsUsername {
                    TextField("Username", text: $username)
                }
                SecureField(platform.secretLabel, text: $secret)
                Text(platform.secretHelp + " It's stored in your Mac's Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Add \(platform.label)") {
                    let account = PublishAccount(platform: platform, site: site, username: username)
                    Keychain.set(secret.trimmingCharacters(in: .whitespacesAndNewlines), for: account.keychainKey)
                    prefs.publishAccounts.append(account)
                    site = ""; username = ""; secret = ""
                }
                .disabled(secret.isEmpty || (platform.sitePrompt != nil && site.isEmpty) || (platform.needsUsername && username.isEmpty))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: AI

struct AISettings: View {
    @Environment(AppModel.self) private var model
    @State private var key = ""
    @State private var hasKey = false

    var body: some View {
        @Bindable var prefs = model.prefs
        Form {
            Section {
                Toggle("Use the AI editor", isOn: $prefs.aiEnabled)
                Text("An editor, not a ghostwriter: it suggests line edits as margin notes, gives an editor's read, checks a book's continuity and drafts a synopsis of your book. It never writes your story.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Service") {
                Picker("Provider", selection: $prefs.aiProvider) {
                    ForEach(AIProvider.allCases) { Text($0.label).tag($0) }
                }
                TextField("Model", text: Binding(get: { prefs.aiModel }, set: { prefs.aiModels[prefs.aiProvider.rawValue] = $0 }),
                          prompt: Text(prefs.aiProvider.defaultModel))
                if prefs.aiProvider.needsKey {
                    HStack {
                        SecureField("API key", text: $key, prompt: Text(hasKey ? "Saved in your Keychain" : "Paste your key"))
                        Button("Save") {
                            Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: prefs.aiProvider.keychainKey)
                            key = ""
                            refresh()
                        }
                        .disabled(key.isEmpty)
                        if hasKey {
                            Button("Remove", role: .destructive) {
                                Keychain.delete(prefs.aiProvider.keychainKey)
                                refresh()
                            }
                        }
                    }
                }
                Text(prefs.aiProvider.keyHelp + (prefs.aiProvider.needsKey ? " Requests are billed to your account by the provider." : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Toggle("Show me what will be sent, every time", isOn: $prefs.aiConfirmRequests)
                Text("Nothing is sent until you ask for something. Each request carries only the passage, sheet or book it's about, straight to the provider you chose. Your key never leaves this Mac except to that provider.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onChange(of: model.prefs.aiProvider) { refresh() }
    }

    private func refresh() {
        hasKey = !(Keychain.get(model.prefs.aiProvider.keychainKey) ?? "").isEmpty
    }
}

/// Shows exactly what an AI request will send, before it goes.
struct AIConfirmSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let pending: AIPending
    @State private var dontAsk = false

    var body: some View {
        // Displaying a whole book would stall the sheet; the full text is still what's sent.
        let shown = pending.preview.count > 20_000
            ? String(pending.preview.prefix(20_000)) + "\n\n… and \((pending.preview.count - 20_000).formatted()) more characters"
            : pending.preview
        VStack(alignment: .leading, spacing: 14) {
            Label(pending.title, systemImage: "sparkle").font(.title2.weight(.bold))
            Text("This will be sent to \(pending.provider.label), model \(pending.model):")
                .foregroundStyle(.secondary)
            ScrollView {
                Text(shown)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 300)
            .background(.background.secondary, in: .rect(cornerRadius: 10))
            HStack {
                Toggle("Don't ask again", isOn: $dontAsk).toggleStyle(.checkbox)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Send") {
                    if dontAsk { model.prefs.aiConfirmRequests = false }
                    dismiss()
                    pending.send()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}

/// The AI editor's home in the inspector: what it can do, and its latest answer.
struct AIPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI Editor").font(.title3.weight(.semibold))
            if !model.prefs.aiEnabled {
                Text("Turn it on and add your key in Settings → AI. It's off until you do.")
                    .font(.callout).foregroundStyle(.secondary)
                SettingsLink { Text("Open Settings…") }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    action("Line Edit Selection", "text.badge.checkmark", "Suggestions as margin notes", model.aiLineEdit)
                    action("Editor's Read", "text.magnifyingglass", "What works, and what to revise", model.aiCritique)
                    action("Title Ideas", "textformat", "Ten titles in your voice", model.aiTitles)
                    action("Write Alt Text", "photo", "For images that have none", model.aiAltText)
                    if model.currentBook != nil {
                        Divider()
                        action("Check Continuity", "arrow.triangle.branch", "Contradictions across the whole book", model.aiContinuity)
                        action("Draft a Synopsis", "doc.plaintext", "From all your chapters", model.aiSynopsis)
                    }
                }
                .disabled(model.aiBusy != nil)
                if let busy = model.aiBusy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("\(busy)…").foregroundStyle(.secondary)
                    }
                }
            }
            if let result = model.aiResult {
                Divider()
                Text(result.title).font(.headline)
                Text(Self.render(result.markdown))
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result.markdown, forType: .string)
                    }
                    if result.saveIn != nil { Button("Save as Sheet") { model.saveAIResult() } }
                    Spacer()
                    Button("Clear") { model.aiResult = nil }
                }
                .controlSize(.small)
            }
        }
    }

    private func action(_ title: String, _ symbol: String, _ detail: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 18).foregroundStyle(model.prefs.theme.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Markdown answers with their line breaks kept (inline styling only).
    static func render(_ markdown: String) -> AttributedString {
        let tidy = markdown.replacingOccurrences(of: #"(?m)^#{1,6} +"#, with: "", options: .regularExpression)
        return (try? AttributedString(markdown: tidy, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(markdown)
    }
}
