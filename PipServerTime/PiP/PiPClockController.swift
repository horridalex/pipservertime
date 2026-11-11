import Foundation
import AVKit
import AVFoundation
import UIKit
import Combine

/// 시계를 AVSampleBufferDisplayLayer 에 그려서 PiP(화면 속 화면)로 띄웁니다.
/// iOS 15+ 의 `AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer:)` 사용.
///
/// PiP 창의 ◀◀ / ▶▶ 버튼은 '시계 미세 조정'으로 씁니다 (설정의 단위만큼 늦추기/앞당기기).
@MainActor
final class PiPClockController: NSObject, ObservableObject {
    @Published private(set) var isPossible = false
    @Published private(set) var isActive = false
    /// 자동으로 닫을 서버시각 (걸려 있으면 화면에 표시)
    @Published private(set) var autoCloseAt: Date?

    /// PiP 앞/뒤 버튼을 눌렀을 때 (true = 앞당기기)
    var onSkip: ((Bool) -> Void)?
    /// PiP 시작 시 호출: 자동으로 닫을 서버시각 (nil = 안 닫음)
    var autoCloseProvider: (() -> Date?)?

    /// 앱 화면 안의 미리보기와 PiP 원본을 겸하는 뷰 (PiP 를 쓰려면 레이어가 화면에 붙어 있어야 함)
    let displayView = SampleBufferView()

    private let loop: ClockFrameLoop
    private var pipController: AVPictureInPictureController?
    private var observations: [NSKeyValueObservation] = []

    init(clock: DisplayClock) {
        loop = ClockFrameLoop(clock: clock, layer: displayView.sampleLayer)
        super.init()
        loop.onAutoClose = { [weak self] in
            DispatchQueue.main.async { self?.stopForAutoClose() }
        }
        displayView.sampleLayer.videoGravity = .resizeAspect
        displayView.backgroundColor = PiPPalette.background
        setupPiP()
        loop.start()
    }

    private func setupPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        // 이전 컨트롤러가 남아 있으면 정리 (중복 생성·관찰 방지)
        if pipController != nil { teardownPiP() }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayView.sampleLayer,
                                                                playbackDelegate: self)
        let pip = AVPictureInPictureController(contentSource: source)
        pip.delegate = self
        // 홈으로 나가도 자동으로 켜지지 않음 — '팝업 타이머' 버튼으로만 시작
        pip.canStartPictureInPictureAutomaticallyFromInline = false
        // 앞/뒤 버튼을 미세 조정용으로 쓰기 위해 표시
        pip.requiresLinearPlayback = false
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
            // 시작 알림을 기다리지 않고 바로 자동 닫기 시각을 건다
            arm(autoCloseProvider?())
            pip.startPictureInPicture()
        }
    }

    private func arm(_ date: Date?) {
        autoCloseAt = date
        loop.setAutoClose(date)
    }

    /// 자동 닫기.
    /// 앱이 백그라운드에 있으면 iOS 가 stopPictureInPicture() 를 무시하는 경우가 있어 단계적으로 시도:
    ///  0) 앱이 앞에 있으면 일반 종료 요청, 백그라운드면 바로 콘텐츠 소스를 떼어냄
    ///  1) 0.3초 뒤에도 떠 있으면 콘텐츠 소스를 떼어냄
    ///  2) 그래도 떠 있으면 PiP 컨트롤러 자체를 해제 (다음 사용을 위해 잠시 뒤 새로 만듦)
    private func stopForAutoClose(step: Int = 0) {
        guard let pip = pipController, pip.isPictureInPictureActive else {
            autoCloseAt = nil
            // 콘텐츠 소스를 떼어내서 닫힌 경우: 다음에 다시 켤 수 있도록 새로 구성
            if pipController?.contentSource == nil {
                teardownPiP()
                setupPiP()
            }
            return
        }
        switch step {
        case 0:
            if UIApplication.shared.applicationState == .active {
                pip.stopPictureInPicture()
            } else {
                // 백그라운드에선 종료 요청이 무시되므로 기다리지 않고 바로 콘텐츠 소스를 떼어냄
                pip.contentSource = nil
            }
        case 1:
            pip.contentSource = nil
        default:
            teardownPiP()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.setupPiP() }
            autoCloseAt = nil
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.stopForAutoClose(step: step + 1)
        }
    }

    private func teardownPiP() {
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        pipController?.delegate = nil
        pipController = nil
        isActive = false
        isPossible = false
        loop.setAutoClose(nil)
    }

    fileprivate nonisolated var playbackTime: CMTime { loop.currentTime }

    fileprivate func didStart() {
        // 버튼 외의 경로로 시작된 경우에도 적용
        if autoCloseAt == nil { arm(autoCloseProvider?()) }
    }

    fileprivate func didStop() {
        arm(nil)
        // X 로 닫으면 원래 자리에 'This video is playing in picture in picture' 안내가 남는 경우가 있어
        // 컨트롤러를 새로 만들어 걷어냄 (이전 컨트롤러가 해제되면서 안내도 사라짐)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.pipController?.isPictureInPictureActive != true else { return }
            self.teardownPiP()
            self.displayView.sampleLayer.flush()
            self.setupPiP()
        }
    }
}

