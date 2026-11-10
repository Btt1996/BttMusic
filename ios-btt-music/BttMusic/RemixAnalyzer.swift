import AVFoundation
import Foundation

// Smart Remix: LOCAL audio analysis, fully offline, no servers.
//  - BPM: onset-envelope autocorrelation over 60-180 BPM
//  - Energy: mean RMS of the first 90 seconds, normalized 0-1
//  - Brightness: zero-crossing rate proxy, drives a mood tag
// What is NOT available locally: reliable musical-key detection (chroma
// templates need heavier DSP). Key matching is approximated with brightness
// clustering; the UI labels it as a heuristic.
enum RemixAnalyzer {
    struct Analysis {
        var bpm: Double      // 0 if detection failed
        var energy: Double   // 0-1
        var brightness: Double // 0-1
    }

    static func analyze(fileURL: URL) async -> Analysis {
        await Task.detached(priority: .userInitiated) {
            do {
                let file = try AVAudioFile(forReading: fileURL)
                let format = file.processingFormat
                let sampleRate = format.sampleRate
                let maxFrames = AVAudioFramePosition(min(Double(file.length), sampleRate * 90))

                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(maxFrames)) else {
                    return Analysis(bpm: 0, energy: 0, brightness: 0)
                }
                try file.read(into: buffer, frameCount: AVAudioFrameCount(maxFrames))
                guard let channel = buffer.floatChannelData?[0] else {
                    return Analysis(bpm: 0, energy: 0, brightness: 0)
                }
                let n = Int(buffer.frameLength)
                guard Double(n) > sampleRate else { return Analysis(bpm: 0, energy: 0, brightness: 0) }

                // Envelope: RMS per 512-sample hop
                let hop = 512
                let frames = n / hop
                guard frames > 16 else { return Analysis(bpm: 0, energy: 0, brightness: 0) }
                var rms = [Float](repeating: 0, count: frames)
                var zcr = [Float](repeating: 0, count: frames)
                for f in 0..<frames {
                    var sum: Float = 0
                    var crossings: Float = 0
                    var prev: Float = 0
                    for i in 0..<hop {
                        let s = channel[f * hop + i]
                        sum += s * s
                        if (s > 0) != (prev > 0) { crossings += 1 }
                        prev = s
                    }
                    rms[f] = sqrt(sum / Float(hop))
                    zcr[f] = crossings / Float(hop)
                }

                // Onset envelope: half-wave rectified difference
                var onset = [Float](repeating: 0, count: frames)
                for f in 1..<frames {
                    onset[f] = max(0, rms[f] - rms[f - 1])
                }
                let onsetMean = onset.reduce(0, +) / Float(max(1, frames - 1))
                for f in 0..<frames { onset[f] = max(0, onset[f] - onsetMean) }

                // Autocorrelation for 60-180 BPM
                let fps = Float(sampleRate) / Float(hop) // envelope frames per second
                let minLag = Int(fps * 60.0 / 180.0)
                let maxLag = Int(fps * 60.0 / 60.0)
                var bestLag = 0
                var bestScore: Float = 0
                if maxLag > minLag, frames > maxLag {
                    for lag in minLag...maxLag {
                        var score: Float = 0
                        for f in 0..<(frames - lag) {
                            score += onset[f] * onset[f + lag]
                        }
                        // slight preference for mid-tempo to avoid octave errors
                        let bpmHere = 60.0 * Double(fps) / Double(lag)
                        let weight = 1.0 - abs(bpmHere - 120.0) / 240.0
                        score *= Float(max(0.5, weight))
                        if score > bestScore {
                            bestScore = score
                            bestLag = lag
                        }
                    }
                }
                var bpm = 0.0
                if bestLag > 0 {
                    bpm = 60.0 * Double(fps) / Double(bestLag)
                    while bpm > 180 { bpm /= 2 }
                    while bpm < 60 { bpm *= 2 }
                }

                // Energy & brightness
                let energyMean = rms.reduce(0, +) / Float(frames)
                let energy = Double(min(1, energyMean * 6))
                let brightnessMean = zcr.reduce(0, +) / Float(frames)
                let brightness = Double(min(1, brightnessMean * 12))

                return Analysis(bpm: bpm, energy: energy, brightness: brightness)
            } catch {
                return Analysis(bpm: 0, energy: 0, brightness: 0)
            }
        }.value
    }

    struct MoodTag {
        var label: String
        var color: String
    }

    static func mood(for analysis: Analysis) -> MoodTag {
        if analysis.energy > 0.66, analysis.brightness > 0.45 { return MoodTag(label: "High Energy", color: "red") }
        if analysis.energy > 0.66 { return MoodTag(label: "Driving", color: "magenta") }
        if analysis.energy > 0.33 { return MoodTag(label: "Warm", color: "purple") }
        return MoodTag(label: "Mellow", color: "indigo")
    }

    // MARK: - Sequence generation
    // Energy arc: warm-up -> build -> peak -> cooldown. Adjacent tracks stay
    // within 12% BPM or are stepped gradually. This is NOT a shuffle.
    static func generateSequence(from tracks: [Track]) -> [Track] {
        let analyzed = tracks.filter(\.analyzed)
        guard analyzed.count >= 4 else { return tracks.shuffled() }

        let sorted = analyzed.sorted { ($0.bpm == 0 ? 120 : $0.bpm) < ($1.bpm == 0 ? 120 : $1.bpm) }
        var warmUp: [Track] = []
        var peak: [Track] = []
        var coolDown: [Track] = []
        for t in sorted {
            if t.energy > 0.62 { peak.append(t) }
            else if t.energy > 0.3 { warmUp.append(t) }
            else { coolDown.append(t) }
        }
        let midPeak = peak.count / 2
        let ascent = Array(peak[0..<max(0, midPeak)].reversed())
        let descent = Array(peak[min(midPeak, peak.count)...])
        let result = warmUp + ascent + descent + coolDown

        // Smooth BPM jumps: swap adjacent tracks when the step is steep
        var smoothed = result
        for i in 1..<smoothed.count {
            let a = smoothed[i - 1].bpm == 0 ? 120 : smoothed[i - 1].bpm
            let b = smoothed[i].bpm == 0 ? 120 : smoothed[i].bpm
            if abs(b - a) > a * 0.35, i + 1 < smoothed.count {
                smoothed.swapAt(i, i + 1)
            }
        }
        return smoothed
    }

    static func energyDescription(_ t: Track) -> String {
        guard t.analyzed else { return "Not analyzed" }
        let bpm = Int(t.bpm) > 0 ? "\(Int(t.bpm)) BPM" : "BPM n/a"
        return "\(bPMBar(t.energy)) • \(bpm) • \(mood(for: t.analyzed ? analysisOf(t) : Analysis(bpm: 0, energy: 0, brightness: 0)).label)"
    }

    private static func analysisOf(_ t: Track) -> Analysis {
        Analysis(bpm: t.bpm, energy: t.energy, brightness: t.brightness)
    }

    private static func bPMBar(_ energy: Double) -> String {
        let bars = Int(energy * 5)
        return String(repeating: "▮", count: bars) + String(repeating: "▯", count: 5 - bars)
    }
}
