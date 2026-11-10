import Foundation
import SwiftUI

// Dynamic theme engine. The default theme ships in the bundle; a future
// "visual direction" can be delivered by pointing the app at a theme JSON
// (hosted on GitHub raw or any CDN) and tapping Apply in Settings — no
// architectural rewrite needed. Palettes, typography character, corner
// radii and feature visibility are all data-driven. Native-code changes
// still ship through proper app updates.
@MainActor
@Observable
final class BTTheme {
    static let shared = BTTheme()
    static let remoteURLKey = "bt.theme.remoteurl"

    struct Palette: Codable, Equatable {
        var canvas: String        // background
        var surface: String       // cards
        var surfaceRaised: String
        var accentA: String       // gradient start
        var accentB: String       // gradient middle
        var accentC: String       // gradient end
        var textPrimary: String
        var textSecondary: String
        var textTertiary: String
    }

    struct ThemeJSON: Codable {
        var name: String
        var palette: Palette
        var displayFontDesign: String   // "serif" | "rounded" | "default"
        var bodyFontDesign: String      // "serif" | "rounded" | "default"
        var cardCornerRadius: Double
        var artworkCornerRadius: Double
        var featureFlags: [String: Bool] // e.g. "youtube": true, "remix": true
    }

    private(set) var json: ThemeJSON
    private(set) var lastAppliedRemote: String?
    private(set) var status: String?

    static let defaultTheme = ThemeJSON(
        name: "BT Signature",
        palette: Palette(
            canvas: "#000000",
            surface: "#131316",
            surfaceRaised: "#1E1E21",
            accentA: "#7A2BF5",
            accentB: "#E62BD9",
            accentC: "#FF1F4B",
            textPrimary: "#FFFFFF",
            textSecondary: "#FFFFFF8C",
            textTertiary: "#FFFFFF59"
        ),
        displayFontDesign: "serif",
        bodyFontDesign: "default",
        cardCornerRadius: 22,
        artworkCornerRadius: 12,
        featureFlags: ["youtube": true, "remix": true, "x2": true]
    )

    init() {
        // Load cached remote theme if present, else bundled default
        if let data = try? Data(contentsOf: Self.cacheURL),
           let decoded = try? JSONDecoder().decode(ThemeJSON.self, from: data) {
            json = decoded
            lastAppliedRemote = UserDefaults.standard.string(forKey: Self.remoteURLKey)
        } else {
            json = Self.defaultTheme
        }
    }

    static var cacheURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cached-theme.json")
    }

    var remoteURL: String {
        get { UserDefaults.standard.string(forKey: Self.remoteURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.remoteURLKey) }
    }

    // MARK: - Remote theme fetch
    func fetchRemote() async {
        let urlString = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard urlString.contains("http") else {
            status = "Enter a theme JSON URL (e.g. a GitHub raw link)"
            return
        }
        guard let url = URL(string: urlString) else {
            status = "Invalid URL"
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                status = "Theme fetch returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
                return
            }
            let decoded = try JSONDecoder().decode(ThemeJSON.self, from: data)
            apply(decoded)
            try? data.write(to: Self.cacheURL)
            lastAppliedRemote = urlString
            status = "Applied theme \"\(decoded.name)\""
        } catch {
            status = "Theme fetch failed: \(error.localizedDescription)"
        }
    }

    func resetToDefault() {
        json = Self.defaultTheme
        try? FileManager.default.removeItem(at: Self.cacheURL)
        status = "Reset to the bundled BT Signature theme"
    }

    // Swap the live theme (used by remote fetch; also exercised by tests).
    func apply(_ decoded: ThemeJSON) {
        json = decoded
    }

    // MARK: - Color helpers
    static func color(from hex: String) -> Color {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        var alpha: Double = 1
        if h.count == 8 {
            alpha = Double(Int(h.suffix(2), radix: 16) ?? 255) / 255
            h = String(h.prefix(6))
        }
        guard h.count == 6, let rgb = Int(h, radix: 16) else { return .black }
        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: alpha
        )
    }

    // MARK: - Convenience accessors (live, reactive)
    var canvas: Color { Self.color(from: json.palette.canvas) }
    var surface: Color { Self.color(from: json.palette.surface) }
    var surfaceRaised: Color { Self.color(from: json.palette.surfaceRaised) }
    var accentA: Color { Self.color(from: json.palette.accentA) }
    var accentB: Color { Self.color(from: json.palette.accentB) }
    var accentC: Color { Self.color(from: json.palette.accentC) }
    var textPrimary: Color { Self.color(from: json.palette.textPrimary) }
    var textSecondary: Color { Self.color(from: json.palette.textSecondary) }
    var textTertiary: Color { Self.color(from: json.palette.textTertiary) }

    var gradient: LinearGradient {
        LinearGradient(colors: [accentA, accentB, accentC], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var horizontalGradient: LinearGradient {
        LinearGradient(colors: [accentA, accentB, accentC], startPoint: .leading, endPoint: .trailing)
    }

    var displayDesign: Font.Design {
        switch json.displayFontDesign {
        case "serif": .serif
        case "rounded": .rounded
        default: .default
        }
    }
    var bodyDesign: Font.Design {
        switch json.bodyFontDesign {
        case "serif": .serif
        case "rounded": .rounded
        default: .default
        }
    }

    func flag(_ key: String) -> Bool { json.featureFlags[key] ?? false }

    var magenta: Color { accentB }
    var purple: Color { accentA }
    var red: Color { accentC }
}
