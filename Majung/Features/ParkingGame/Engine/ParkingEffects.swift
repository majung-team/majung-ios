import Foundation
import AVFoundation

// Short generated chimes: no downloaded assets, off-main-thread audio session, no interruption to other audio.
final class ParkingEffects: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.majung.ios.parking.audio", qos: .userInitiated)
    private var player: AVAudioPlayer?
    private var sessionActive = false

    func play(success: Bool) {
        let wave = Self.makeWave(success: success)
        queue.async { [weak self] in
            guard let self else { return }
            self.player?.stop()
            self.player = nil
            do {
                let session = AVAudioSession.sharedInstance()
                if !self.sessionActive {
                    try session.setCategory(.ambient, mode: .default)
                    try session.setActive(true)
                    self.sessionActive = true
                }
                let nextPlayer = try AVAudioPlayer(data: wave)
                nextPlayer.play()
                self.player = nextPlayer
            } catch {
                self.player = nil
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            let hadPlayer = self.player != nil
            self.player?.stop()
            self.player = nil
            guard self.sessionActive || hadPlayer else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            self.sessionActive = false
        }
    }

    private static func makeWave(success: Bool) -> Data {
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
        return wave
    }
}

