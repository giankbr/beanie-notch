import AVFoundation

// Background sound for focusing, made on the fly rather than shipped as recordings, so it adds nothing to the
// download. Noise shaped three ways, rain as noise with drops in it, and waves as noise that swells and falls.
@MainActor
final class Ambient: ObservableObject {
    enum Sound: String, CaseIterable, Identifiable {
        case rain, waves, brown, white
        var id: String { rawValue }
        var title: String { rawValue.capitalized + (self == .brown || self == .white ? " noise" : "") }
    }

    @Published private(set) var playing: Sound?
    private var engine: AVAudioEngine?

    func play(_ sound: Sound, volume: Float = 0.5) {
        guard playing != sound else { return }
        stop()
        let engine = AVAudioEngine()
        let format = engine.outputNode.inputFormat(forBus: 0)
        let rate = format.sampleRate
        let generator = AmbientGenerator(sound: sound, rate: rate)
        let source = AVAudioSourceNode { _, _, frames, buffers -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(buffers)
            for frame in 0..<Int(frames) {
                let value = generator.next()
                for buffer in list {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value
                }
            }
            return noErr
        }
        let mono = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: mono)
        engine.mainMixerNode.outputVolume = 0
        guard (try? engine.start()) != nil else { return }
        self.engine = engine
        playing = sound
        fade(engine.mainMixerNode, to: volume)
    }

    func stop() {
        engine?.stop()
        engine = nil
        playing = nil
    }

    // In over a second and a half, so it doesn't start with a burst.
    private func fade(_ mixer: AVAudioMixerNode, to target: Float, step: Int = 0) {
        guard step < 30, engine?.mainMixerNode === mixer else { return }
        mixer.outputVolume = target * Float(step + 1) / 30
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated { self?.fade(mixer, to: target, step: step + 1) }
        }
    }
}

// Runs on the audio thread: plain state, no locks, nothing allocated per sample.
final class AmbientGenerator: @unchecked Sendable {
    let sound: Ambient.Sound
    let rate: Double
    private var seed: UInt64 = 0x9E3779B97F4A7C15
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
    private var brown: Float = 0
    private var drop: Float = 0, dropTone: Float = 0, dropPhase: Float = 0
    private var low: Float = 0
    private var t: Double = 0

    init(sound: Ambient.Sound, rate: Double) {
        self.sound = sound
        self.rate = rate
    }

    private func white() -> Float {
        seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
        return Float(seed % 2_000_001) / 1_000_000 - 1
    }

    // Paul Kellet's refined pink noise filter.
    private func pink() -> Float {
        let w = white()
        b0 = 0.99886 * b0 + w * 0.0555179; b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520; b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522; b5 = -0.7616 * b5 - w * 0.0168980
        let p = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
        b6 = w * 0.115926
        return p * 0.11
    }

    private func brownNoise() -> Float {
        brown = (brown + 0.02 * white()) / 1.02
        return brown * 3.5
    }

    func next() -> Float {
        t += 1 / rate
        switch sound {
        case .white:
            return white() * 0.25
        case .brown:
            return brownNoise()
        case .waves:
            // A swell every eight seconds or so, never quite silent between them.
            let swell = Float(0.5 + 0.5 * sin(2 * Double.pi * t / 8.3))
            low += 0.04 * (pink() - low)
            return brownNoise() * (0.25 + 0.75 * swell * swell) + low * 0.6 * swell
        case .rain:
            // A steady hiss with drops landing in it at random: each a short, fading tick.
            if white() > 0.9993 {
                drop = 0.25 + 0.35 * abs(white())
                dropTone = 0.15 + 0.25 * abs(white())
            }
            dropPhase += dropTone
            let tick = drop * sin(dropPhase)
            drop *= 0.9965
            let hiss = pink() - low
            low += 0.02 * (hiss - low)
            return hiss * 0.55 + tick * 0.35 + brownNoise() * 0.25
        }
    }
}
