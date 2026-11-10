import SwiftUI

// "Get Music" hub: Telegram sync, X1 metadata, X2 audio, YouTube — independent screens.
struct AcquireView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AcquisitionCard(
                        icon: "paperplane.circle.fill",
                        title: "Telegram Sync",
                        subtitle: "Connect your bot, scan recent updates, import audio from your chats and channels. Token stays in the Keychain.",
                        destination: AnyView(TelegramView())
                    )
                    AcquisitionCard(
                        icon: "text.badge.checkmark",
                        title: "X1 · Identify",
                        subtitle: "Paste a Spotify playlist, album or track link. Imports titles, artists and artwork metadata — never audio.",
                        destination: AnyView(X1View())
                    )
                    AcquisitionCard(
                        icon: "arrow.down.circle.fill",
                        title: "X2 · Acquire",
                        subtitle: "Find and download freely licensed audio (Internet Archive, Jamendo) to complete your library offline.",
                        destination: AnyView(X2View())
                    )
                    if BTTheme.shared.flag("youtube") {
                        AcquisitionCard(
                            icon: "play.rectangle.fill",
                            title: "YouTube Import",
                            subtitle: "Send YouTube links to your own yt-dlp-compatible server and pull the audio in. Share the link from Safari to start.",
                            destination: AnyView(YouTubeView())
                        )
                    }
                }
                .padding(16)
            }
            .background(BT.canvas)
            .navigationTitle("Get Music")
        }
    }
}

struct AcquisitionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let destination: AnyView

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundStyle(BT.gradient)
                    .frame(width: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(BT.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(BT.textTertiary)
            }
            .padding(18)
            .btCard()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Telegram
struct TelegramView: View {
    @Environment(TelegramService.self) private var telegram
    @Environment(LibraryStore.self) private var library

    @State private var tokenInput = ""
    @State private var importing: Set<String> = []

    var body: some View {
        @Bindable var telegram = telegram
        ScrollView {
            VStack(spacing: 16) {
                if telegram.connected {
                    connectedHeader
                } else {
                    connectCard
                }
                if case .downloading(let name, let progress) = telegram.phase {
                    downloadProgressCard(name: name, progress: progress)
                }
                if case .failed(let message) = telegram.phase {
                    errorCard(message)
                }
                if telegram.connected {
                    filesCard
                }
                complianceNote
            }
            .padding(16)
        }
        .background(BT.canvas)
        .navigationTitle("Telegram")
        .onAppear {
            if telegram.connected, telegram.discovered.isEmpty {
                Task { await telegram.scan() }
            }
        }
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Connect your Telegram bot", systemImage: "paperplane.fill")
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text("Create a bot with @BotFather, paste its token here. Send MP3s to your bot in a private chat, then scan to import them. The token is stored in the iOS Keychain only.")
                .font(.system(size: 13))
                .foregroundStyle(BT.textSecondary)
            SecureField("123456:ABC-DEF...", text: $tokenInput)
                .font(.system(size: 14, design: .monospaced))
                .textFieldStyle(.plain)
                .padding(12)
                .background(BT.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
            Button {
                Task { await telegram.connect(token: tokenInput) }
            } label: {
                HStack {
                    if case .connecting = telegram.phase {
                        ProgressView().tint(.white)
                    }
                    Text("Connect Bot")
                        .font(.system(size: 15, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.white)
                .padding(.vertical, 13)
                .background(BT.gradient, in: Capsule())
            }
            .disabled(tokenInput.isEmpty)
        }
        .padding(18)
        .btCard()
    }

    private var connectedHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(telegram.botUsername.map { "Connected to @\($0)" } ?? "Bot connected")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Send audio to your bot, then refresh.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(BT.textSecondary)
            }
            Spacer()
            Button {
                Task { await telegram.scan() }
            } label: {
                if case .scanning = telegram.phase {
                    ProgressView().tint(BT.magenta)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(BT.magenta)
                }
            }
            .disabled({
                if case .scanning = telegram.phase { return true }
                return false
            }())
        }
        .padding(16)
        .btCard()
    }

    private var filesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bot Audio Files (\(telegram.discovered.count))")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(BT.textSecondary)
            if telegram.discovered.isEmpty, case .done(let msg) = telegram.phase {
                Text(msg).font(.system(size: 13)).foregroundStyle(BT.textTertiary)
            }
            ForEach(telegram.discovered) { audio in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(BT.gradient.opacity(0.18))
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(BT.magenta)
                    }
                    .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(audio.title ?? audio.fileName ?? "Audio")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("\(audio.performer ?? audio.chatTitle) · \(LibraryStore.formattedBytes(audio.fileSize))")
                            .font(.system(size: 12))
                            .foregroundStyle(BT.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if importing.contains(audio.id) {
                        ProgressView().tint(BT.magenta)
                    } else {
                        Button {
                            importing.insert(audio.id)
                            Task {
                                await telegram.download(audio, into: library)
                                importing.remove(audio.id)
                            }
                        } label: {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(BT.gradient)
                        }
                    }
                }
            }
        }
        .padding(18)
        .btCard()
    }

    private func downloadProgressCard(name: String, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Downloading \(name)")
                .font(.system(size: 13, weight: .semibold))
            ProgressView(value: progress).tint(BT.magenta)
        }
        .padding(16)
        .btCard()
    }

    private func errorCard(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(BT.red)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .btCard()
    }

    private var complianceNote: some View {
        Text("The Bot API only shows audio sent to your own bot — a stable, compliant official method. Bots cannot read arbitrary public channels unless they are admins there. Old app's curated channels like @ElectronicMusicHub therefore can't be scraped keylessly; forward their audio to your bot instead.")
            .font(.system(size: 11.5))
            .foregroundStyle(BT.textTertiary)
            .padding(.horizontal, 8)
    }
}

