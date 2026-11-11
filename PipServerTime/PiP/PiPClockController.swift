import Foundation
import AVKit
import AVFoundation
import UIKit
import Combine

/// 시계를 AVSampleBufferDisplayLayer 에 그려서 PiP(화면 속 화면)로 띄웁니다.
/// iOS 15+ 의 `AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer:)` 사용.
@MainActor
final class PiPClockController: NSObject, ObservableObject {
    @Published private(set) var isPossible = false
    @Published private(set) var isActive = false
    @Published var showTenths = true { didSet { loop.showTenths = showTenths } }
    @Published var showHost = false { didSet { loop.showHost = showHost } }

    /// 앱 화면 안의 미리보기와 PiP 원본을 겸하는 뷰 (PiP 를 쓰려면 레이어가 화면에 붙어 있어야 함)
    let displayView = SampleBufferView()

    private let loop: ClockFrameLoop
    private var pipController: AVPictureInPictureController?
    private var observations: [NSKeyValueObservation] = []

    init(clock: OffsetClock) {
        loop = ClockFrameLoop(clock: clock, layer: displayView.sampleLayer)
        super.init()
        displayView.sampleLayer.videoGravity = .resizeAspect
        displayView.backgroundColor = .black
        setupPiP()
        loop.start()
    }

    private func setupPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayView.sampleLayer,
                                                                playbackDelegate: self)
        let pip = AVPictureInPictureController(contentSource: source)
        pip.delegate = self
        // 앱을 홈으로 내리면 자동으로 PiP 시작
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        // 실시간 시계이므로 되감기/빨리감기 UI 숨김
        pip.requiresLinearPlayback = true
        pipController = pip

        observations.append(pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] p, _ in
            let v = p.isPictureInPicturePossible
            Task { @MainActor in self?.isPossible = v }
        })
        observations.append(pip.observe(\.isPictureInPictureActive, options: [.initial, .new]) { [weak self] p, _ in
            let v = p.isPictureInPictureActive
            Task { @MainActor in self?.isActive = v }
        })
    }

    func toggle() {
        guard let pip = pipController else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            try? AVAudioSession.sharedInstance().setActive(true)
            pip.startPictureInPicture()
        }
    }
}

/// 백그라운드(PiP 중)에도 돌아가야 하므로 CADisplayLink 대신 GCD 타이머로 프레임을 공급합니다.
/// 표시 문자열이 바뀔 때(0.1초 또는 1초마다)만 새 프레임을 그립니다.
final class ClockFrameLoop: @unchecked Sendable {
    private let clock: OffsetClock
    private let layer: AVSampleBufferDisplayLayer
    private let renderer = ClockFrameRenderer()
    private let queue = DispatchQueue(label: "pip.clock.render", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var lastKey = ""
    private var timebase: CMTimebase?

    private let lock = NSLock()
    private var _showTenths = true
    private var _showHost = false
    var showTenths: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _showTenths }
        set { lock.lock(); _showTenths = newValue; lock.unlock() }
    }
    var showHost: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _showHost }
        set { lock.lock(); _showHost = newValue; lock.unlock() }
    }

    init(clock: OffsetClock, layer: AVSampleBufferDisplayLayer) {
        self.clock = clock
        self.layer = layer
        var tb: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault,
                                        sourceClock: CMClockGetHostTimeClock(),
                                        timebaseOut: &tb)
        if let tb {
            CMTimebaseSetTime(tb, time: .zero)
            CMTimebaseSetRate(tb, rate: 1)
            layer.controlTimebase = tb
            timebase = tb
        }
    }

    func start() {
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        // 5ms 간격으로 확인 → 0.1초 자릿수가 바뀌는 순간과의 지연이 최대 ~5ms
        t.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func tick() {
        let tenths = showTenths
        let subtitle = showHost ? clock.label : nil
        let text = ClockFrameRenderer.text(for: clock.now(), tenths: tenths)
        let key = text + "|" + (subtitle ?? "")
        guard key != lastKey else { return }
        lastKey = key

        if layer.status == .failed { layer.flush() }
        let pts = timebase.map { CMTimebaseGetTime($0) } ?? CMClockGetTime(CMClockGetHostTimeClock())
        if let sb = renderer.makeSampleBuffer(text: text, subtitle: subtitle, pts: pts) {
            layer.enqueue(sb)
        }
    }

    deinit { timer?.cancel() }
}

extension PiPClockController: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                setPlaying playing: Bool) {}

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        // 라이브 콘텐츠로 표시
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController) -> Bool { false }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                skipByInterval skipInterval: CMTime,
                                                completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

extension PiPClockController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: Error) {
        print("PiP 시작 실패:", error)
    }
}

/// AVSampleBufferDisplayLayer 를 기본 레이어로 쓰는 뷰
final class SampleBufferView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    var sampleLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
}
