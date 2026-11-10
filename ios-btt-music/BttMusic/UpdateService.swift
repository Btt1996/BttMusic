import Foundation

// GitHub release checking. An iOS app cannot silently replace its own
// executable; this feature surfaces new releases and notes, and the actual
// install happens through TestFlight / App Store / the user's sideloading
// workflow. The repo is user-configurable in Settings.
@MainActor
@Observable
final class UpdateService {
    struct Release: Identifiable, Equatable {
        var id: String
        var version: String
        var notes: String
        var htmlURL: URL?
        var publishedAt: Date?
    }

    enum Status: Equatable {
        case idle
        case checking
        case upToDate(String)
        case available(Release)
        case failed(String)
    }

    private(set) var status: Status = .idle
    static let repoKey = "bt.updates.repo"
    static let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

    var repoPath: String {
        get { UserDefaults.standard.string(forKey: Self.repoKey) ?? "hynesconnor/spotify_to_mp3" }
        set { UserDefaults.standard.set(newValue, forKey: Self.repoKey) }
    }

    func check() async {
        status = .checking
        let path = repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.contains("/") else {
            status = .failed("Repository must look like owner/repo")
            return
        }
        let url = URL(string: "https://api.github.com/repos/\(path)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 404 {
                status = .upToDate("No published releases in \(path)")
                return
            }
            guard http.statusCode == 200 else {
                throw NSError(domain: "gh", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "GitHub returned HTTP \(http.statusCode)"])
            }
            struct GHRelease: Codable {
                var tag_name: String?
                var name: String?
                var body: String?
                var html_url: String?
                var published_at: String?
            }
            let release = try JSONDecoder().decode(GHRelease.self, from: data)
            let tag = release.tag_name ?? release.name ?? ""
            guard !tag.isEmpty else {
                status = .upToDate("No published releases in \(path)")
                return
            }
            let rel = Release(
                id: tag, version: normalized(tag),
                notes: release.body ?? "No release notes",
                htmlURL: release.html_url.flatMap(URL.init(string:)),
                publishedAt: release.published_at.flatMap { Self.parseDate($0) }
            )
            let installed = normalized(Self.currentVersion)
            if isVersion(rel.version, greaterThan: installed) {
                status = .available(rel)
            } else {
                status = .upToDate("You are on \(Self.currentVersion), the latest release is \(rel.version)")
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func normalized(_ v: String) -> String {
        v.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
    }

    private func isVersion(_ a: String, greaterThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    nonisolated static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        return f.date(from: s)
    }
}
