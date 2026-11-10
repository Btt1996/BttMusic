import SwiftUI
import UniformTypeIdentifiers
import SwiftData

// Restore a full backup produced by BackupService. Shows a preview before
// touching anything; the restore itself never overwrites existing tracks.
struct RestoreView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.modelContext) private var modelContext

    @State private var showImporter = false
    @State private var backup: BackupService.Backup?
    @State private var decodeFailed = false
    @State private var report: BackupService.RestoreReport?
    @State private var confirmRestore = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                introCard
                if let backup {
                    previewCard(backup)
                } else if decodeFailed {
                    Text("That file is not a valid Btt Music backup (expected JSON exported by this app).")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BT.red)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .btCard()
                }
                if let report {
                    Text(report.summary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BT.magenta)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .btCard()
                }
                safetyNote
            }
            .padding(16)
        }
        .background(BT.canvas)
        .navigationTitle("Restore Backup")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { decodeFailed = true; return }
            if let parsed = BackupService.decodeBackup(from: data) {
                backup = parsed
                decodeFailed = false
            } else {
                decodeFailed = true
            }
        }
        .alert("Restore this backup?", isPresented: $confirmRestore) {
            Button("Restore") {
                if let backup {
                    report = BackupService.restore(backup, into: library, context: modelContext)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Existing tracks are never overwritten — duplicates are matched and left as they are.")
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Restore from JSON", systemImage: "square.and.arrow.down.on.square")
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text("Pick a backup JSON file (Files, iCloud Drive…). You'll see a preview of what it contains before anything is restored.")
                .font(.system(size: 13))
                .foregroundStyle(BT.textSecondary)
            Button {
                showImporter = true
            } label: {
                Label("Choose Backup File", systemImage: "folder")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.white)
                    .padding(.vertical, 13)
                    .background(BT.gradient, in: Capsule())
            }
        }
        .padding(18)
        .btCard()
    }

    private func previewCard(_ backup: BackupService.Backup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Backup contents")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Exported \(backup.exportedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 12))
                        .foregroundStyle(BT.textSecondary)
                }
                Spacer()
            }
            HStack(spacing: 20) {
                stat("\(backup.tracks.count)", "tracks")
                stat("\(backup.playlists.count)", "playlists")
            }
            ForEach(backup.playlists.prefix(6), id: \.name) { pl in
                HStack {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 12))
                        .foregroundStyle(BT.magenta)
                    Text(pl.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Text("\(pl.trackKeys.count) tracks")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(BT.textTertiary)
                }
            }
            Button {
                confirmRestore = true
            } label: {
                Text("Restore Backup")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.white)
                    .padding(.vertical, 13)
                    .background(BT.gradient, in: Capsule())
            }
        }
        .padding(18)
        .btCard()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(BT.gradient)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(BT.textSecondary)
                .textCase(.uppercase)
        }
    }

    private var safetyNote: some View {
        Text("Restore never deletes or overwrites anything: tracks already in your library are matched by title + artist and left untouched. Entries whose audio file is not on this device are restored as metadata-only so you can see what's missing.")
            .font(.system(size: 11.5))
            .foregroundStyle(BT.textTertiary)
            .padding(.horizontal, 8)
    }
}
