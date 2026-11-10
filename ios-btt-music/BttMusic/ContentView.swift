import SwiftUI

enum AppTab: String, CaseIterable {
    case library = "Library"
    case playlists = "Playlists"
    case acquire = "Get Music"
    case remix = "Remix"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .library: "music.note.list"
        case .playlists: "rectangle.stack"
        case .acquire: "arrow.down.circle"
        case .remix: "waveform.badge.plus"
        case .settings: "gearshape"
        }
    }
}

struct ContentView: View {
    @Environment(AudioEngine.self) private var audio
    @State private var tab: AppTab = .library
    @State private var showPlayer = false
    @State private var youtubeImportURL: String?
    @State private var showYouTubeImport = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                LibraryView(showPlayer: $showPlayer)
                    .tabItem { Label(AppTab.library.rawValue, systemImage: AppTab.library.icon) }
                    .tag(AppTab.library)
                PlaylistsView(showPlayer: $showPlayer)
                    .tabItem { Label(AppTab.playlists.rawValue, systemImage: AppTab.playlists.icon) }
                    .tag(AppTab.playlists)
                AcquireView()
                    .tabItem { Label(AppTab.acquire.rawValue, systemImage: AppTab.acquire.icon) }
                    .tag(AppTab.acquire)
                RemixView(showPlayer: $showPlayer)
                    .tabItem { Label(AppTab.remix.rawValue, systemImage: AppTab.remix.icon) }
                    .tag(AppTab.remix)
                SettingsView()
                    .tabItem { Label(AppTab.settings.rawValue, systemImage: AppTab.settings.icon) }
                    .tag(AppTab.settings)
            }
            .tint(BT.magenta)

            if audio.currentTrack != nil {
                MiniPlayerBar(showPlayer: $showPlayer)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: audio.currentTrack != nil)
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView()
        }
        // Share Extension hand-off: bttmu://youtube-import?url=...
        .onOpenURL { url in
            guard url.scheme == "bttmu", url.host == "youtube-import" else { return }
            let query = url.query(percentEncoded: false) ?? ""
            let link = query.hasPrefix("url=") ? String(query.dropFirst(4)) : query
            if !link.isEmpty {
                youtubeImportURL = link.removingPercentEncoding ?? link
                tab = .acquire
                showYouTubeImport = true
            }
        }
        .sheet(isPresented: $showYouTubeImport) {
            NavigationStack {
                YouTubeView(initialURL: youtubeImportURL ?? "")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showYouTubeImport = false }
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Mini player
struct MiniPlayerBar: View {
    @Environment(AudioEngine.self) private var audio
    @Binding var showPlayer: Bool

    var body: some View {
        Button {
            showPlayer = true
        } label: {
            HStack(spacing: 12) {
                TrackArtwork(artworkData: audio.currentTrack?.artworkData, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(audio.currentTrack?.title ?? "")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(audio.currentTrack?.artist ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(BT.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    audio.togglePlayPause()
                } label: {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Button {
                    audio.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(BT.textSecondary)
                        .frame(width: 36, height: 40)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 20)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(BT.hairline, lineWidth: 1)
            )
            .foregroundStyle(.black.opacity(0.001))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: audio.isPlaying)
    }
}
