import SwiftData
import SwiftUI

struct RemixView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AudioEngine.self) private var audio
    @Binding var showPlayer: Bool

    @State private var sequence: [Track]?
    @State private var analyzing = false
    @State private var showEnergy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    explanationCard
                    analyzeCard
                    if let sequence {
                        sequenceCard(sequence)
                    }
                }
                .padding(16)
            }
            .background(BT.canvas)
            .navigationTitle("Smart Remix")
        }
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Real local analysis — not a shuffle", systemImage: "waveform.badge.magnifyingglass")
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text("Every track is analyzed on-device: BPM via onset-envelope autocorrelation (60–180), energy from mean RMS, and brightness from zero-crossing rate as a mood heuristic. True musical-key detection isn't practical with light DSP, so key matching is approximated by brightness clustering. Sequences follow an energy arc: warm-up → build → peak → cooldown, keeping adjacent BPM within 12%.")
                .font(.system(size: 13))
                .foregroundStyle(BT.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .btCard()
    }

    private var analyzeCard: some View {
        let (done, total) = library.analysisProgress
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Library analysis")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Text("\(done)/\(total)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(BT.magenta)
            }
            ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                .tint(BT.gradient)
            HStack(spacing: 12) {
                Button {
                    analyzing = true
                    Task {
                        for track in library.tracks where !track.analyzed {
                            await library.analyze(track)
                        }
                        analyzing = false
                    }
                } label: {
                    Label(analyzing ? "Analyzing…" : "Analyze All", systemImage: "waveform")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(BT.gradient, in: Capsule())
                }
                .disabled(analyzing || library.tracks.isEmpty)
                Button {
                    let seq = RemixAnalyzer.generateSequence(from: library.tracks)
                    sequence = seq
                } label: {
                    Label("Build Sequence", systemImage: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(BT.magenta)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(BT.magenta.opacity(0.14), in: Capsule())
                }
                .disabled(done < 4)
            }
        }
        .padding(18)
        .btCard()
    }

    private func sequenceCard(_ sequence: [Track]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Remix sequence (\(sequence.count))")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Button {
                    let name = "Remix " + DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
                    library.createPlaylist(name: name, tracks: sequence, isRemix: true)
                    library.statusMessage = "Saved as \"\(name)\""
                } label: {
                    Text("Save as Playlist")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(BT.gradient, in: Capsule())
                }
            }
            ForEach(Array(sequence.enumerated()), id: \.element.id) { index, track in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(BT.textTertiary)
                        .frame(width: 20)
                    TrackArtwork(artworkData: track.artworkData, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(remixMeta(track))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(BT.textSecondary)
                    }
                    Spacer()
                    if showEnergy {
                        EnergyBar(value: track.energy)
                            .frame(width: 44)
                    }
                }
                .contentShape(.rect)
                .onTapGesture {
                    audio.play(sequence, index: index)
                    showPlayer = true
                }
            }
        }
        .padding(18)
        .btCard()
    }

    private func remixMeta(_ track: Track) -> String {
        guard track.analyzed else { return "not analyzed" }
        let bpm = track.bpm > 0 ? "\(Int(track.bpm)) BPM" : "BPM n/a"
        return "\(bpm) · E \(String(format: "%.2f", track.energy)) · \(RemixAnalyzer.mood(for: .init(bpm: track.bpm, energy: track.energy, brightness: track.brightness)).label)"
    }
}

struct EnergyBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule().fill(BT.gradient).frame(width: geo.size.width * value)
            }
        }
        .frame(height: 5)
    }
}