/// 백그라운드(PiP 중)에도 돌아가야 하므로 CADisplayLink 대신 GCD 타이머로 프레임을 공급합니다.
/// 표시 문자열이 바뀔 때만 새 프레임을 그리고, 초가 바뀔 때 카운트다운 소리를 냅니다.
final class ClockFrameLoop: @unchecked Sendable {
    private let clock: DisplayClock
    private let layer: AVSampleBufferDisplayLayer
    private var renderer = ClockFrameRenderer(size: PiPStyle.standard.pixelSize)
    private var currentStyle: PiPStyle = .standard
    private let queue = DispatchQueue(label: "pip.clock.render", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var lastKey = ""
    private var lastSecond: Double = 0
    private let timebase: CMTimebase?
    /// 자동 닫기 시각에 도달했을 때 (렌더 큐에서 호출)
    var onAutoClose: (() -> Void)?

    func setAutoClose(_ date: Date?) {
        clock.update { $0.autoCloseAt = date }
    }

    init(clock: DisplayClock, layer: AVSampleBufferDisplayLayer) {
        self.clock = clock
        self.layer = layer
        var tb: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault,
                                        sourceClock: CMClockGetHostTimeClock(),
                                        timebaseOut: &tb)
        if let tb {
            // PiP 진행 막대 가운데쯤에서 시작하도록 12시간 지점으로
            CMTimebaseSetTime(tb, time: CMTime(seconds: 43_200, preferredTimescale: 600))
            CMTimebaseSetRate(tb, rate: 1)
            layer.controlTimebase = tb
        }
        timebase = tb
    }

    var currentTime: CMTime {
        timebase.map { CMTimebaseGetTime($0) } ?? CMClockGetTime(CMClockGetHostTimeClock())
    }

