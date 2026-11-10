import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(AudioEngine.self) private var audio
    @Environment(LibraryStore.self) private var library
    @Environment(\.modelContext) private var context
    @Binding var showPlayer: Bool

    @State private var searchText = ""
    @State private var showImporter = false
    @State private var analyzingID: UUID?

    var filtered: [Track] {
        guard !searchText.isEmpty else { return library.tracks }
        let q = searchText.lowercased()
        return library.tracks.filter {
            $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q) || $0.album.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.tracks.isEmpty {
                    emptyState
                } else {
                    trackList
                }
            }
            .background(BT.canvas)
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Songs, artists, albums")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    var imported = 0
                    for url in urls {
                        if library.importFile(at: url, source: .files) != nil { imported += 1 }
                    }
                    if imported > 0 { library.statusMessage = "Imported \(imported) track\(imported == 1 ? "" : "s")" }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image("BTLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .opacity(0.85)
            Text("Your music lives here")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Import audio files from Files, sync from\nTelegram, or acquire freely licensed audio\nin Get Music.")
                .font(.system(size: 14))
                .foregroundStyle(BT.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                showImporter = true
            } label: {
                Label("Import from Files", systemImage: "folder.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(BT.gradient, in: Capsule())
            }
            .padding(.top, 6)
        }
        .padding(40)
    }

    private var trackList: some View {
        List {
            if let message = library.statusMessage {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BT.magenta)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 0, trailing: 16))
            }
            ForEach(filtered, id: \.id) { track in
                TrackRow(track: track, isCurrent: audio.currentTrack?.id == track.id, isAnalyzing: analyzingID == track.id)
                    .contentShape(.rect)
                    .onTapGesture {
                        audio.play(filtered, index: filtered.firstIndex(where: { $0.id == track.id }) ?? 0)
                        showPlayer = true
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            library.delete(track)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            Task {
                                analyzingID = track.id
                                await library.analyze(track)
                                analyzingID = nil
                            }
                        } label: {
                            Label("Analyze", systemImage: "waveform")
                        }
                        .tint(BT.purple)
                    }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

struct TrackRow: View {
    let track: Track
    var isCurrent = false
    var isAnalyzing = false

    var body: some View {
        HStack(spacing: 12) {
            TrackArtwork(artworkData: track.artworkData, size: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(isCurrent ? AnyShapeStyle(BT.gradient) : AnyShapeStyle(Color.white))
                    .lineLimit(1)
                Text("\(track.artist) · \(sourceLabel)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(BT.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if isAnalyzing {
                ProgressView()
                    .tint(BT.magenta)
            } else if track.analyzed {
                Text(track.bpm > 0 ? "\(Int(track.bpm))" : "—")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(BT.textTertiary)
            }
            Text(Self.format(track.duration))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(BT.textTertiary)
        }
        .padding(.vertical, 4)
    }

    private var sourceLabel: String {
        switch track.source {
        case .files: track.album.isEmpty ? "Files" : track.album
        case .telegram: "Telegram · \(track.album.isEmpty ? "bot" : track.album)"
        case .x2: "X2 · \(track.artist == "Unknown Artist" ? "free source" : track.album)"
        }
    }

    static func format(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
