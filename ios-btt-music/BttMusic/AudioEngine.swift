import AVFoundation
import AudioToolbox
import MediaPlayer
import UIKit

// The native audio engine: AVAudioEngine graph
//   playerA / playerB (crossfade pair) -> EQ (bass + treble) -> PeakLimiter -> mainMixer
// Boost to 300% is implemented as PeakLimiter PreGain (+9.5 dB max): the gain
// is applied and the same unit catches the peaks, which prevents clipping.
// Handles background audio, remote commands, interruptions, route changes.
@MainActor
@Observable
final class AudioEngine {
    // PeakLimiter AudioUnit parameter ids (AudioUnitParameters.h)
    private enum LimiterParam {
        static let attackTime: AudioUnitParameterID = 0
        static let decayTime: AudioUnitParameterID = 1
        static let preGain: AudioUnitParameterID = 2
        static let threshold: AudioUnitParameterID = 3
    }

    // MARK: - Graph nodes
    private let engine = AVAudioEngine()
    private let playerA = AVAudioPlayerNode()
    private let playerB = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 2)
    private let limiter: AVAudioUnitEffect = {
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        return AVAudioUnitEffect(audioComponentDescription: desc)
    }()

    // MARK: - State
    private(set) var isPlaying = false
    private(set) var queue: [Track] = []
    private(set) var queueIndex: Int = 0
    private(set) var currentTrack: Track?
    var shuffle = false { didSet { persistState() } }
    enum RepeatMode: String { case off, all, one }
    var repeatMode: RepeatMode = .off { didSet { persistState() } }
    var crossfadeDuration: Double {
        get { UserDefaults.standard.object(forKey: "bt.crossfade") as? Double ?? 4 }
        set {
            UserDefaults.standard.set(newValue, forKey: "bt.crossfade")
            persistState()
        }
    }
    var volume: Double = 1.0 { didSet { applyVolume() } }   // app volume 0...1
    var boostPercent: Double {
        get { UserDefaults.standard.object(forKey: "bt.boost") as? Double ?? 150 }
        set {
            let clamped = min(300, max(100, newValue))
            UserDefaults.standard.set(clamped, forKey: "bt.boost")
            applyEQ()
            persistState()
        }
    }
    // Booster is DISABLED by default; playback is bit-identical to the
    // unprocessed graph while it is off.
    var boosterEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "bt.boosterEnabled") as? Bool ?? false }
        set {
            UserDefaults.standard.set(newValue, forKey: "bt.boosterEnabled")
            applyEQ()
            persistState()
        }
    }
    var bassGain: Double {
        get { UserDefaults.standard.object(forKey: "bt.bass") as? Double ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: "bt.bass"); applyEQ() }
    }
    var trebleGain: Double {
        get { UserDefaults.standard.object(forKey: "bt.treble") as? Double ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: "bt.treble"); applyEQ() }
    }
    var limiterEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "bt.limiter") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "bt.limiter")
            applyEQ()
        }
    }

    private(set) var currentTime: TimeInterval = 0
    private var activePlayer: AVAudioPlayerNode?
    private var activeFileOffset: TimeInterval = 0
    private var activeFile: AVAudioFile?
    private var fading = false
    private var heartbeat: Timer?
    private var wasPlayingBeforeInterruption = false
    private var history: [Int] = []

    // MARK: - Init
    init() {
        configureGraph()
        configureSession()
        setupRemoteCommands()
        observeInterruptions()
        observeRouteChanges()
        restoreState()
    }

    private func configureGraph() {
        engine.attach(playerA)
        engine.attach(playerB)
        engine.attach(eq)
        engine.attach(limiter)

        let bass = eq.bands[0]
        bass.filterType = .lowShelf
        bass.frequency = 120
        bass.bypass = false

        let treble = eq.bands[1]
        treble.filterType = .highShelf
        treble.frequency = 8000
        treble.bypass = false

        setLimiterParam(LimiterParam.threshold, -1.0)
        setLimiterParam(LimiterParam.attackTime, 0.003)
        setLimiterParam(LimiterParam.decayTime, 0.05)

        engine.connect(playerA, to: eq, format: nil)
        engine.connect(playerB, to: eq, format: nil)
        engine.connect(eq, to: limiter, format: nil)
        engine.connect(limiter, to: engine.mainMixerNode, format: nil)
        applyEQ()
        applyVolume()
    }

    private func setLimiterParam(_ key: AudioUnitParameterID, _ value: Float) {
        AudioUnitSetParameter(limiter.audioUnit, key, kAudioUnitScope_Global, 0, value, 0)
    }

    func applyEQ() {
        // 300% boost == +9.54 dB of digital gain. Digital gain raises amplitude,
        // not perceived loudness threefold; the limiter catches the peaks.
        let boosting = boosterEnabled && boostPercent > 100
        if boosting {
            setLimiterParam(LimiterParam.preGain, Float(20 * log10(boostPercent / 100)))
            limiter.bypass = false   // protection must stay engaged while boosting
        } else {
            setLimiterParam(LimiterParam.preGain, 0)
            limiter.bypass = !limiterEnabled
        }
        eq.bands[0].gain = Float(bassGain)
        eq.bands[1].gain = Float(trebleGain)
    }

    func setLimiter(_ on: Bool) { limiterEnabled = on }

    func setBooster(_ on: Bool) { boosterEnabled = on }

    // Introspection (used by tests): the PreGain actually set on the limiter unit.
    var appliedPreGainDB: Float {
        var value: Float = 0
        AudioUnitGetParameter(limiter.audioUnit, LimiterParam.preGain, kAudioUnitScope_Global, 0, &value)
        return value
    }
    var limiterBypassed: Bool { limiter.bypass }

    func applyVolume() {
        activePlayer?.volume = Float(volume)
        (activePlayer === playerA ? playerB : playerA).volume = 0
    }

    private func configureSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    // MARK: - Playback
    func play(_ tracks: [Track], index: Int) {
        queue = tracks
        queueIndex = index
        history = []
        startCurrent()
    }

    func play(_ track: Track) {
        if let idx = queue.firstIndex(where: { $0.id == track.id }) {
            play(queue, index: idx)
        } else {
            play([track], index: 0)
        }
    }

    private func startCurrent() {
        guard queue.indices.contains(queueIndex) else { return }
        let track = queue[queueIndex]
        guard track.fileExists else { return }
        do {
            try engine.start()
        } catch {
            print("Engine start error: \(error)")
            return
        }
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: track.fileURL)
        } catch {
            print("File open error: \(error)")
            return
        }
        stopPlayers()
        let player = playerA
        player.volume = Float(volume)
        player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.playerDidFinish() }
        }
        player.play()
        activePlayer = player
        activeFile = file
        activeFileOffset = 0
        currentTime = 0
        currentTrack = track
        track.playCount += 1
        isPlaying = true
        updateNowPlaying()
        startHeartbeat()
        persistState()
    }

    private func stopPlayers() {
        for p in [playerA, playerB] {
            p.stop()
            p.volume = 0
        }
    }

    private func playerDidFinish() {
        guard isPlaying, !fading else { return }
        advance(by: 1, auto: true)
    }

    func togglePlayPause() {
        guard let player = activePlayer, currentTrack != nil else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            try? engine.start()
            player.play()
            isPlaying = true
        }
        updateNowPlaying()
    }

    func seek(to time: TimeInterval) {
        guard let track = currentTrack, track.fileExists else { return }
        let player = activePlayer ?? playerA
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: track.fileURL) } catch { return }
        player.stop()
        let sampleRate = file.processingFormat.sampleRate
        let start = max(0, AVAudioFramePosition(time * sampleRate))
        let totalFrames = AVAudioFrameCount(max(0, file.length - start))
        player.scheduleSegment(file, startingFrame: start, frameCount: totalFrames, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.playerDidFinish() }
        }
        player.play()
        activeFile = file
        activeFileOffset = time
        currentTime = time
        if isPlaying { updateNowPlaying() }
    }

    func next() { advance(by: 1, auto: false) }

    func previous() {
        if currentTime > 3 {
            seek(to: 0)
        } else {
            advance(by: -1, auto: false)
        }
    }

    private func advance(by delta: Int, auto: Bool) {
        guard !queue.isEmpty else { return }
        if auto, repeatMode == .one {
            startCurrent()
            return
        }
        var nextIndex = queueIndex + delta
        if shuffle, delta == 1, queue.count > 1 {
            var candidate = queueIndex
            while candidate == queueIndex { candidate = Int.random(in: 0..<queue.count) }
            nextIndex = candidate
        }
        if nextIndex >= queue.count {
            if repeatMode == .all { nextIndex = 0 } else {
                isPlaying = false
                currentTime = 0
                updateNowPlaying()
                return
            }
        }
        if nextIndex < 0 { nextIndex = queue.count - 1 }
        history.append(queueIndex)
        queueIndex = nextIndex
        startCurrent()
    }

    func removeFromQueue(at index: Int) {
        guard queue.indices.contains(index) else { return }
        queue.remove(at: index)
        if index < queueIndex { queueIndex -= 1 }
    }

    func insertInQueue(_ track: Track, after index: Int) {
        let at = min(index + 1, queue.count)
        queue.insert(track, at: at)
    }

    // MARK: - Volume ramping (manual; setVolume(rampDuration:) is unavailable here)
    private var rampTimer: Timer?
    private func ramp(_ player: AVAudioPlayerNode, from: Float, to: Float, duration: Double) {
        rampTimer?.invalidate()
        let steps = max(1, Int(duration / 0.05))
        var step = 0
        let timer = Timer(timeInterval: 0.05, repeats: true) { t in
            step += 1
            let fraction = Float(step) / Float(steps)
            let value = from + (to - from) * fraction
            Task { @MainActor in
                player.volume = value
                if step >= steps { t.invalidate() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        rampTimer = timer
    }

    // MARK: - Crossfade + progress heartbeat
    private func startHeartbeat() {
        heartbeat?.invalidate()
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    private func tick() {
        guard let player = activePlayer, let file = activeFile, currentTrack != nil else { return }
        let rate = file.processingFormat.sampleRate
        let nodeTime = player.lastRenderTime
        var sampleTime: Double = 0
        if let nodeTime, let playerTime = player.playerTime(forNodeTime: nodeTime) {
            sampleTime = Double(playerTime.sampleTime)
        }
        currentTime = activeFileOffset + sampleTime / rate
        if isPlaying {
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        }
        guard isPlaying, !fading, crossfadeDuration > 0.2 else { return }
        let remaining = currentTrackDuration - currentTime
        if remaining <= crossfadeDuration, remaining > 0 {
            beginCrossfade()
        }
    }

    private var currentTrackDuration: TimeInterval { currentTrack?.duration ?? 0 }

    private func beginCrossfade() {
        guard let _ = currentTrack else { return }
        var nextIndex = queueIndex + 1
        if shuffle, queue.count > 1 {
            var candidate = queueIndex
            while candidate == queueIndex { candidate = Int.random(in: 0..<queue.count) }
            nextIndex = candidate
        }
        if nextIndex >= queue.count {
            guard repeatMode == .all else { return }
            nextIndex = 0
        }
        let nextTrack = queue[nextIndex]
        guard nextTrack.fileExists else { return }
        guard let nextFile = try? AVAudioFile(forReading: nextTrack.fileURL) else { return }
        let incoming = activePlayer === playerA ? playerB : playerA
        let outgoing = activePlayer
        fading = true
        incoming.volume = 0.001
        incoming.scheduleFile(nextFile, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.playerDidFinish() }
        }
        incoming.play()
        ramp(incoming, from: 0.001, to: Float(volume), duration: crossfadeDuration)
        if let outgoing {
            ramp(outgoing, from: outgoing.volume, to: 0.001, duration: crossfadeDuration)
        }
        history.append(queueIndex)
        queueIndex = nextIndex
        currentTrack = nextTrack
        nextTrack.playCount += 1
        activePlayer = incoming
        activeFile = nextFile
        activeFileOffset = 0
        currentTime = 0
        updateNowPlaying()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(crossfadeDuration + 0.2))
            outgoing?.stop()
            outgoing?.volume = 0
            self.fading = false
        }
        persistState()
    }

    // MARK: - Now playing + remote commands
    private func updateNowPlaying() {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = currentTrack?.title ?? ""
        info[MPMediaItemPropertyArtist] = currentTrack?.artist ?? ""
        info[MPMediaItemPropertyAlbumTitle] = currentTrack?.album ?? ""
        info[MPMediaItemPropertyPlaybackDuration] = currentTrackDuration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        if let data = currentTrack?.artworkData, let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let pos = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else { return .commandFailed }
            Task { @MainActor in self?.seek(to: pos) }
            return .success
        }
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let info = note.userInfo,
                      let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
                switch type {
                case .began:
                    self?.wasPlayingBeforeInterruption = self?.isPlaying ?? false
                    if let p = self?.activePlayer { p.pause() }
                    self?.isPlaying = false
                    self?.updateNowPlaying()
                case .ended:
                    let optRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    let options = AVAudioSession.InterruptionOptions(rawValue: optRaw)
                    if options.contains(.shouldResume), self?.wasPlayingBeforeInterruption == true {
                        if let p = self?.activePlayer { p.play() }
                        self?.isPlaying = true
                        self?.updateNowPlaying()
                    }
                @unknown default:
                    break
                }
            }
        }
    }

    private func observeRouteChanges() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let info = note.userInfo,
                      let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
                if reason == .oldDeviceUnavailable {
                    // Headphones / AirPods disconnected: pause like Apple Music.
                    if let p = self?.activePlayer { p.pause() }
                    self?.isPlaying = false
                    self?.updateNowPlaying()
                }
            }
        }
    }

    // MARK: - Persistence
    private func persistState() {
        let ids = queue.map(\.id.uuidString)
        UserDefaults.standard.set(ids, forKey: "bt.queue")
        UserDefaults.standard.set(queueIndex, forKey: "bt.queueIndex")
        UserDefaults.standard.set(shuffle, forKey: "bt.shuffle")
        UserDefaults.standard.set(repeatMode.rawValue, forKey: "bt.repeat")
    }

    private func restoreState() {
        shuffle = UserDefaults.standard.bool(forKey: "bt.shuffle")
        repeatMode = RepeatMode(rawValue: UserDefaults.standard.string(forKey: "bt.repeat") ?? "off") ?? .off
    }

    func restoreQueue(tracks: [Track]) {
        guard currentTrack == nil else { return }
        let ids = UserDefaults.standard.stringArray(forKey: "bt.queue") ?? []
        let index = UserDefaults.standard.integer(forKey: "bt.queueIndex")
        guard !ids.isEmpty else { return }
        let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id.uuidString, $0) })
        let restored = ids.compactMap { byID[$0] }
        guard !restored.isEmpty else { return }
        queue = restored
        queueIndex = min(index, restored.count - 1)
        currentTrack = restored[queueIndex]
    }
}
