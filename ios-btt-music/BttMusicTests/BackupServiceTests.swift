import Foundation
import SwiftData
import Testing
@testable import BttMusic

// Verifies the full backup -> restore cycle and its protections:
// preview data, duplicate matching, missing-file accounting, and the
// guarantee that restoring NEVER overwrites or duplicates existing tracks.
@MainActor
struct BackupServiceTests {

    private func makeStore() throws -> (LibraryStore, ModelContainer) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Track.self, Playlist.self, configurations: config)
        let store = LibraryStore()
        store.bind(context: ModelContext(container))
        return (store, container)
    }

    private func makeTrack(_ title: String, _ artist: String, fileName: String = "x.m4a",
                           duration: TimeInterval = 180, playCount: Int = 0) -> Track {
        let t = Track(title: title, artist: artist, album: "Album", duration: duration,
                      fileName: fileName, fileSize: 4_000_000, source: .files)
        t.playCount = playCount
        return t
    }

    @Test func exportRoundTripPreservesTracksAndPlaylists() throws {
        let (store, container) = try makeStore()
        let context = ModelContext(container)
        let a = makeTrack("Nightcall", "Kavinsky", playCount: 7)
        let b = makeTrack("Sunset", "The Midnight", playCount: 2)
        context.insert(a); context.insert(b)
        let pl = Playlist(name: "Night Drive")
        pl.tracks = [a, b]
        context.insert(pl)
        store.refresh()

        let data = try #require(BackupService.exportBackup(tracks: store.tracks, playlists: store.playlists))
        let backup = try #require(BackupService.decodeBackup(from: data))

        #expect(backup.schema == 1)
        #expect(backup.tracks.count == 2)
        #expect(backup.playlists.count == 1)
        #expect(backup.playlists[0].name == "Night Drive")
        #expect(backup.playlists[0].trackKeys.count == 2)
        // Metadata survives: play counts and durations
        let nightcall = backup.tracks.first { $0.title == "Nightcall" }
        #expect(nightcall?.playCount == 7)
        #expect(nightcall?.duration == 180)
        #expect(nightcall?.artist == "Kavinsky")
    }

    @Test func restoreNeverOverwritesAndFlagsMissingFiles() throws {
        // Destination library already contains one of the backed-up tracks.
        let (store, container) = try makeStore()
        let context = ModelContext(container)
        let existing = makeTrack("Nightcall", "Kavinsky", fileName: "device-original.m4a", playCount: 99)
        context.insert(existing)
        let preexistingPlaylist = Playlist(name: "Night Drive")
        context.insert(preexistingPlaylist)
        store.refresh()
        let existingID = existing.id
        let existingPlayCount = existing.playCount

        let backup = BackupService.Backup(tracks: [
            .init(title: "Nightcall", artist: "Kavinsky", album: "OutRun", duration: 254,
                  fileName: "cloud-copy.m4a", fileSize: 5_000_000, source: "files",
                  sourceID: "", bpm: 0, playCount: 3),
            .init(title: "Sunset", artist: "The Midnight", album: "", duration: 200,
                  fileName: "not-on-this-device.m4a", fileSize: 4_000_000, source: "telegram",
                  sourceID: "tg-1", bpm: 100, playCount: 0),
            .init(title: "", artist: "Broken Entry", album: "", duration: 0,
                  fileName: "bad.m4a", fileSize: 0, source: "files", sourceID: "", bpm: 0, playCount: 0),
        ], playlists: [
            .init(name: "Night Drive", isRemix: false, trackKeys: [
                "nightcall|kavinsky", "sunset|the midnight"
            ]),
        ])

        let report = BackupService.restore(backup, into: store, context: context)

        // The already-present track was matched, untouched, not duplicated.
        #expect(report.matchedExisting == 1)
        #expect(report.restoredMetadata == 1)   // "Sunset" has no audio on this device
        #expect(report.restoredWithFile == 0)
        #expect(report.skippedEntries == 1)     // malformed entry rejected
        #expect(report.playlistsCreated == 1)   // "Night Drive" already existed -> skipped
        #expect(report.playlistsSkipped == 1)
        #expect(store.tracks.count == 2)        // 1 existing + 1 restored, no duplicates

        let original = try #require(store.tracks.first { $0.id == existingID })
        #expect(original.playCount == existingPlayCount)   // never overwritten

        // The created playlist contains the existing track (matched) + the new one.
        let playlist = try #require(store.playlists.first { $0.name == "Night Drive" && $0.id != preexistingPlaylist.id })
        #expect(playlist.tracks?.count == 2)
        #expect(playlist.tracks?.contains { $0.id == existingID } == true)
    }

    @Test func completeExportRestoreCycle() throws {
        // Cycle: library A (2 tracks, one WITH audio on disk, 1 playlist)
        //        -> export JSON -> restore into empty library C.
        let (source, sourceContainer) = try makeStore()
        let sourceContext = ModelContext(sourceContainer)

        let fileName = "cycle-\(UUID().uuidString).m4a"
        let fileURL = Track.tracksDirectory.appendingPathComponent(fileName)
        try? "fake-bytes-for-existence-check".data(using: .utf8)!.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let withFile = makeTrack("Real File", "Artist A", fileName: fileName)
        let metadataOnly = makeTrack("Cloud Only", "Artist B", fileName: "cycle-missing-\(UUID().uuidString).m4a")
        sourceContext.insert(withFile); sourceContext.insert(metadataOnly)
        let pl = Playlist(name: "Mixed", isRemix: true)
        pl.tracks = [withFile, metadataOnly]
        sourceContext.insert(pl)
        source.refresh()

        let data = try #require(BackupService.exportBackup(tracks: source.tracks, playlists: source.playlists))
        let backup = try #require(BackupService.decodeBackup(from: data))

        let (destination, destContainer) = try makeStore()
        let destContext = ModelContext(destContainer)
        let report = BackupService.restore(backup, into: destination, context: destContext)

        #expect(report.matchedExisting == 0)
        #expect(report.restoredWithFile == 1)   // file existed on this device
        #expect(report.restoredMetadata == 1)   // metadata-only, flagged
        #expect(report.playlistsCreated == 1)
        #expect(destination.tracks.count == 2)
        let restoredPlaylist = try #require(destination.playlists.first)
        #expect(restoredPlaylist.isRemix == true)
        #expect(restoredPlaylist.tracks?.count == 2)
    }
}