    func start() {
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        // 5ms 간격 확인 → 표시 자릿수가 바뀌는 순간과의 지연이 최대 ~5ms
        t.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func tick() {
        let cfg = clock.config
        let now = Date().addingTimeInterval(cfg.offset)
        let t = now.timeIntervalSince1970
        let second = floor(t)

        // 지정한 서버시각(보정 제외)에 도달하면 PiP 닫기 (한 번만)
        if let closeAt = cfg.autoCloseAt, Date().addingTimeInterval(cfg.serverOffset) >= closeAt {
            clock.update { $0.autoCloseAt = nil }
            onAutoClose?()
        }

        // 카운트다운 소리
        if second != lastSecond {
            if lastSecond != 0 { beepIfNeeded(second: second, cfg: cfg) }
            lastSecond = second
        }

        // 아래 줄: 사이트 이름 / 일정 카운트다운
        var parts: [String] = []
        if cfg.showLabel { parts.append(cfg.label) }
        var eventSoon = false
        if let e = cfg.nextEvent {
            let remain = e.date.timeIntervalSince(now)
            if remain > -60 && remain < 86_400 {
                parts.append("\(e.name) \(remain > 0 ? ClockFormat.countdown(remain) : "시작")")
                eventSoon = remain > 0 && remain <= DisplayClock.redWindow
            }
        }
        let subtitle = parts.isEmpty ? nil : parts.joined(separator: "  ·  ")

        // 정각 직전 빨간 표시
        let secOfMinute = t.truncatingRemainder(dividingBy: 60)
        let highlight = cfg.redBeforeMinute && (secOfMinute >= 60 - DisplayClock.redWindow || eventSoon)

        let lines = Self.layout(style: cfg.style, now: now, cfg: cfg, subtitle: subtitle, highlight: highlight)
        let key = cfg.style.rawValue + "|" + lines.map(\.text).joined(separator: "|") + (highlight ? "!" : "")
        guard key != lastKey else { return }
        lastKey = key

        // PiP 크기가 바뀌면 새 크기의 버퍼로 (PiP 창 비율이 따라 바뀜)
        if cfg.style != currentStyle {
            currentStyle = cfg.style
            renderer = ClockFrameRenderer(size: cfg.style.pixelSize)
            layer.flush()
        }

        if layer.status == .failed { layer.flush() }
        if let sb = renderer.makeSampleBuffer(lines: lines, pts: currentTime) {
            layer.enqueue(sb)
        }
    }

    /// PiP 크기별 화면 구성
    static func layout(style: PiPStyle, now: Date, cfg: DisplayConfig,
                       subtitle: String?, highlight: Bool) -> [RenderLine] {
        let main = highlight ? PiPPalette.alert : PiPPalette.text
        let dim = PiPPalette.dim
        // 소수점 아래만 민트 (자릿수 0이면 없음)
        let frac: UIColor? = cfg.digits > 0 ? (highlight ? PiPPalette.alert : PiPPalette.accent) : nil
        let time = ClockFormat.time(now, digits: cfg.digits)
        let full = ClockFormat.full(now, digits: cfg.digits, showDate: cfg.showDate)
        let info = [cfg.accuracyText, subtitle].compactMap { $0 }.joined(separator: "  ·  ")

        switch style {
        case .standard, .square:
            var lines: [RenderLine] = []
            if cfg.showDate { lines.append(RenderLine(text: ClockFormat.dateOnly(now), share: 1, color: dim, weight: .semibold)) }
            lines.append(RenderLine(text: time, share: style == .square ? 2.2 : 3.2, color: main, fractionColor: frac))
            if !info.isEmpty { lines.append(RenderLine(text: info, share: 0.9, color: dim, weight: .medium)) }
            return lines
        case .barL:
            var lines = [RenderLine(text: full, share: 3, color: main, fractionColor: frac)]
            if let subtitle { lines.append(RenderLine(text: subtitle, share: 1, color: dim, weight: .medium)) }
            return lines
        case .barM:
            return [RenderLine(text: full, share: 1, color: main, fractionColor: frac)]
        case .thin, .ultraSlim:
            return [RenderLine(text: time, share: 1, color: main, fractionColor: frac)]
        }
    }

    /// 정각 3초 전부터 짧게, 정각에 길게
    private func beepIfNeeded(second: Double, cfg: DisplayConfig) {
        var target: Double?
        if let e = cfg.nextEvent, cfg.beepMode != .off {
            let ev = floor(e.date.timeIntervalSince1970)
            if ev - second >= 0 && ev - second <= 3 { target = ev }
        }
        if target == nil, cfg.beepMode == .everyMinute {
            target = (floor(second / 60) + (second.truncatingRemainder(dividingBy: 60) == 0 ? 0 : 1)) * 60
        }
        guard let target else { return }
        let remain = target - second
        if remain == 0 {
            BeepPlayer.shared.playLong()
        } else if remain >= 1 && remain <= 3 {
            BeepPlayer.shared.playShort()
        }
    }

    deinit { timer?.cancel() }
}

extension PiPClockController: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                setPlaying playing: Bool) {}

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        // 앞/뒤 버튼이 항상 눌릴 수 있도록 현재 위치 앞뒤로 넉넉한 구간
        let now = playbackTime
        return CMTimeRange(start: CMTimeSubtract(now, CMTime(seconds: 3600, preferredTimescale: 600)),
                           duration: CMTime(seconds: 7200, preferredTimescale: 600))
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController) -> Bool { false }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    /// ◀◀ = 늦추기, ▶▶ = 앞당기기
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                skipByInterval skipInterval: CMTime,
                                                completion completionHandler: @escaping () -> Void) {
        let forward = CMTimeGetSeconds(skipInterval) > 0
        Task { @MainActor in
            self.onSkip?(forward)
            completionHandler()
        }
    }
}

extension PiPClockController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: Error) {
        print("PiP 시작 실패:", error)
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in self.didStart() }
    }

    /// PiP 창의 '앱으로 돌아가기' 버튼: 바로 복귀 처리
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in self.didStop() }
    }
}

/// AVSampleBufferDisplayLayer 를 기본 레이어로 쓰는 뷰
final class SampleBufferView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    var sampleLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
}
