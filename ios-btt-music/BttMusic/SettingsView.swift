import SwiftUI

struct SettingsView: View {
    @Environment(UpdateService.self) private var updates
    @Environment(LibraryStore.self) private var library
    @Environment(TelegramService.self) private var telegram
    @State private var theme = BTTheme.shared

    var body: some View {
        @Bindable var updates = updates
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    updatesCard
                    themeCard
                    backupCard
                    storageCard
                    telegramCard
                    aboutCard
                }
                .padding(16)
            }
            .background(BT.canvas)
            .navigationTitle("Settings")
        }
    }

    // MARK: - Theme (remote theming)
    private var themeCard: some View {
        @Bindable var theme = theme
        return VStack(alignment: .leading, spacing: 12) {
            Label("Theme", systemImage: "paintpalette.fill")
                .font(.system(size: 16, weight: .bold, design: .rounded))
            HStack(spacing: 10) {
                Circle().fill(BT.purple).frame(width: 18, height: 18)
                Circle().fill(BT.magenta).frame(width: 18, height: 18)
                Circle().fill(BT.red).frame(width: 18, height: 18)
                Text(theme.json.name)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            TextField("https://raw.githubusercontent.com/…/theme.json", text: $theme.remoteURL)
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.plain)
                .padding(12)
                .background(BT.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            HStack(spacing: 10) {
                Button {
                    Task { await theme.fetchRemote() }
                } label: {
                    Text("Apply")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(BT.gradient, in: Capsule())
                }
                Button {
                    theme.resetToDefault()
                } label: {
                    Text("Reset")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(BT.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(BT.surfaceRaised, in: Capsule())
                }
            }
            if let status = theme.status {
                Text(status)
                    .font(.system(size: 12.5))
                    .foregroundStyle(BT.magenta)
            }
            Text("Colors, corner radii, typography character and which acquisition cards appear are all theme-controlled. Point the app at a theme JSON hosted on GitHub or any CDN and apply it — no reinstall needed.")
                .font(.system(size: 11.5))
                .foregroundStyle(BT.textTertiary)
        }
        .padding(18)
        .btCard()
    }

    // MARK: - Backup & restore
    private var backupCard: some View {
        NavigationLink {
            RestoreView()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "externaldrive.badge.timemachine")
                    .font(.system(size: 26))
                    .foregroundStyle(BT.gradient)
                    .frame(width: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Backup & Restore")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Export everything as JSON; restore with a preview and duplicate matching")
                        .font(.system(size: 12.5))
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

    // MARK: - Updates (GitHub)
    private var updatesCard: some View {
        @Bindable var updates = updates
        return VStack(alignment: .leading, spacing: 12) {
            Label("Updates", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 16, weight: .bold, design: .rounded))
            HStack {
                Text("Installed version")
                    .font(.system(size: 13.5))
                    .foregroundStyle(BT.textSecondary)
                Spacer()
                Text(UpdateService.currentVersion)
                    .font(.system(size: 13.5, weight: .bold, design: .monospaced))
            }
            TextField("owner/repo", text: $updates.repoPath)
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.plain)
                .padding(12)
                .background(BT.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button {
                Task { await updates.check() }
            } label: {
                HStack {
                    if case .checking = updates.status { ProgressView().tint(.white) }
                    Text("Check for Updates")
                        .font(.system(size: 14, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.white)
                .padding(.vertical, 12)
                .background(BT.gradient, in: Capsule())
            }
            switch updates.status {
            case .upToDate(let msg):
                Label(msg, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(BT.magenta)
            case .available(let release):
                VStack(alignment: .leading, spacing: 8) {
                    Label("Update available: \(release.version)", systemImage: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(BT.magenta)
                    Text(release.notes)
                        .font(.system(size: 12.5))
                        .foregroundStyle(BT.textSecondary)
                        .lineLimit(8)
                    if let url = release.htmlURL {
                        Link("Open release on GitHub", destination: url)
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
            case .failed(let msg):
                Text(msg)
                    .font(.system(size: 13))
                    .foregroundStyle(BT.red)
            case .idle, .checking:
                EmptyView()
            }
            Text("An iOS app cannot silently replace its own executable. New versions install through TestFlight, the App Store, or your sideloading workflow — the app tells you what's new and where to get it.")
                .font(.system(size: 11.5))
                .foregroundStyle(BT.textTertiary)
        }
        .padding(18)
        .btCard()
    }

    // MARK: - Storage
    private var storageCard: some View {
        NavigationLink {
            StorageDashboardView()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(BT.gradient)
                    .frame(width: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Storage & Duplicates")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(library.tracks.count) tracks · \(LibraryStore.formattedBytes(library.storageStats.totalBytes)) offline")
                        .font(.system(size: 12.5))
                        .foregroundStyle(BT.textSecondary)
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

    // MARK: - Telegram quick access
    private var telegramCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "paperplane.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(BT.gradient)
                .frame(width: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("Telegram bot")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(telegram.connected ? "Connected · token in Keychain" : "Not connected")
                    .font(.system(size: 12.5))
                    .foregroundStyle(BT.textSecondary)
            }
            Spacer()
            if telegram.connected {
                Button(role: .destructive) {
                    telegram.disconnect()
                } label: {
                    Text("Disconnect")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(BT.red)
                }
            }
        }
        .padding(18)
        .btCard()
    }

    // MARK: - About
    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image("BTLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Btt Music (BTmu)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("By Taboubi Ahmed")
                        .font(.system(size: 12.5))
                        .foregroundStyle(BT.textSecondary)
                }
                Spacer()
            }
            Text("Native SwiftUI rebuild. Offline-first music engine on AVAudioEngine, Telegram Bot API sync, X1 metadata identification, X2 freely-licensed audio acquisition, YouTube import through your own yt-dlp server, on-device Smart Remix analysis, remote theming, full JSON backup & restore, and GitHub update checks.")
                .font(.system(size: 12.5))
                .foregroundStyle(BT.textSecondary)
        }
        .padding(18)
        .btCard()
    }
}

// MARK: - Storage dashboard
struct StorageDashboardView: View {
    @Environment(LibraryStore.self) private var library
    @State private var confirmDuplicates = false
    @State private var removedCount = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                usageCard
                breakdownCard
                duplicatesCard
                exportCard
                audioNote
            }
            .padding(16)
        }
        .background(BT.canvas)
        .navigationTitle("Storage")
        .alert("Remove duplicates?", isPresented: $confirmDuplicates) {
            Button("Remove", role: .destructive) {
                removedCount = library.removeDuplicates()
                library.statusMessage = "Removed \(removedCount) duplicate\(removedCount == 1 ? "" : "s")"
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your least-played copy in each duplicate group will be removed. Originals are never touched without this confirmation.")
        }
    }

    private var usageCard: some View {
        let stats = library.storageStats
        return VStack(alignment: .leading, spacing: 12) {
            Text("Offline library")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            HStack(alignment: .firstTextBaseline) {
                Text(LibraryStore.formattedBytes(stats.totalBytes))
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(BT.gradient)
                Spacer()
                Text("\(stats.count) tracks")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(BT.textSecondary)
            }
            if stats.missingFiles > 0 {
                Label("\(stats.missingFiles) entries have missing files — remove them in the Library tab.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(BT.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .btCard()
    }

    private var breakdownCard: some View {
        let stats = library.storageStats
        let total = max(1, stats.totalBytes)
        return VStack(alignment: .leading, spacing: 12) {
            Text("By source")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            ForEach([TrackSource.files, .telegram, .x2], id: \.self) { source in
                let bytes = stats.bySource[source] ?? 0
                HStack {
                    Text(sourceLabel(source))
                        .font(.system(size: 13.5))
                    Spacer()
                    Text(LibraryStore.formattedBytes(bytes))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(BT.textSecondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.08))
                        Capsule().fill(BT.gradient)
                            .frame(width: geo.size.width * CGFloat(bytes) / CGFloat(total))
                    }
                }
                .frame(height: 5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .btCard()
    }

    private func sourceLabel(_ s: TrackSource) -> String {
        switch s {
        case .files: "Files import"
        case .telegram: "Telegram"
        case .x2: "X2 acquisition"
        }
    }

    private var duplicatesCard: some View {
        let groups = library.duplicateGroups()
        return VStack(alignment: .leading, spacing: 12) {
            Text("Duplicates")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            if groups.isEmpty {
                Text("No duplicates detected (title + artist + duration matching).")
                    .font(.system(size: 13))
                    .foregroundStyle(BT.textSecondary)
            } else {
                ForEach(Array(groups.prefix(8).enumerated()), id: \.offset) { _, group in
                    Text("\(group.count)×  \(group[0].title) — \(group[0].artist)")
                        .font(.system(size: 13))
                        .foregroundStyle(BT.textSecondary)
                        .lineLimit(1)
                }
                Button {
                    confirmDuplicates = true
                } label: {
                    Text("Remove \(groups.reduce(0) { $0 + $1.count - 1 }) duplicates")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(BT.gradient, in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .btCard()
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text("Export your ENTIRE library — track metadata plus playlist structure — as a JSON backup. iOS sandboxes prevent reading another app's private data, so this export + Restore is the migration path between installs. Audio files themselves are not included.")
                .font(.system(size: 12.5))
                .foregroundStyle(BT.textSecondary)
            if let data = BackupService.exportBackup(tracks: library.tracks, playlists: library.playlists) {
                ShareLink(item: data, preview: SharePreview("Btt Music backup", image: Image("BTLogo"))) {
                    Label("Export full backup JSON", systemImage: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(BT.magenta)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(BT.magenta.opacity(0.14), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .btCard()
    }

    private var audioNote: some View {
        Text("Audio compression (MP3/AAC/Opus bitrate) determines sound quality and file size; container formats (M4A vs MP3) only wrap the audio. The app detects formats on import and never transcodes automatically — conversion without consent can permanently damage quality.")
            .font(.system(size: 11.5))
            .foregroundStyle(BT.textTertiary)
            .padding(.horizontal, 8)
    }
}
