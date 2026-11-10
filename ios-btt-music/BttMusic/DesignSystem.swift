import SwiftUI

// Design system entry points. All values are live views over BTTheme.shared,
// so applying a remote theme restyles every screen without code changes.
// Typography pairs a serif display face (editorial, Apple-keynote-like)
// with the system sans for UI chrome.
enum BT {
    static var theme: BTTheme { BTTheme.shared }

    static var purple: Color { theme.accentA }
    static var magenta: Color { theme.accentB }
    static var red: Color { theme.accentC }
    static var white: Color { .white }

    static var gradient: LinearGradient { theme.gradient }
    static var horizontalGradient: LinearGradient { theme.horizontalGradient }

    static var canvas: Color { theme.canvas }
    static var surface: Color { theme.surface }
    static var surfaceRaised: Color { theme.surfaceRaised }
    static var hairline: Color { .white.opacity(0.08) }
    static var textSecondary: Color { theme.textSecondary }
    static var textTertiary: Color { theme.textTertiary }

    static var corner: CGFloat { theme.json.cardCornerRadius }
    static var artworkCorner: CGFloat { theme.json.artworkCornerRadius }

    // Display font sizes use a serif face for the editorial signature look
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: theme.displayDesign)
    }
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: theme.bodyDesign)
    }
}

extension View {
    func btCard() -> some View {
        self
            .background(BT.surface, in: .rect(cornerRadius: BT.corner))
            .overlay(
                RoundedRectangle(cornerRadius: BT.corner)
                    .strokeBorder(BT.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    func btGradientText() -> some View {
        foregroundStyle(BT.gradient)
    }
}

struct GradientPlayBadge: View {
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32)
                .fill(BT.gradient)
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: size * 0.03)
        }
        .frame(width: size, height: size)
    }
}

struct TrackArtwork: View {
    let artworkData: Data?
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let data = artworkData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: BT.artworkCorner)
                        .fill(BT.gradient.opacity(0.22))
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(BT.gradient)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: BT.artworkCorner))
    }
}
