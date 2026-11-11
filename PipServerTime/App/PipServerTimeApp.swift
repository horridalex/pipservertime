import SwiftUI
import AVFoundation

@main
struct PipServerTimeApp: App {
    @StateObject private var store = ClockStore()
    @StateObject private var network = NetworkMonitor()

    init() {
        // PiP 를 쓰려면 재생(playback) 오디오 세션이 활성화되어 있어야 합니다.
        // mixWithOthers 로 다른 앱의 음악 재생을 끊지 않습니다.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(network)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: ClockStore

    var body: some View {
        ContentView()
            .preferredColorScheme(scheme)
    }

    private var scheme: ColorScheme? {
        switch store.colorMode {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}
