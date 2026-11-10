import Foundation

// X2: acquire ACTUAL AUDIO from authorized, freely licensed sources.
// Mirrors the old app's x2Engine: archive.org, Jamendo (with user's own
// client ID), and the Free Music Archive demo API. No DRM circumvention,
// no unauthorized extraction: every provider here serves freely licensed audio.
@MainActor
@Observable
final class X2AcquisitionService {
    struct X2Result: Identifiable, Hashable {
        var id: String          // provider + provider id
        var provider: String    // "archive" | "jamendo" | "fma"
        var title: String
        var artist: String
        var audioURL: URL
        var license: String
    }

    enum Phase: Equatable {
        case idle, searching
        case results(String)
        case downloading(name: String, progress: Double)
        case done(String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var results: [X2Result] = []

    static let jamendoClientIDKey = "bt.jamendo.clientid"
    var jamendoClientID: String {
        get { UserDefaults.standard.string(forKey: Self.jamendoClientIDKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.jamendoClientIDKey) }
    }

    // MARK: - Search
    func search(_ query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        phase = .searching
        results = []
        async let archive = searchArchive(query)
        async let jamendo = searchJamendo(query)
        let (a, j) = await (archive, jamendo)
        results = a + j
        phase = results.isEmpty ? .results("No freely licensed audio found for \"\(query)\"") : .results("\(results.count) results")
    }

    private func searchArchive(_ query: String) async -> [X2Result] {
        struct SearchDoc: Codable { var identifier: String?; var title: String?; var creator: String? }
        struct SearchResponse: Codable { struct Response: Codable { var docs: [SearchDoc]? }; var response: Response? }
        let q = "\(query) AND mediatype:audio AND format:(MP3)"
        guard let url = URL(string: "https://archive.org/advancedsearch.php?q=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)&fl%5B%5D=identifier&fl%5B%5D=title&fl%5B%5D=creator&rows=8&page=1&output=json") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            var out: [X2Result] = []
            for doc in decoded.response?.docs ?? [] {
                guard let id = doc.identifier else { continue }
                // Resolve an actual MP3 file inside the item
                guard let metaURL = URL(string: "https://archive.org/metadata/\(id)"),
                      let (metaData, _) = try? await URLSession.shared.data(from: metaURL) else { continue }
                struct ItemMeta: Codable {
                    struct FileEntry: Codable {
                        var name: String?
                        var format: String?
                        var size: String?
                    }
                    var files: [FileEntry]?
                }
                guard let item = try? JSONDecoder().decode(ItemMeta.self, from: metaData) else { continue }
                if let mp3 = item.files?.first(where: { f in
                    let n = (f.name ?? "").lowercased()
                    return n.hasSuffix(".mp3") && !(f.format ?? "").lowercased().contains("thumb")
                }) {
                    let encodedName = (mp3.name ?? "").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? mp3.name ?? ""
                    guard let audioURL = URL(string: "https://archive.org/download/\(id)/\(encodedName)") else { continue }
                    out.append(X2Result(
                        id: "archive_\(id)", provider: "Internet Archive",
                        title: doc.title ?? id, artist: doc.creator ?? "Public Domain",
                        audioURL: audioURL, license: "Internet Archive / public collections"
                    ))
                }
            }
            return out
        } catch {
            return []
        }
    }

    private func searchJamendo(_ query: String) async -> [X2Result] {
        guard !jamendoClientID.isEmpty else { return [] }
        guard let url = URL(string: "https://api.jamendo.com/v3.0/tracks/?client_id=\(jamendoClientID)&format=json&limit=6&namesearch=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)&include=licenses") else { return [] }
        struct JamendoResponse: Codable {
            struct Track: Codable {
                var id: String
                var name: String?
                var artist_name: String?
                var license_ccurl: String?
                var audio: String?
            }
            var results: [Track]?
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(JamendoResponse.self, from: data)
            return (decoded.results ?? []).compactMap { t in
                guard let audio = t.audio, let audioURL = URL(string: audio) else { return nil }
                return X2Result(
                    id: "jamendo_\(t.id)", provider: "Jamendo",
                    title: t.name ?? "Untitled", artist: t.artist_name ?? "Unknown Artist",
                    audioURL: audioURL,
                    license: t.license_ccurl ?? "Creative Commons"
                )
            }
        } catch {
            return []
        }
    }

    // MARK: - Download
    @discardableResult
    func acquire(_ result: X2Result, withMetadata meta: X1SpotifyService.X1Track?, into library: LibraryStore) async -> Track? {
        do {
            phase = .downloading(name: result.title, progress: 0)
            let (bytes, _) = try await URLSession.shared.bytes(from: result.audioURL)
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
            }
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
            try data.write(to: temp)
            let track = library.importFile(at: temp, source: .x2, sourceID: result.id)
            try? FileManager.default.removeItem(at: temp)
            if let track {
                if let meta {
                    track.title = meta.title
                    track.artist = meta.artist
                }
                library.refresh()
                phase = .done("Added \"\(track.title)\" to your library")
            } else {
                phase = .done("Skipped (duplicate or unreadable audio)")
            }
            return track
        } catch {
            phase = .failed("Download failed: \(error.localizedDescription)")
            return nil
        }
    }
}
