import Foundation
import SwiftData

// Full-library backup: JSON with track metadata + playlist structure.
// Playlists reference tracks by "title|artist" keys so a restore can match
// them to existing tracks. The backup never contains audio files — restored
// entries whose audio is missing are flagged, never silently dropped.
@MainActor
enum BackupService {
    struct Backup: Codable {
        var app: String = "btmu"
        var schema: Int = 1
        var exportedAt: Date = Date()
        var tracks: [BackupTrack]
        var playlists: [BackupPlaylist]
    }

    struct BackupTrack: Codable {
        var title: String
        var artist: String
        var album: String
        var duration: TimeInterval
        var fileName: String
        var fileSize: Int64
        var source: String
        var sourceID: String
        var bpm: Double
        var playCount: Int
        var key: String { "\(title.lowercased())|\(artist.lowercased())" }
    }

    struct BackupPlaylist: Codable {
        var name: String
        var isRemix: Bool
        var trackKeys: [String]
    }

    // MARK: - Export
    static func exportBackup(tracks: [Track], playlists: [Playlist]) -> Data? {
        let backup = Backup(
            tracks: tracks.map {
                BackupTrack(title: $0.title, artist: $0.artist, album: $0.album,
                            duration: $0.duration, fileName: $0.fileName, fileSize: $0.fileSize,
                            source: $0.sourceRaw, sourceID: $0.sourceID, bpm: $0.bpm,
                            playCount: $0.playCount)
            },
            playlists: playlists.map { p in
                BackupPlaylist(
                    name: p.name, isRemix: p.isRemix,
                    trackKeys: (p.tracks ?? []).map { "\($0.title.lowercased())|\($0.artist.lowercased())" }
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(backup)
    }

    // MARK: - Restore
    struct RestoreReport {
        var matchedExisting = 0       // track already in library, left untouched
        var restoredMetadata = 0      // entry created; audio file missing (metadata-only)
        var restoredWithFile = 0      // entry created; the referenced file still exists
        var playlistsCreated = 0
        var playlistsSkipped = 0      // playlist with that name already existed
        var skippedEntries = 0        // malformed entries
        var summary: String {
            var lines: [String] = []
            lines.append("\(matchedExisting) track\(matchedExisting == 1 ? "" : "s") already in your library (untouched)")
            if restoredWithFile > 0 { lines.append("\(restoredWithFile) restored with audio file") }
            if restoredMetadata > 0 { lines.append("\(restoredMetadata) restored as metadata-only (audio file not on this device)") }
            lines.append("\(playlistsCreated) playlist\(playlistsCreated == 1 ? "" : "s") created, \(playlistsSkipped) skipped (name exists)")
            if skippedEntries > 0 { lines.append("\(skippedEntries) malformed entries skipped") }
            return lines.joined(separator: "\n")
        }
    }

    static func decodeBackup(from data: Data) -> Backup? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Backup.self, from: data)
    }

    // Never overwrites existing tracks: a match on title+artist (case-insensitive)
    // is left exactly as it is.
    static func restore(_ backup: Backup, into library: LibraryStore, context: ModelContext) -> RestoreReport {
        var report = RestoreReport()
        let existing = library.tracks
        var byKey: [String: Track] = [:]
        for t in existing { byKey["\(t.title.lowercased())|\(t.artist.lowercased())"] = t }

        var restoredTracks: [Track] = []
        for entry in backup.tracks {
            if entry.title.isEmpty || entry.artist.isEmpty { report.skippedEntries += 1; continue }
            if let match = byKey[entry.key] {
                report.matchedExisting += 1
                restoredTracks.append(match)
                continue
            }
            let fileExists = FileManager.default.fileExists(
                atPath: Track.tracksDirectory.appendingPathComponent(entry.fileName).path)
            let track = Track(
                title: entry.title, artist: entry.artist, album: entry.album,
                duration: entry.duration, fileName: entry.fileName, fileSize: entry.fileSize,
                artworkData: nil,
                source: TrackSource(rawValue: entry.source) ?? .files, sourceID: entry.sourceID)
            track.bpm = entry.bpm
            track.playCount = entry.playCount
            context.insert(track)
            byKey[entry.key] = track
            restoredTracks.append(track)
            if fileExists { report.restoredWithFile += 1 } else { report.restoredMetadata += 1 }
        }

        for pl in backup.playlists {
            if library.playlists.contains(where: { $0.name.lowercased() == pl.name.lowercased() }) {
                report.playlistsSkipped += 1
                continue
            }
            let members = pl.trackKeys.compactMap { byKey[$0] }
            library.createPlaylist(name: pl.name, tracks: members, isRemix: pl.isRemix)
            report.playlistsCreated += 1
        }
        library.refresh()
        return report
    }
}
