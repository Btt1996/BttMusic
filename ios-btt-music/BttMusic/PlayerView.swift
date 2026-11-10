import SwiftUI

struct PlayerView: View {
    @Environment(AudioEngine.self) private var audio
    @Environment(\.dismiss) private var dismiss
    @State private var showQueue = false
    @State private var showMixer = false
    @State private var scrubbing = false
    @State private var scrubValue = 0.0

    private var progress: Double {
        let d = audio.currentTrack?.duration ?? 0
        return d > 0 ? (scrubbing ? scrubValue : audio.currentTime) / d : 0
    }

    var body: some View {
        ZStack {
            // Ambient backdrop from the artwork
            Color.black.ignoresSafeArea()
            if let data = audio.currentTrack?.artworkData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .blur(radius: 70)
                    .opacity(0.35)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 12)
                artwork
                Spacer(minLength: 12)
                titles
                scrubber
                controls
                secondaryControls
                Spacer(minLength: 8)
                if audio.boosterEnabled, audio.boostPercent > 100 {
                    boostBadge
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showQueue) { QueueSheet() }
        .sheet(isPresented: $showMixer) { MixerSheet() }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(BT.textSecondary)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            VStack(spacing: 0) {
                Text("NOW PLAYING")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(BT.textTertiary)
                Text(sourceLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BT.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                showMixer = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(BT.textSecondary)
                    .frame(width: 44, height: 44)
            }
        }
    }

    private var sourceLabel: String {
        switch audio.currentTrack?.source {
        case .telegram: "TELEGRAM"
        case .x2: "X2 ACQUISITION"
        default: "LOCAL LIBRARY"
        }
    }

    private var artwork: some View {
        TrackArtwork(artworkData: audio.currentTrack?.artworkData, size: 300)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .shadow(color: BT.magenta.opacity(0.35), radius: 40, y: 14)
            .scaleEffect(audio.isPlaying ? 1 : 0.94)
            .animation(.spring(response: 0.55, dampingFraction: 0.75), value: audio.isPlaying)
    }

    private var titles: some View {
        VStack(spacing: 5) {
            Text(audio.currentTrack?.title ?? "Nothing playing")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(audio.currentTrack?.artist ?? "")
                .font(.system(size: 16))
                .foregroundStyle(BT.textSecondary)
                .lineLimit(1)
        }
        .padding(.bottom, 16)
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14)).frame(height: 6)
                    Capsule().fill(BT.gradient).frame(width: geo.size.width * progress, height: 6)
                }
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            scrubbing = true
                            scrubValue = min(1, max(0, v.location.x / geo.size.width)) * (audio.currentTrack?.duration ?? 0)
                        }
                        .onEnded { v in
                            let target = min(1, max(0, v.location.x / geo.size.width)) * (audio.currentTrack?.duration ?? 0)
                            audio.seek(to: target)
                            scrubbing = false
                        }
                )
            }
            .frame(height: 6)
            HStack {
                Text(timeLabel(scrubbing ? scrubValue : audio.currentTime))
                Spacer()
                Text(timeLabel(audio.currentTrack?.duration ?? 0))
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(BT.textTertiary)
        }
        .padding(.bottom, 18)
    }

    private func timeLabel(_ t: Double) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }

    private var controls: some View {
        HStack(spacing: 34) {
            Button {
                audio.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 26, weight: .bold))
            }
            Button {
                audio.togglePlayPause()
            } label: {
                ZStack {
                    Circle().fill(BT.gradient).frame(width: 78, height: 78)
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: audio.isPlaying ? 0 : 2)
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: audio.isPlaying)
            Button {
                audio.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 26, weight: .bold))
            }
        }
        .foregroundStyle(.white)
        .padding(.bottom, 18)
    }

    private var secondaryControls: some View {
        HStack(spacing: 40) {
            Button {
                audio.shuffle.toggle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(audio.shuffle ? AnyShapeStyle(BT.gradient) : AnyShapeStyle(BT.textSecondary))
            }
            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(BT.textSecondary)
            }
            switch audio.repeatMode {
            case .off:
                Button { audio.repeatMode = .all } label: {
                    Image(systemName: "repeat").font(.system(size: 15, weight: .bold)).foregroundStyle(BT.textSecondary)
                }
            case .all:
                Button { audio.repeatMode = .one } label: {
                    Image(systemName: "repeat").font(.system(size: 15, weight: .bold)).foregroundStyle(BT.gradient)
                }
            case .one:
                Button { audio.repeatMode = .off } label: {
                    Image(systemName: "repeat.1").font(.system(size: 15, weight: .bold)).foregroundStyle(BT.gradient)
                }
            }
        }
    }

    private var boostBadge: some View {
        Text("BOOST \(Int(audio.boostPercent))%")
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(BT.gradient, in: Capsule())
    }
}

