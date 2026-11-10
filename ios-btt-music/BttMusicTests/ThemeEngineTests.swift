import SwiftUI
import Testing
import UIKit
@testable import BttMusic

// Verifies the dynamic theme engine: a remote-style theme JSON changes the
// palette, typography design, corner radii and feature flags live.
@MainActor
struct ThemeEngineTests {

    private let remoteThemeJSON = """
    {
      "name": "BT Midnight",
      "palette": {
        "canvas": "#0A0E1A",
        "surface": "#141B2E",
        "surfaceRaised": "#1D2740",
        "accentA": "#4F46E5",
        "accentB": "#22D3EE",
        "accentC": "#34D399",
        "textPrimary": "#F8FAFC",
        "textSecondary": "#F8FAFC99",
        "textTertiary": "#F8FAFC59"
      },
      "displayFontDesign": "rounded",
      "bodyFontDesign": "serif",
      "cardCornerRadius": 16,
      "artworkCornerRadius": 8,
      "featureFlags": { "youtube": false, "remix": true, "x2": true }
    }
    """

    @Test func remoteThemeJSONChangesPaletteTypographyAndFlags() throws {
        let theme = BTTheme.shared
        let decoded = try #require(Self.decode(remoteThemeJSON))
        let original = theme.json
        defer { theme.apply(original) }   // leave the shared singleton untouched

        theme.apply(decoded)

        // Name + palette
        #expect(theme.json.name == "BT Midnight")
        #expect(Self.rgb(theme.canvas) == Self.hex("#0A0E1A"))
        #expect(Self.rgb(theme.surface) == Self.hex("#141B2E"))
        #expect(Self.rgb(theme.accentA) == Self.hex("#4F46E5"))
        #expect(Self.rgb(theme.accentB) == Self.hex("#22D3EE"))
        #expect(Self.rgb(theme.accentC) == Self.hex("#34D399"))

        // Typography character changed by remote data
        #expect(theme.displayDesign == .rounded)
        #expect(theme.bodyDesign == .serif)

        // Layout values + feature flags drive the UI
        #expect(theme.json.cardCornerRadius == 16)
        #expect(theme.json.artworkCornerRadius == 8)
        #expect(theme.flag("youtube") == false)   // YouTube card would disappear
        #expect(theme.flag("remix") == true)
    }

    @Test func malformedRemoteThemeIsRejectedNotApplied() throws {
        let bad = #"{"name": "Broken", "palette": "nope"}"#
        let theme = BTTheme.shared
        let original = theme.json
        let decoded = Self.decode(bad)
        #expect(decoded == nil, "malformed theme JSON must fail decoding, not apply a half-theme")
        // Status quo preserved
        #expect(theme.json.name == original.name)
    }

    // MARK: helpers
    static func decode(_ json: String) -> BTTheme.ThemeJSON? {
        try? JSONDecoder().decode(BTTheme.ThemeJSON.self, from: Data(json.utf8))
    }

    static func hex(_ string: String) -> (r: Int, g: Int, b: Int) {
        var h = string.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        let rgb = Int(h, radix: 16)!
        return ((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF)
    }

    static func rgb(_ color: Color) -> (r: Int, g: Int, b: Int) {
        var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}
