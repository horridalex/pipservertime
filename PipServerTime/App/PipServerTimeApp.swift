import SwiftUI
import AVFoundation

@main
struct PipServerTimeApp: App {
    @StateObject private var store = ClockStore()

    init() {
        // PiP 를 쓰려면 재생(playback) 오디오 세션이 활성화되어 있어야 합니다.
        // mixWithOthers 로 다른 앱의 음악 재생을 끊지 않습니다.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
