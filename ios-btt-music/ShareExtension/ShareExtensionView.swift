import SwiftUI

// Local stand-in for the app's BT design system (the extension is a separate
// module and cannot import it): the BT gradient, purple → magenta → red.
private struct ShareGradient: ShapeStyle {
    var body: some ShapeStyle {
        LinearGradient(
            colors: [Color(red: 0.478, green: 0.169, blue: 0.961),
                     Color(red: 0.902, green: 0.169, blue: 0.851),
                     Color(red: 1.0, green: 0.122, blue: 0.294)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// Receives a URL shared from Safari/YouTube, forwards it to Btt Music via the
// bttmu://youtube-import?url=... custom scheme. If iOS denies the open from an
// extension (common), the link is copied to the pasteboard as a fallback and
// the user is told to open Btt Music, where YouTube Import picks it up.
struct ShareView: View {
    let extensionContext: NSExtensionContext?
    @State private var forwarded = false
    @State private var sharedURL: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(ShareGradient())
                Text(forwarded ? "Link handed to Btt Music" : "Open in Btt Music")
                    .font(.system(size: 17, weight: .bold))
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                if let url = sharedURL {
                    Text(url)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .padding(.horizontal, 12)
                }
                Button("Done") {
                    extensionContext?.completeRequest(returningItems: nil)
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 40)
                .padding(.vertical, 12)
                .background(ShareGradient(), in: Capsule())
            }
            .padding()
            .navigationTitle("Btt Music")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .task { forward() }
    }

    private var message: String {
        if forwarded {
            return "Tap Done, then switch to Btt Music to finish the import."
        }
        return "Btt Music will import this YouTube link when you open it. The link is also on your clipboard as a fallback."
    }

    private func forward() {
        // Pull the shared URL out of the extension items (async load).
        for item in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier("public.url") {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url {
                            Task { @MainActor in
                                sharedURL = url.absoluteString
                                copyAndOpen(url.absoluteString)
                            }
                        }
                    }
                }
            }
        }
    }

    private func copyAndOpen(_ urlString: String) {
        UIPasteboard.general.string = urlString
        let trimmed = urlString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: ":/?&=.-_~"))) ?? urlString
        if let appURL = URL(string: "bttmu://youtube-import?url=\(trimmed)") {
            extensionContext?.open(appURL) { opened in
                Task { @MainActor in forwarded = opened }
            }
        }
    }
}