// MARK: - Queue sheet
struct QueueSheet: View {
    @Environment(AudioEngine.self) private var audio
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(audio.queue.enumerated()), id: \.element.id) { index, track in
                    HStack(spacing: 12) {
                        if index == audio.queueIndex {
                            Image(systemName: audio.isPlaying ? "waveform" : "speaker.wave.2.fill")
                                .foregroundStyle(BT.magenta)
                                .frame(width: 22)
                        } else {
                            Text("\(index + 1)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(BT.textTertiary)
                                .frame(width: 22)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            Text(track.artist).font(.system(size: 12)).foregroundStyle(BT.textSecondary).lineLimit(1)
                        }
                        Spacer()
                        Text(TrackRow.format(track.duration))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(BT.textTertiary)
                    }
                    .contentShape(.rect)
                    .onTapGesture {
                        audio.play(audio.queue, index: index)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            audio.removeFromQueue(at: index)
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(BT.surface)
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Mixer sheet (volume, boost, EQ, crossfade, limiter)
struct MixerSheet: View {
    @Environment(AudioEngine.self) private var audio
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var audio = audio
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    mixerSection("Volume") {
                        Slider(value: $audio.volume, in: 0...1) { editing in
                            if !editing { audio.applyVolume() }
                        }
                        .tint(BT.magenta)
                    }
                    mixerSection("Volume Booster") {
                        Text("Up to 300% digital gain (+9.5 dB). Digital gain raises amplitude — perceived loudness rises less, and the limiter catches peaks to prevent clipping distortion.")
                            .font(.system(size: 12))
                            .foregroundStyle(BT.textSecondary)
                        Toggle(isOn: Binding(
                            get: { audio.boosterEnabled },
                            set: { audio.setBooster($0) }
                        )) {
                            Text("Enable booster")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .tint(BT.magenta)
                        if audio.boosterEnabled {
                            Slider(value: $audio.boostPercent, in: 100...300, step: 10) { editing in
                                if !editing { audio.applyEQ() }
                            }
                            .tint(BT.gradient)
                            Text("\(Int(audio.boostPercent))%")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(BT.magenta)
                        }
                    }
                    mixerSection("Equalizer") {
                        EQDial(label: "Bass", value: $audio.bassGain)
                        EQDial(label: "Treble", value: $audio.trebleGain)
                    }
                    mixerSection("Crossfade") {
                        Slider(value: $audio.crossfadeDuration, in: 0...10, step: 1)
                        .tint(BT.purple)
                        Text(audio.crossfadeDuration == 0 ? "Off" : "\(Int(audio.crossfadeDuration)) s seamless blend")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(BT.textSecondary)
                    }
                    mixerSection("Limiter") {
                        Toggle(isOn: Binding(
                            get: { audio.limiterEnabled },
                            set: { audio.setLimiter($0) }
                        )) {
                            Text("Clipping protection")
                                .font(.system(size: 14))
                        }
                        .tint(BT.magenta)
                    }
                }
                .padding(20)
            }
            .background(BT.canvas)
            .navigationTitle("Sound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func mixerSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(BT.textSecondary)
                .textCase(.uppercase)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .btCard()
    }
}

struct EQDial: View {
    @Environment(AudioEngine.self) private var audio
    let label: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .frame(width: 56, alignment: .leading)
            Button {
                value = 0
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(BT.textTertiary)
            }
            Spacer()
            Slider(value: Binding(
                get: { value },
                set: { value = $0 }
            ), in: -12...12)
            .tint(value > 0 ? BT.magenta : BT.purple)
            Text("\(value >= 0 ? "+" : "")\(Int(value)) dB")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(BT.textSecondary)
                .frame(width: 64, alignment: .trailing)
        }
    }
}
