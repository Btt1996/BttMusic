import SwiftData
import SwiftUI

struct PlaylistsView: View {
    @Environment(AudioEngine.self) private var audio
    @Environment(LibraryStore.self) private var library
    @Environment(\.modelContext) private var context
    @Binding var showPlayer: Bool

    @State private var newPlaylistName = ""
    @State private var showNewPlaylist = false

    var body: some View {
        NavigationStack {
            Group {
                if library.playlists.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(library.playlists, id: \.id) { playlist in
                            NavigationLink(value: playlist.id) {
                                PlaylistRow(playlist: playlist)
                            }
                        }
                        .onDelete { indexSet in
                            for i in indexSet { library.delete(library.playlists[i]) }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(BT.canvas)
            .navigationTitle("Playlists")
            .navigationDestination(for: UUID.self) { id in
                if let p = library.playlists.first(where: { $0.id == id }) {
                    PlaylistDetailView(showPlayer: $showPlayer, playlist: p)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewPlaylist = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New playlist", isPresented: $showNewPlaylist) {
                TextField("Name", text: $newPlaylistName)
                Button("Create") {
                    if !newPlaylistName.isEmpty {
                        library.createPlaylist(name: newPlaylistName)
                        newPlaylistName = ""
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(BT.textTertiary)
            Text("No playlists yet")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text("Create one, or let Smart Remix build an\nenergy-crafted sequence for you.")
                .font(.system(size: 14))
                .foregroundStyle(BT.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

struct PlaylistRow: View {
    let playlist: Playlist

    private var trackCount: Int {
        (playlist.tracks ?? []).count
    }

    var body: some View {
        HStack(spacing: 14) {
            PlaylistCover(playlist: playlist)
            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(trackCount) tracks")
                        .font(.system(size: 12))
                        .foregroundStyle(BT.textSecondary)
                    if playlist.isRemix {
                        Text("SMART REMIX")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(BT.gradient, in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct PlaylistCover: View {
    let playlist: Playlist

    var body: some View {
        if let first = playlist.tracks?.first {
            TrackArtwork(artworkData: first.artworkData, size: 52)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(BT.surfaceRaised)
                Image(systemName: "music.note")
                    .foregroundStyle(BT.textTertiary)
            }
            .frame(width: 52, height: 52)
        }
    }
}

struct PlaylistDetailView: View {
    @Environment(AudioEngine.self) private var audio
    @Environment(LibraryStore.self) private var library
    @Binding var showPlayer: Bool
    let playlist: Playlist

    @State private var showAddTracks = false

    var body: some View {
        List {
            if let tracks = playlist.tracks, !tracks.isEmpty {
                Button {
                    audio.play(tracks, index: 0)
                    showPlayer = true
                } label: {
                    HStack {
                        GradientPlayBadge(size: 44)
                        Text("Play all")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            }
            ForEach(playlist.tracks ?? [], id: \.id) { track in
                TrackRow(track: track, isCurrent: audio.currentTrack?.id == track.id)
                    .contentShape(.rect)
                    .onTapGesture {
                        if let list = playlist.tracks {
                            audio.play(list, index: list.firstIndex(where: { $0.id == track.id }) ?? 0)
                            showPlayer = true
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            library.removeFromPlaylist(playlist, track: track)
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BT.canvas)
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddTracks = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddTracks) {
            AddTracksSheet(playlist: playlist)
        }
    }

}

struct AddTracksSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let playlist: Playlist
    @State private var search = ""

    var filtered: [Track] {
        guard !search.isEmpty else { return library.tracks }
        return library.tracks.filter { $0.title.lowercased().contains(search.lowercased()) || $0.artist.lowercased().contains(search.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.id) { track in
                Button {
                    library.addToPlaylist(playlist, track: track)
                } label: {
                    HStack {
                        TrackArtwork(artworkData: track.artworkData, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                            Text(track.artist).font(.system(size: 12)).foregroundStyle(BT.textSecondary).lineLimit(1)
                        }
                        Spacer()
                        if playlist.tracks?.contains(where: { $0.id == track.id }) == true {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(BT.magenta)
                        }
                    }
                }
            }
            .searchable(text: $search)
            .scrollContentBackground(.hidden)
            .background(BT.canvas)
            .navigationTitle("Add tracks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
