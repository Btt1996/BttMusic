import Foundation

// X1: identify music and import METADATA ONLY.
// Parses public Spotify playlist/album/track links keylessly via the official
// embed pages (same approach as the old app's keyless fallback). No audio is
// downloaded here; audio acquisition belongs to X2.
@MainActor
@Observable
final class X1SpotifyService {
    struct X1Track: Identifiable, Hashable {
        var id = UUID()
        var title: String
        var artist: String
        var spotifyURI: String
    }

    struct X1Collection: Identifiable {
        var id = UUID()
        var kind: String   // playlist / album / track
        var name: String
        var spotifyURL: String
        var tracks: [X1Track]
    }

    enum Phase: Equatable {
        case idle, importing
        case done(String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var lastImport: X1Collection?

    // MARK: - Link parsing
    struct SpotifyRef { var type: String; var id: String }

    static func parseLink(_ text: String) -> SpotifyRef? {
        // Accept open.spotify.com/playlist/ID, spotify:playlist:ID, or raw share text
        let patterns = [
            #"open\.spotify\.com/(?:intl-[a-z]+/)?(playlist|album|track)/([A-Za-z0-9]+)"#,
            #"spotify:(playlist|album|track):([A-Za-z0-9]+)"#,
        ]
        for p in patterns {
            if let m = text.range(of: p, options: .regularExpression) {
                let s = String(text[m])
                let parts = s.replacingOccurrences(of: ":", with: "/").split(separator: "/")
                if parts.count >= 2 {
                    let type = String(parts[parts.count - 2])
                    let id = String(parts.last!)
                    return SpotifyRef(type: type, id: id)
                }
            }
        }
        return nil
    }

    // MARK: - Import
    func importCollection(from link: String) async -> X1Collection? {
        guard let ref = Self.parseLink(link) else {
            phase = .failed("Paste a valid open.spotify.com playlist, album or track link")
            return nil
        }
        phase = .importing
        do {
            let embed = URL(string: "https://open.spotify.com/embed/\(ref.type)/\(ref.id)")!
            // A native app has no CORS restriction: fetch the embed page directly.
            let data: Data
            do {
                var request = URLRequest(url: embed)
                request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
                let (d, r) = try await URLSession.shared.data(for: request)
                guard let http = r as? HTTPURLResponse, http.statusCode == 200, d.count > 1000 else {
                    throw NSError(domain: "x1", code: 1)
                }
                data = d
            } catch {
                // Fallback: public CORS relay, same as the old app.
                let proxied = "https://api.allorigins.win/raw?url=\(embed.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? embed.absoluteString)"
                let (d, _) = try await URLSession.shared.data(from: URL(string: proxied)!)
                data = d
            }
            guard let html = String(data: data, encoding: .utf8),
                  let jsonStart = html.range(of: #"<script id="__NEXT_DATA__" type="application/json">"#),
                  let jsonEnd = html.range(of: "</script>", range: jsonStart.upperBound..<html.endIndex) else {
                throw NSError(domain: "x1", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not read Spotify embed page. Make sure the link is public."])
            }
            let json = String(html[jsonStart.upperBound..<jsonEnd.lowerBound])

            struct Embed: Decodable {
                struct Page: Decodable {
                    struct Entity: Decodable {
                        struct Entry: Decodable {
                            var title: String?
                            var subtitle: String?
                            var uri: String?
                        }
                        var name: String?
                        var title: String?
                        var subtitle: String?
                        var trackList: [Entry]?
                        var trackCount: Int?
                    }
                    var entity: Entity?
                }
                var props: Page?
            }
            let decoded = try JSONDecoder().decode(Embed.self, from: Data(json.utf8))
            guard let entity = decoded.props?.entity else {
                throw NSError(domain: "x1", code: 3, userInfo: [NSLocalizedDescriptionKey: "Embed data not found — Spotify may have changed its format."])
            }
            let name = entity.name ?? entity.title ?? "Spotify Import"
            var tracks: [X1Track] = []
            if let list = entity.trackList {
                for e in list {
                    let parts = (e.subtitle ?? e.title ?? "").split(separator: "•").map { $0.trimmingCharacters(in: .whitespaces) }
                    let artist = parts.count > 1 ? parts.last! : (e.subtitle ?? "Unknown Artist")
                    tracks.append(X1Track(title: e.title ?? "Unknown Title", artist: artist, spotifyURI: e.uri ?? ""))
                }
            } else if let t = entity.title {
                tracks.append(X1Track(title: t, artist: entity.subtitle ?? "Unknown Artist", spotifyURI: "spotify:\(ref.type):\(ref.id)"))
            }
            guard !tracks.isEmpty else {
                throw NSError(domain: "x1", code: 4, userInfo: [NSLocalizedDescriptionKey: "No tracks found in the link."])
            }
            let collection = X1Collection(kind: ref.type, name: name, spotifyURL: "https://open.spotify.com/\(ref.type)/\(ref.id)", tracks: tracks)
            lastImport = collection
            phase = .done("Imported \"\(name)\" — \(tracks.count) tracks of metadata")
            return collection
        } catch {
            phase = .failed(error.localizedDescription)
            return nil
        }
    }

    // MARK: - Match to local library
    static func match(_ x1: X1Track, in library: LibraryStore) -> Track? {
        let t = x1.title.lowercased()
        let a = x1.artist.lowercased()
        return library.tracks.first { track in
            let lt = track.title.lowercased()
            let la = track.artist.lowercased()
            return (lt.contains(t) || t.contains(lt)) && (la.contains(a) || a.contains(la) || la == "unknown artist")
        }
    }

    func saveAsPlaylist(_ collection: X1Collection, in library: LibraryStore) -> Playlist {
        let playlist = library.createPlaylist(name: collection.name)
        var seen = Set<UUID>()
        var list: [Track] = []
        for t in collection.tracks {
            if let local = Self.match(t, in: library), seen.insert(local.id).inserted {
                list.append(local)
            }
        }
        playlist.tracks = list
        library.refresh()
        return playlist
    }
}
