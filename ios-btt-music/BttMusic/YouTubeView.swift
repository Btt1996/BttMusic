import SwiftUI

// YouTube import — honest design:
//  iOS apps cannot run yt-dlp (it's a Python pipeline) and cannot extract
//  YouTube streams themselves. This screen therefore drives a yt-dlp
//  COMPATIBLE server that YOU host (at home, on a VPS, anywhere) and submits
//  the video URL to it. Without a configured server this screen clearly says
//  so and does nothing else.
struct YouTubeView: View {
    @Environment(LibraryStore.self) private var library
    var initialURL: String = ""

    @AppStorage("bt.ytdlp.server") private var serverURL = ""
    @State private var videoURL = ""
    @State private var phase: Phase = .idle

    enum Phase: Equatable {
        case idle, submitting, downloading(String, Double)
        case done(String), failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                serverCard
                submitCard
                statusCard
                honestyNote
            }
            .padding(16)
        }
        .background(BT.canvas)
        .navigationTitle("YouTube Import")
        .onAppear {
            if videoURL.isEmpty { videoURL = initialURL }
        }
    }

    private var serverConfigured: Bool {
        URL(string: serverURL)?.scheme?.hasPrefix("http") == true
    }

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your yt-dlp server", systemImage: "server.rack")
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text("Base URL of a yt-dlp-compatible extraction server you control (for example youtube-dl-api-server or a small script you host). iOS cannot run yt-dlp on-device.")
                .font(.system(size: 13))
                .foregroundStyle(BT.textSecondary)
            TextField("https://my-server.example.com", text: $serverURL)
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.plain)
                .padding(12)
                .background(BT.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
        }
        .padding(18)
        .btCard()
    }

    private var submitCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Submit a link", systemImage: "play.rectangle.fill")
                .font(.system(size: 16, weight: .bold, design: .rounded))
            HStack(spacing: 10) {
                TextField("https://youtube.com/watch?v=…", text: $videoURL)
                    .font(.system(size: 13.5, design: .monospaced))
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(BT.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button {
                    if let s = UIPasteboard.general.string { videoURL = s.trimmingCharacters(in: .whitespacesAndNewlines) }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(BT.magenta)
                        .frame(width: 44, height: 44)
                        .background(BT.magenta.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            Button {
                Task { await submit() }
            } label: {
                HStack {
                    if phase == .submitting { ProgressView().tint(.white) }
                    Text("Import Audio")
                        .font(.system(size: 15, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.white)
                .padding(.vertical, 13)
                .background(BT.gradient, in: Capsule())
            }
            .disabled(!serverConfigured || videoURL.isEmpty || phase == .submitting)
            if !serverConfigured {
                Text("Configure your server above first.")
                    .font(.system(size: 12))
                    .foregroundStyle(BT.textTertiary)
            }
        }
        .padding(18)
        .btCard()
    }

    @ViewBuilder
    private var statusCard: some View {
        switch phase {
        case .submitting:
            HStack { Spacer(); ProgressView().tint(BT.magenta); Spacer() }
        case .downloading(let name, let progress):
            VStack(alignment: .leading, spacing: 8) {
                Text("Downloading \(name)")
                    .font(.system(size: 13, weight: .semibold))
                ProgressView(value: progress).tint(BT.magenta)
            }
            .padding(16)
            .btCard()
        case .done(let msg):
            Text(msg)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(BT.magenta)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .btCard()
        case .failed(let msg):
            Text(msg)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(BT.red)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .btCard()
        case .idle:
            EmptyView()
        }
    }

    private var honestyNote: some View {
        Text("This feature downloads audio only from links you submit to a server YOU host and control. The app never circumvents YouTube's streaming protections on its own, and works only while your server is reachable.")
            .font(.system(size: 11.5))
            .foregroundStyle(BT.textTertiary)
            .padding(.horizontal, 8)
    }

    private func submit() async {
        guard let server = URL(string: serverURL) else { return }
        phase = .submitting
        do {
            var request = URLRequest(url: server.appendingPathComponent("extract"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 30
            request.httpBody = try JSONEncoder().encode(["url": videoURL])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                phase = .failed("Your server answered with an error. Check that it is running and reachable.")
                return
            }
            // Expected response: {"title": "...", "download_url": "..."} — yt-dlp server contract.
            struct ExtractResponse: Decodable { var title: String?; var download_url: String }
            let payload = try JSONDecoder().decode(ExtractResponse.self, from: data)
            guard let fileURL = URL(string: payload.download_url) else {
                phase = .failed("Your server returned no download URL.")
                return
            }
            let name = payload.title ?? "YouTube audio"
            phase = .downloading(name, 0)
            let (temp, resp) = try await URLSession.shared.download(from: fileURL, delegate: nil)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                phase = .failed("Audio download failed (HTTP error).")
                return
            }
            phase = .downloading(name, 0.9)
            let importURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(name.replacingOccurrences(of: "/", with: "-"))
                .appendingPathExtension(temp.pathExtension.isEmpty ? "m4a" : temp.pathExtension)
            try? FileManager.default.removeItem(at: importURL)
            try FileManager.default.moveItem(at: temp, to: importURL)
            if library.importFile(at: importURL, source: .files, sourceID: "yt:" + videoURL) != nil {
                phase = .done("Imported \"\(name)\" to your library.")
            } else {
                phase = .done("Import skipped — the file was a duplicate or unreadable.")
            }
            try? FileManager.default.removeItem(at: importURL)
        } catch {
            phase = .failed("Could not reach your server: \(error.localizedDescription)")
        }
    }
}
