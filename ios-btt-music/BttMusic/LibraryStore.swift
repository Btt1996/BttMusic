import AVFoundation
import Foundation
import SwiftData
import UIKit

@MainActor
@Observable
final class LibraryStore {
    private(set) var tracks: [Track] = []
    private(set) var playlists: [Playlist] = []
    private var modelContext: ModelContext?
    var statusMessage: String?

    func bind(context: ModelContext) {
        self.modelContext = context
        refresh()
    }

    func refresh() {
        guard let context = modelContext else { return }
        let trackRequest = FetchDescriptor<Track>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])
        tracks = (try? context.fetch(trackRequest)) ?? []
        let playlistRequest = FetchDescriptor<Playlist>(sortBy: [SortDescriptor(\.dateCreated, order: .reverse)])
        playlists = (try? context.fetch(playlistRequest)) ?? []
    }

    // MARK: - Import
    @discardableResult
    func importFile(at url: URL, source: TrackSource, sourceID: String = "") -> Track? {
        guard let context = modelContext else { return nil }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let fileManager = FileManager.default
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
        let destName = UUID().uuidString + "." + ext
        let dest = Track.tracksDirectory.appendingPathComponent(destName)
        do {
            try fileManager.copyItem(at: url, to: dest)
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
            return nil
        }

        let size = (try? fileManager.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
        let meta = readMetadata(of: dest)

        // Duplicate detection: same sourceID, or same title+artist+duration.
        if !sourceID.isEmpty, tracks.contains(where: { $0.sourceID == sourceID && $0.source == source }) {
            try? fileManager.removeItem(at: dest)
            statusMessage = "Skipped duplicate: \(meta.title)"
            return nil
        }
        if tracks.contains(where: {
            $0.title.lowercased() == meta.title.lowercased()
                && $0.artist.lowercased() == meta.artist.lowercased()
                && abs($0.duration - meta.duration) < 1.5
        }) {
            try? fileManager.removeItem(at: dest)
            statusMessage = "Skipped duplicate: \(meta.title)"
            return nil
        }

        let track = Track(
            title: meta.title, artist: meta.artist, album: meta.album,
            duration: meta.duration, fileName: destName, fileSize: size,
            artworkData: meta.artworkData, source: source, sourceID: sourceID
        )
        context.insert(track)
        refresh()
        return track
    }

    struct Metadata {
        var title: String
        var artist: String
        var album: String
        var duration: TimeInterval
        var artworkData: Data?
    }

    private func readMetadata(of url: URL) -> Metadata {
        let asset = AVURLAsset(url: url)
        var title = url.deletingPathExtension().lastPathComponent
        var artist = "Unknown Artist"
        var album = ""
        var duration: TimeInterval = 0
        var artwork: Data?

        for item in asset.commonMetadata {   // synchronous legacy API; deprecated but reliable
            switch item.commonKey {
            case .commonKeyTitle: title = item.stringValue ?? title
            case .commonKeyArtist: artist = item.stringValue ?? artist
            case .commonKeyAlbumName: album = item.stringValue ?? album
            case .commonKeyArtwork: artwork = item.dataValue ?? artwork
            default: break
            }
        }
        let d = asset.duration.seconds
        if !d.isNaN && !d.isInfinite { duration = d }
        return Metadata(title: title, artist: artist, album: album, duration: duration, artworkData: artwork)
    }

    // MARK: - Storage
    struct StorageStats {
        var totalBytes: Int64 = 0
        var count: Int = 0
        var bySource: [TrackSource: Int64] = [:]
        var missingFiles: Int = 0
    }

    var storageStats: StorageStats {
        var stats = StorageStats()
        for t in tracks {
            stats.totalBytes += t.fileSize
            stats.count += 1
            stats.bySource[t.source, default: 0] += t.fileSize
            if !t.fileExists { stats.missingFiles += 1 }
        }
        return stats
    }

    static func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Duplicates
    func duplicateGroups() -> [[Track]] {
        var buckets: [String: [Track]] = [:]
        for t in tracks where t.fileExists {
            let key = "\(t.title.lowercased())|\(t.artist.lowercased())|\(Int(t.duration))"
            buckets[key, default: []].append(t)
        }
        return buckets.values.filter { $0.count > 1 }
    }

    @discardableResult
    func removeDuplicates(keepingNewest: Bool = false) -> Int {
        var removed = 0
        for group in duplicateGroups() {
            let sorted = keepingNewest
                ? group.sorted { $0.dateAdded > $1.dateAdded }
                : group.sorted { $0.playCount > $1.playCount }
            for loser in sorted.dropFirst() { delete(loser); removed += 1 }
        }
        refresh()
        return removed
    }

    // MARK: - Delete
    func delete(_ track: Track) {
        try? FileManager.default.removeItem(at: track.fileURL)
        modelContext?.delete(track)
        refresh()
    }

    func delete(_ playlist: Playlist) {
        modelContext?.delete(playlist)
        refresh()
    }

    // MARK: - Playlists
    @discardableResult
    func createPlaylist(name: String, tracks: [Track] = [], isRemix: Bool = false) -> Playlist {
        let p = Playlist(name: name, isRemix: isRemix)
        p.tracks = tracks
        modelContext?.insert(p)
        refresh()
        return p
    }

    func addToPlaylist(_ playlist: Playlist, track: Track) -> Bool {
        var list = playlist.tracks ?? []
        if list.contains(where: { $0.id == track.id }) { return false }
        list.append(track)
        playlist.tracks = list
        refresh()
        return true
    }

    func removeFromPlaylist(_ playlist: Playlist, track: Track) {
        var list = playlist.tracks ?? []
        list.removeAll { $0.id == track.id }
        playlist.tracks = list
        refresh()
    }

    // MARK: - Analysis
    func analyze(_ track: Track) async {
        let result = await RemixAnalyzer.analyze(fileURL: track.fileURL)
        track.bpm = result.bpm
        track.energy = result.energy
        track.brightness = result.brightness
        track.analyzed = true
        statusMessage = "Analyzed \(track.title): \(Int(result.bpm)) BPM"
    }

    var analysisProgress: (done: Int, total: Int) {
        (tracks.filter(\.analyzed).count, tracks.count)
    }

    // MARK: - Export (migration out)
    func libraryExportJSON() -> Data? {
        struct Exported: Codable {
            var title, artist, album, fileName, source: String
            var duration: TimeInterval; var fileSize: Int64; var bpm: Double
        }
        let list = tracks.map {
            Exported(title: $0.title, artist: $0.artist, album: $0.album, fileName: $0.fileName,
                     source: $0.sourceRaw, duration: $0.duration, fileSize: $0.fileSize, bpm: $0.bpm)
        }
        return try? JSONEncoder().encode(list)
    }
}
