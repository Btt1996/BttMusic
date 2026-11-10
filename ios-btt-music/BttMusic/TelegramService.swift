import Foundation

// Native Telegram Bot API client. The token lives in the Keychain, never in
// code or UserDefaults. Mirrors the old app's flow (getUpdates -> getFile ->
// file download) without the CORS proxy, which iOS does not need.
@MainActor
@Observable
final class TelegramService {
    private static let tokenKey = "bt.telegram.token"
    static let base = "https://api.telegram.org"

    struct BotUser: Codable { var id: Int; var username: String? }

    struct TelegramAudio: Identifiable, Hashable {
        var id: String { fileUniqueID }
        var fileID: String
        var fileUniqueID: String
        var title: String?
        var performer: String?
        var fileName: String?
        var mimeType: String
        var fileSize: Int64
        var duration: Double
        var chatTitle: String
    }

    enum Phase: Equatable {
        case idle
        case connecting
        case scanning
        case downloading(name: String, progress: Double)
        case done(String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var discovered: [TelegramAudio] = []
    private(set) var botUsername: String?
    private(set) var connected: Bool = false

    init() {
        connected = Self.token() != nil
    }

    // MARK: - Token
    static func token() -> String? { Keychain.get(tokenKey) }

    func connect(token: String) async {
        phase = .connecting
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let bot: BotUser = try await Self.call("getMe", token: clean, query: [:])
            Keychain.set(clean, for: Self.tokenKey)
            connected = true
            botUsername = bot.username
            phase = .done("Connected @\(bot.username ?? "bot")")
        } catch {
            phase = .failed("Bot verification failed: \(error.localizedDescription)")
        }
    }

    func disconnect() {
        Keychain.delete(Self.tokenKey)
        connected = false
        botUsername = nil
        discovered = []
        phase = .idle
    }

    // MARK: - Scan bot updates
    func scan() async -> [TelegramAudio] {
        guard let token = Self.token() else {
            phase = .failed("Connect a bot first")
            return []
        }
        phase = .scanning
        do {
            struct Update: Codable {
                struct Message: Codable {
                    struct Chat: Codable { var id: Int; var title: String?; var first_name: String?; var username: String? }
                    struct AudioDoc: Codable {
                        var file_id: String
                        var file_unique_id: String
                        var title: String?
                        var performer: String?
                        var file_name: String?
                        var mime_type: String?
                        var file_size: Int64?
                        var duration: Int?
                    }
                    var audio: AudioDoc?
                    var document: AudioDoc?
                    var chat: Chat?
                }
                var message: Message?
                var channel_post: Message?
            }
            let updates: [Update] = try await Self.call(
                "getUpdates", token: token,
                query: ["limit": "100", "allowed_updates": "[\"message\",\"channel_post\"]"]
            )
            var found: [TelegramAudio] = []
            for u in updates {
                let m = u.message ?? u.channel_post
                guard let m else { continue }
                let a = m.audio ?? m.document
                guard let a else { continue }
                let mime = a.mime_type ?? ""
                guard mime.hasPrefix("audio") || mime == "video/ogg" || ["mp3","m4a","flac","wav","ogg","opus","aac"].contains(
                    (a.file_name ?? "").split(separator: ".").last.map(String.init)?.lowercased() ?? "") else { continue }
                let chat = m.chat?.title ?? m.chat?.username ?? m.chat?.first_name ?? "Telegram"
                found.append(TelegramAudio(
                    fileID: a.file_id, fileUniqueID: a.file_unique_id,
                    title: a.title ?? a.file_name, performer: a.performer,
                    fileName: a.file_name, mimeType: mime.isEmpty ? "audio/mpeg" : mime,
                    fileSize: a.file_size ?? 0, duration: Double(a.duration ?? 0), chatTitle: chat
                ))
            }
            // Deduplicate by file_unique_id
            var seen = Set<String>()
            found.removeAll { !seen.insert($0.fileUniqueID).inserted }
            discovered = found
            phase = found.isEmpty ? .done("No audio in recent bot updates. Send MP3s to your bot, then Refresh.") : .done("Found \(found.count) audio files")
        } catch {
            phase = .failed(error.localizedDescription)
        }
        return discovered
    }

    // MARK: - Download with progress
    @discardableResult
    func download(_ audio: TelegramAudio, into library: LibraryStore) async -> Track? {
        guard let token = Self.token() else { return nil }
        do {
            struct FileInfo: Codable { var file_path: String? }
            let info: FileInfo = try await Self.call("getFile", token: token, query: ["file_id": audio.fileID])
            guard let path = info.file_path else { throw NSError(domain: "tg", code: 1, userInfo: [NSLocalizedDescriptionKey: "File too large for Bot API download (20 MB limit) or unavailable"]) }
            let url = URL(string: "\(Self.base)/file/bot\(token)/\(path)")!
            phase = .downloading(name: audio.title ?? audio.fileName ?? "audio", progress: 0)
            let (tempURL, response) = try await download(url) { [weak self] fraction in
                Task { @MainActor in
                    self?.phase = .downloading(name: audio.title ?? audio.fileName ?? "audio", progress: fraction)
                }
            }
            _ = response
            // Preserve original filename metadata by staging through importFile
            let track = library.importFile(at: tempURL, source: .telegram, sourceID: audio.fileUniqueID)
            try? FileManager.default.removeItem(at: tempURL)
            if let track {
                if track.title.isEmpty || track.artist == "Unknown Artist" {
                    if let t = audio.title { track.title = t }
                    if let p = audio.performer { track.artist = p }
                }
                if track.album.isEmpty { track.album = audio.chatTitle }
                library.refresh()
                phase = .done("Imported \(track.title)")
            } else {
                phase = .done("Skipped (duplicate or unreadable)")
            }
            return track
        } catch {
            phase = .failed("Download error: \(error.localizedDescription)")
            return nil
        }
    }

    private func download(_ url: URL, progress: @escaping (Double) -> Void) async throws -> (URL, URLResponse) {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        let total = response.expectedContentLength
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".audio")
        var data = Data()
        var lastReport = 0.0
        for try await byte in bytes {
            data.append(byte)
            if total > 0 {
                let f = Double(data.count) / Double(total)
                if f - lastReport > 0.02 {
                    lastReport = f
                    progress(f)
                }
            }
        }
        try data.write(to: temp)
        return (temp, response)
    }

    // MARK: - Generic API call
    private struct Envelope<T: Decodable>: Decodable { var ok: Bool; var result: T?; var description: String? }

    nonisolated static func call<T: Decodable>(_ method: String, token: String, query: [String: String]) async throws -> T {
        var components = URLComponents(string: "\(base)/bot\(token)/\(method)")!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        let http = response as? HTTPURLResponse
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        guard envelope.ok, let result = envelope.result else {
            throw NSError(domain: "telegram", code: http?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: envelope.description ?? "Telegram request failed"])
        }
        return result
    }
}