// MARK: - X1
struct X1View: View {
    @Environment(X1SpotifyService.self) private var x1
    @Environment(LibraryStore.self) private var library

    @State private var link = ""
    @State private var showResults = false

    var body: some View {
        @Bindable var x1 = x1
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Spotify metadata import", systemImage: "text.badge.checkmark")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("X1 imports METADATA ONLY: title, artist, artwork references. No audio is downloaded here — use X2 for that.")
                        .font(.system(size: 13))
                        .foregroundStyle(BT.textSecondary)
                    TextField("https://open.spotify.com/playlist/...", text: $link)
                        .font(.system(size: 13.5, design: .monospaced))
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(BT.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button {
                        Task { await x1.importCollection(from: link) }
                    } label: {
                        HStack {
                            if case .importing = x1.phase { ProgressView().tint(.white) }
                            Text("Import Metadata")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white)
                        .padding(.vertical, 13)
                        .background(BT.gradient, in: Capsule())
                    }
                    .disabled(link.isEmpty)
                }
                .padding(18)
                .btCard()

                switch x1.phase {
                case .done:
                    if case .done(let msg) = x1.phase {
                        Text(msg)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(BT.magenta)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .btCard()
                    }
                case .failed(let msg):
                    Text(msg)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BT.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .btCard()
                default:
                    EmptyView()
                }

                if let collection = x1.lastImport {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(collection.name)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("\(collection.tracks.count) tracks · \(collection.kind)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(BT.textSecondary)
                            }
                            Spacer()
                            Button {
                                let p = x1.saveAsPlaylist(collection, in: library)
                                library.statusMessage = "Saved \"\(p.name)\" with \(p.tracks?.count ?? 0) local matches"
                            } label: {
                                Text("Save as Playlist")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(BT.gradient, in: Capsule())
                            }
                        }
                        ForEach(collection.tracks.prefix(30)) { t in
                            HStack {
                                Image(systemName: X1SpotifyService.match(t, in: library) != nil ? "checkmark.circle.fill" : "circle.dashed")
                                    .font(.system(size: 13))
                                    .foregroundStyle(X1SpotifyService.match(t, in: library) != nil ? BT.magenta : BT.textTertiary)
                                    .frame(width: 18)
                                Text(t.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Spacer()
                                Text(t.artist)
                                    .font(.system(size: 12))
                                    .foregroundStyle(BT.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        if collection.tracks.count > 30 {
                            Text("+ \(collection.tracks.count - 30) more")
                                .font(.system(size: 12))
                                .foregroundStyle(BT.textTertiary)
                        }
                    }
                    .padding(18)
                    .btCard()
                }

                Text("Keyless import reads public Spotify embed pages. Private playlists require the link owner to make them public. Duplicate tracks already in your library are marked with a filled circle.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(BT.textTertiary)
                    .padding(.horizontal, 8)
            }
            .padding(16)
        }
        .background(BT.canvas)
        .navigationTitle("X1 · Identify")
    }
}

// MARK: - X2
struct X2View: View {
    @Environment(X2AcquisitionService.self) private var x2
    @Environment(X1SpotifyService.self) private var x1
    @Environment(LibraryStore.self) private var library

    @State private var query = ""
    @State private var acquiring: Set<String> = []

    var body: some View {
        @Bindable var x2 = x2
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Freely licensed audio", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("X2 acquires real audio files from authorized free sources: the Internet Archive and Jamendo (add your own Jamendo client ID in Settings). No DRM bypassing, no unauthorized extraction.")
                        .font(.system(size: 13))
                        .foregroundStyle(BT.textSecondary)
                    HStack(spacing: 10) {
                        TextField("Search free audio, e.g. \"jazz piano\"", text: $query)
                            .font(.system(size: 14))
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(BT.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                            .onSubmit { Task { await x2.search(query) } }
                        Button {
                            Task { await x2.search(query) }
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(BT.gradient, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(18)
                .btCard()

                switch x2.phase {
                case .searching:
                    HStack { Spacer(); ProgressView().tint(BT.magenta); Spacer() }
                case .results(let msg), .done(let msg):
                    Text(msg)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BT.magenta)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .btCard()
                case .failed(let msg):
                    Text(msg)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BT.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .btCard()
                default:
                    EmptyView()
                }

                ForEach(x2.results) { result in
                    HStack(spacing: 12) {
                        TrackArtwork(artworkData: nil, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text("\(result.artist) · \(result.provider)")
                                .font(.system(size: 12))
                                .foregroundStyle(BT.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if acquiring.contains(result.id) {
                            ProgressView().tint(BT.magenta)
                        } else {
                            Button {
                                acquiring.insert(result.id)
                                Task {
                                    await x2.acquire(result, withMetadata: nil, into: library)
                                    acquiring.remove(result.id)
                                }
                            } label: {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(BT.gradient)
                            }
                        }
                    }
                    .padding(12)
                    .btCard()
                }
            }
            .padding(16)
        }
        .background(BT.canvas)
        .navigationTitle("X2 · Acquire")
    }
}
