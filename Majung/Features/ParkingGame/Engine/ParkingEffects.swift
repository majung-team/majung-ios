import Foundation
import AVFoundation

// Short generated chimes: no downloaded assets and no interruption to other audio.
@MainActor
final class ParkingEffects {
    private var player: AVAudioPlayer?

    func play(success: Bool) {
        stop()
        let rate = 22_050
        let duration = success ? 0.28 : 0.14
        let count = Int(Double(rate) * duration)
        var pcm = Data()
        for index in 0..<count {
            let time = Double(index) / Double(rate)
            let frequency = success ? (time < 0.14 ? 660.0 : 880.0) : 220.0
            let local = success ? time.truncatingRemainder(dividingBy: 0.14) : time
            let envelope = min(1, local / 0.008) * max(0, 1 - local / 0.14)
            var value = Int16(sin(time * frequency * 2 * .pi) * envelope * 3_000).littleEndian
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }
        var wave = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ number: T) {
            var value = number.littleEndian
            withUnsafeBytes(of: &value) { wave.append(contentsOf: $0) }
        }
        append(UInt32(36 + pcm.count)); wave.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16))
        wave.append(Data("data".utf8)); append(UInt32(pcm.count)); wave.append(pcm)
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(data: wave)
            player?.play()
        } catch { player = nil }
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

