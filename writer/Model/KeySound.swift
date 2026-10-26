import AVFoundation
import Foundation

/// Soft mechanical-keyboard clicks, synthesized at launch so there are no audio assets to ship.
final class KeySound {
    enum Kind { case key, space, enter, delete }

    static let shared = KeySound()

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Kind: [AVAudioPCMBuffer]] = [:]
    private var nextPlayer = 0
    private var isReady = false

    private func setUp() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else { return }
        buffers[.key] = (0..<4).map { makeClick(format: format, pitch: 1 + Double($0) * 0.06, body: 160, length: 0.045, level: 0.5) }
        buffers[.space] = [makeClick(format: format, pitch: 0.75, body: 110, length: 0.07, level: 0.6)]
        buffers[.enter] = [makeClick(format: format, pitch: 0.6, body: 90, length: 0.1, level: 0.75)]
        buffers[.delete] = [makeClick(format: format, pitch: 1.3, body: 200, length: 0.035, level: 0.4)]
        for _ in 0..<6 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.mainMixerNode.outputVolume = 0.35
        engine.prepare()
        isReady = (try? engine.start()) != nil
    }

    func play(_ kind: Kind) {
        if players.isEmpty { setUp() }
        if !engine.isRunning { isReady = (try? engine.start()) != nil }
        guard isReady, let variants = buffers[kind], let buffer = variants.randomElement() else { return }
        let player = players[nextPlayer % players.count]
        nextPlayer += 1
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    func stop() {
        if engine.isRunning { engine.pause() }
    }

    /// A short filtered noise burst (the "tick") layered over a decaying low sine (the "thock").
    private func makeClick(format: AVAudioFormat, pitch: Double, body: Double, length: Double, level: Float) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(format.sampleRate * length)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        let rate = format.sampleRate
        var lowpass: Float = 0
        let alpha = Float(min(0.9, 0.35 * pitch))
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            let noise = Float.random(in: -1...1)
            lowpass += alpha * (noise - lowpass)
            let tick = lowpass * Float(exp(-t * 900 * pitch))
            let thock = Float(sin(2 * .pi * body * t) * exp(-t * 60))
            samples[i] = (tick * 0.9 + thock * 0.5) * level
        }
        return buffer
    }
}
