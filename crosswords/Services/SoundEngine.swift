import AVFoundation
import os

/// Game sound effects, synthesised in real time so the app ships no audio assets.
/// Letters on the wheel play an ascending pentatonic scale; found words resolve into chords.
final class SoundEngine {
    enum Effect {
        case letter(Int)
        case word(length: Int)
        case bonus
        case repeated
        case invalid
        case reveal
        case shuffle
        case coins
        case levelComplete
        case tap
        case unlock
    }

    var isEnabled = true

    private let synth = Synthesizer(sampleRate: 44_100)
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var resetObserver: NSObjectProtocol?
    private var isSessionActive = false
    private var idlePause: Task<Void, Never>?

    /// C major pentatonic, starting at C5.
    private static let scale: [Double] = [523.25, 587.33, 659.25, 783.99, 880.00, 1046.50, 1174.66, 1318.51, 1567.98]
    /// How long the engine keeps running after the last sound; longer than any effect rings.
    private static let idleTimeout: Duration = .seconds(5)

    init() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init)
            MainActor.assumeIsolated {
                switch type {
                case .began:
                    // A call or an alarm took the audio: the system has deactivated the session
                    // and stopped the engine, so both have to start again for the next sound.
                    self?.isSessionActive = false
                    self?.engine?.stop()
                case .ended:
                    self?.prepare()
                default:
                    break
                }
            }
        }
        resetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // The audio server restarted: every engine and node made before is dead, and the
            // session has lost its category. Both are made again for the next sound.
            MainActor.assumeIsolated { self?.discardEngine() }
        }
    }

    private func discardEngine() {
        idlePause?.cancel()
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine = nil
        isSessionActive = false
        prepare()
    }

    func play(_ effect: Effect) {
        guard isEnabled else { return }
        guard startIfNeeded() else { return }
        scheduleIdlePause()
        let s = Self.scale
        switch effect {
        case .letter(let index):
            synth.play([.init(frequency: s[min(index, s.count - 1)], duration: 0.5, volume: 0.32)])
        case .word(let length):
            let top = min(length + 1, s.count - 1)
            synth.play([
                .init(frequency: s[max(0, top - 4)], duration: 0.8, volume: 0.22),
                .init(frequency: s[max(0, top - 2)], delay: 0.06, duration: 0.8, volume: 0.22),
                .init(frequency: s[top], delay: 0.12, duration: 1.0, volume: 0.26),
            ])
        case .bonus:
            synth.play([
                .init(frequency: s[6], duration: 0.4, volume: 0.18, timbre: .bell),
                .init(frequency: s[7], delay: 0.07, duration: 0.4, volume: 0.18, timbre: .bell),
                .init(frequency: s[8], delay: 0.14, duration: 0.6, volume: 0.2, timbre: .bell),
            ])
        case .repeated:
            synth.play([
                .init(frequency: s[2], duration: 0.25, volume: 0.18),
                .init(frequency: s[2], delay: 0.12, duration: 0.3, volume: 0.14),
            ])
        case .invalid:
            synth.play([
                .init(frequency: 196, duration: 0.25, volume: 0.24, timbre: .soft),
                .init(frequency: 174.6, delay: 0.09, duration: 0.3, volume: 0.22, timbre: .soft),
            ])
        case .reveal:
            synth.play((0..<5).map { .init(frequency: s[3 + $0 % 5], delay: Double($0) * 0.045, duration: 0.5,
                                           volume: 0.13, timbre: .bell) })
        case .shuffle:
            synth.play([
                .init(frequency: s[1], duration: 0.15, volume: 0.12, timbre: .soft),
                .init(frequency: s[3], delay: 0.05, duration: 0.15, volume: 0.12, timbre: .soft),
                .init(frequency: s[2], delay: 0.1, duration: 0.2, volume: 0.12, timbre: .soft),
            ])
        case .coins:
            synth.play([
                .init(frequency: 1975.5, duration: 0.25, volume: 0.12, timbre: .bell),
                .init(frequency: 2637.0, delay: 0.08, duration: 0.4, volume: 0.12, timbre: .bell),
            ])
        case .levelComplete:
            let notes = [0, 2, 3, 5, 7]
            var voices = notes.enumerated().map { i, n in
                Synthesizer.Note(frequency: s[n], delay: Double(i) * 0.09, duration: 0.9, volume: 0.2)
            }
            voices += [s[0] / 2, s[2] / 2, s[3] / 2].map {
                Synthesizer.Note(frequency: $0, delay: 0.5, duration: 1.6, volume: 0.16, timbre: .soft)
            }
            synth.play(voices)
        case .tap:
            synth.play([.init(frequency: s[4], duration: 0.12, volume: 0.08, timbre: .soft)])
        case .unlock:
            synth.play([0, 2, 4, 5].enumerated().map { i, n in
                .init(frequency: s[n + 2], delay: Double(i) * 0.08, duration: 0.7, volume: 0.16, timbre: .bell)
            })
        }
    }

    /// Activates the audio session ahead of the first sound, off the main thread: activation
    /// can block for a while. Called whenever the app becomes active.
    func prepare() {
        guard isEnabled, !isSessionActive else { return }
        Task.detached(priority: .userInitiated) {
            let activated = (try? Self.activateSession()) != nil
            await MainActor.run { self.isSessionActive = activated }
        }
    }

    /// Releases the audio hardware while the app is in the background.
    func suspend() {
        idlePause?.cancel()
        engine?.stop()
        isSessionActive = false
    }

    /// Pauses the engine once the last sound has rung out, so the audio hardware can sleep
    /// instead of rendering silence. The next sound starts it again.
    private func scheduleIdlePause() {
        idlePause?.cancel()
        idlePause = Task { [weak self] in
            try? await Task.sleep(for: Self.idleTimeout)
            guard !Task.isCancelled else { return }
            self?.engine?.pause()
        }
    }

    nonisolated private static func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        // Ambient: mixes with the player's music and respects the silent switch.
        try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    private func startIfNeeded() -> Bool {
        if let engine, engine.isRunning { return true }
        do {
            // Normally `prepare()` has done this already.
            if !isSessionActive {
                try Self.activateSession()
                isSessionActive = true
            }
            guard let engine = self.engine ?? makeEngine() else { return false }
            self.engine = engine
            try engine.start()
            return true
        } catch {
            // E.g. the session was deactivated by an interruption; activate it again next time.
            isSessionActive = false
            Logger.audio.error("Audio engine failed to start: \(error.localizedDescription)")
            return false
        }
    }

    private func makeEngine() -> AVAudioEngine? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: synth.sampleRate, channels: 1) else { return nil }
        let engine = AVAudioEngine()
        let source = AVAudioSourceNode(format: format, renderBlock: synth.makeRenderBlock())
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.9
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            // Route changes (e.g. headphones) stop the engine; it restarts on the next sound.
            MainActor.assumeIsolated { self?.engine?.stop() }
        }
        return engine
    }
}

