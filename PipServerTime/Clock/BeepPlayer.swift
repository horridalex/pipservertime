import Foundation
import AVFoundation

/// 카운트다운 비프음. 소리 파일 없이 사인파 WAV 를 메모리에서 만들어 재생합니다.
final class BeepPlayer: @unchecked Sendable {
    static let shared = BeepPlayer()

    private var short: AVAudioPlayer?
    private var long: AVAudioPlayer?

    private init() {
        short = try? AVAudioPlayer(data: Self.wav(frequency: 880, duration: 0.08))
        long = try? AVAudioPlayer(data: Self.wav(frequency: 1320, duration: 0.35))
        short?.prepareToPlay()
        long?.prepareToPlay()
    }

    func playShort() { replay(short) }
    func playLong() { replay(long) }

    private func replay(_ p: AVAudioPlayer?) {
        guard let p else { return }
        p.currentTime = 0
        p.play()
    }

    /// 16bit mono PCM WAV
    static func wav(frequency: Double, duration: Double, sampleRate: Double = 44_100) -> Data {
        let count = Int(duration * sampleRate)
        var pcm = Data(capacity: count * 2)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            // 앞뒤 5ms 페이드로 '딱' 소리 방지
            let fade = min(1, min(t, duration - t) / 0.005)
            let v = sin(2 * .pi * frequency * t) * 0.6 * fade
            var s = Int16(max(-1, min(1, v)) * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &s) { pcm.append(contentsOf: $0) }
        }
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count))
        d.append(pcm)
        return d
    }
}
