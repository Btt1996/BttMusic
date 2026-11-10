import AVFoundation
import AudioToolbox
import Foundation
import Testing
@testable import BttMusic

// Booster behavior tests: gain values at 100/200/300%, disabled-by-default
// guarantee, and a real offline DSP render proving the limiter prevents
// clipping at 300%.
@MainActor
struct BoosterTests {

    private func resetKeys() {
        for key in ["bt.boosterEnabled", "bt.boost", "bt.limiter", "bt.bass", "bt.treble"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    @Test func boosterIsDisabledByDefault() {
        resetKeys()
        let audio = AudioEngine()
        #expect(audio.boosterEnabled == false, "booster must ship disabled")
        #expect(audio.appliedPreGainDB == 0, "no gain applied while booster is off")
        #expect(audio.limiterBypassed == false, "limiter stays engaged by default")
    }

    @Test func boostPercentMath() {
        resetKeys()
        let audio = AudioEngine()
        audio.setBooster(true)

        audio.boostPercent = 100
        #expect(abs(audio.appliedPreGainDB) < 0.01, "100% must apply 0 dB of gain")

        audio.boostPercent = 200
        #expect(abs(audio.appliedPreGainDB - 6.0206) < 0.01, "200% == +6.02 dB")

        audio.boostPercent = 300
        #expect(abs(audio.appliedPreGainDB - 9.5424) < 0.01, "300% == +9.54 dB")

        // Even with the user's limiter preference OFF, boosting force-enables it.
        audio.setLimiter(false)
        audio.boostPercent = 300
        #expect(audio.limiterBypassed == false, "limiter must stay engaged while boosting")

        // Values clamp to the 100...300 range.
        audio.boostPercent = 900
        #expect(audio.boostPercent == 300)
        audio.boostPercent = 10
        #expect(audio.boostPercent == 100)
    }

    @Test func disablingBoosterRemovesGain() {
        resetKeys()
        let audio = AudioEngine()
        audio.setBooster(true)
        audio.boostPercent = 300
        #expect(audio.appliedPreGainDB > 9)
        audio.setBooster(false)
        #expect(audio.appliedPreGainDB == 0, "turning the booster off restores the clean graph")
        #expect(audio.limiterBypassed == false)
    }
}

// Real DSP render: a full-scale sine through +9.54 dB gain with the SAME
// PeakLimiter configuration the app uses. With the limiter engaged the output
// must stay below full scale; bypassed, the float samples exceed 1.0 — the
// exact clipping the limiter exists to prevent at the device's D/A converter.
@MainActor
struct LimiterRenderTests {

    private func makeLimiter() -> AVAudioUnitEffect {
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        return AVAudioUnitEffect(audioComponentDescription: desc)
    }

    private func render(limiterBypassed: Bool) throws -> Float {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 1)
        eq.bands[0].filterType = .lowPass          // band gain applies regardless of filter type
        eq.bands[0].frequency = 20000
        eq.bands[0].gain = 9.5424                  // +9.54 dB == 300% boost
        eq.bands[0].bypass = false
        let limiter = makeLimiter()

        engine.attach(player)
        engine.attach(eq)
        engine.attach(limiter)
        engine.connect(player, to: eq, format: nil)
        engine.connect(eq, to: limiter, format: nil)
        engine.connect(limiter, to: engine.mainMixerNode, format: nil)

        // Same parameter configuration as AudioEngine.applyEQ()
        for (param, value) in [(0 as AudioUnitParameterID, 0.003 as Float),
                               (1, 0.05),
                               (3, -1.0)] {   // threshold -1 dB
            AudioUnitSetParameter(limiter.audioUnit, param, kAudioUnitScope_Global, 0, value, 0)
        }
        AudioUnitSetParameter(limiter.audioUnit, 2, kAudioUnitScope_Global, 0, 9.5424, 0)
        limiter.bypass = limiterBypassed

        let sampleRate = 44100.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()

        let frames = AVAudioFrameCount(sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        for i in 0..<Int(frames) {
            buffer.floatChannelData![0][i] = sinf(2 * Float.pi * 220 * Float(i) / Float(sampleRate))
        }
        buffer.frameLength = frames

        player.scheduleBuffer(buffer, at: nil)
        player.play()
        let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames * 2)!
        try engine.renderOffline(frames * 2, to: out)

        var peak: Float = 0
        for i in 0..<Int(out.frameLength) {
            peak = max(peak, abs(out.floatChannelData![0][i]))
        }
        return peak
    }

    @Test func limiterPreventsClippingAt300Percent() throws {
        let limitedPeak = try render(limiterBypassed: false)
        #expect(limitedPeak < 0.95,
                "limiter output must stay below full scale at 300% boost, got \(limitedPeak)")

        let bypassedPeak = try render(limiterBypassed: true)
        #expect(bypassedPeak > 1.5,
                "bypassed limiter at 300% must exceed full scale (would clip), got \(bypassedPeak)")
    }
}