/// The real-time part of the synthesiser. Runs on the audio thread, so it is nonisolated
/// and guards its voices with an unfair lock held only for a few microseconds.
nonisolated final class Synthesizer: @unchecked Sendable {
    enum Timbre { case mallet, bell, soft }

    struct Note {
        var frequency: Double
        var delay: Double = 0
        var duration: Double
        var volume: Double
        var timbre: Timbre = .mallet
    }

    private struct Voice {
        var note: Note
        var phase: Double = 0
        var phase2: Double = 0
        var elapsed: Double
    }

    let sampleRate: Double
    private let lock = OSAllocatedUnfairLock()
    private var voices: [Voice] = []
    private let maxVoices = 24

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        voices.reserveCapacity(maxVoices)
    }

    func play(_ notes: [Note]) {
        lock.withLockUnchecked {
            for note in notes {
                if voices.count >= maxVoices { voices.removeFirst() }
                voices.append(Voice(note: note, elapsed: -note.delay))
            }
        }
    }

    func makeRenderBlock() -> AVAudioSourceNodeRenderBlock {
        { [self] _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let first = buffers.first, let data = first.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            render(into: data, frames: Int(frameCount))
            for buffer in buffers.dropFirst() {
                buffer.mData?.copyMemory(from: data, byteCount: Int(buffer.mDataByteSize))
            }
            return noErr
        }
    }

    private func render(into output: UnsafeMutablePointer<Float>, frames: Int) {
        let dt = 1 / sampleRate
        lock.withLockUnchecked {
            for frame in 0..<frames {
                var sample = 0.0
                for v in voices.indices {
                    voices[v].elapsed += dt
                    let t = voices[v].elapsed
                    guard t >= 0 else { continue }
                    let note = voices[v].note
                    voices[v].phase += note.frequency * dt
                    let attack = note.timbre == .soft ? 0.02 : 0.004
                    let envelope = min(1, t / attack) * exp(-t * (note.timbre == .soft ? 7 : 4.2) / max(0.2, note.duration))
                    let fundamental = sin(2 * .pi * voices[v].phase)
                    var value: Double
                    switch note.timbre {
                    case .mallet:
                        // A marimba-like inharmonic partial that dies away quickly.
                        voices[v].phase2 += note.frequency * 3.9 * dt
                        value = fundamental + 0.25 * sin(2 * .pi * voices[v].phase2) * exp(-t * 18)
                    case .bell:
                        voices[v].phase2 += note.frequency * 2.76 * dt
                        value = fundamental * 0.8 + 0.35 * sin(2 * .pi * voices[v].phase2) * exp(-t * 6)
                    case .soft:
                        value = fundamental * 0.9 + 0.1 * sin(4 * .pi * voices[v].phase)
                    }
                    sample += value * envelope * note.volume
                }
                output[frame] = Float(tanh(sample * 1.2))
            }
            voices.removeAll { $0.elapsed > $0.note.duration * 1.6 + 0.1 }
        }
    }
}

extension Logger {
    nonisolated static let audio = Logger(subsystem: "cz.rob.crosswords", category: "audio")
    nonisolated static let storage = Logger(subsystem: "cz.rob.crosswords", category: "storage")
}
