import Foundation
import SwiftData

enum TrackSource: String, Codable {
    case files
    case telegram
    case x2
}

@Model
final class Track {
    var id: UUID
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var fileName: String
    var fileSize: Int64
    var artworkData: Data?
    var sourceRaw: String
    var sourceID: String
    var bpm: Double
    var energy: Double
    var brightness: Double
    var analyzed: Bool
    var dateAdded: Date
    var playCount: Int

    var source: TrackSource {
        get { TrackSource(rawValue: sourceRaw) ?? .files }
        set { sourceRaw = newValue.rawValue }
    }

    init(title: String, artist: String, album: String, duration: TimeInterval,
         fileName: String, fileSize: Int64, artworkData: Data? = nil,
         source: TrackSource = .files, sourceID: String = "") {
        self.id = UUID()
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.fileName = fileName
        self.fileSize = fileSize
        self.artworkData = artworkData
        self.sourceRaw = source.rawValue
        self.sourceID = sourceID
        self.bpm = 0
        self.energy = 0
        self.brightness = 0
        self.analyzed = false
        self.dateAdded = Date()
        self.playCount = 0
    }
}

@Model
final class Playlist {
    var id: UUID
    var name: String
    var dateCreated: Date
    var isRemix: Bool
    @Relationship(deleteRule: .nullify)
    var tracks: [Track]?

    init(name: String, isRemix: Bool = false) {
        self.id = UUID()
        self.name = name
        self.dateCreated = Date()
        self.isRemix = isRemix
    }
}

extension Track {
    static var tracksDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Tracks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var fileURL: URL { Self.tracksDirectory.appendingPathComponent(fileName) }
    var fileExists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }
}
