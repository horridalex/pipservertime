import Foundation
import UserNotifications

/// 앱 전체 상태. PiP 렌더러와 SwiftUI 화면이 함께 참조합니다.
@MainActor
final class ClockStore: ObservableObject {
    private static let defaults = UserDefaults.standard

    // MARK: - 사이트 / 측정 설정

    @Published var urlText: String = UserDefaults.standard.string(forKey: "lastURL") ?? "https://tickets.interpark.com" {
        didSet { Self.defaults.set(urlText, forKey: "lastURL") }
    }
    @Published var siteName: String = UserDefaults.standard.string(forKey: "siteName") ?? "NOL 티켓(인터파크)" {
        didSet { Self.defaults.set(siteName, forKey: "siteName") }
    }
    @Published var source: SyncSource =
        SyncSource(rawValue: UserDefaults.standard.string(forKey: "syncSource") ?? "") ?? .auto {
        didSet { Self.defaults.set(source.rawValue, forKey: "syncSource") }
    }
    @Published var accuracyPreset: AccuracyPreset =
        AccuracyPreset(rawValue: UserDefaults.standard.string(forKey: "accuracyPreset") ?? "") ?? .normal {
        didSet { Self.defaults.set(accuracyPreset.rawValue, forKey: "accuracyPreset") }
    }
    @Published var customLevel: AccuracyLevel = {
        if let d = UserDefaults.standard.data(forKey: "customLevel"),
           let l = try? JSONDecoder().decode(AccuracyLevel.self, from: d) { return l }
        return AccuracyPreset.normal.level!
    }() {
        didSet { Self.defaults.set(try? JSONEncoder().encode(customLevel), forKey: "customLevel") }
    }
    var accuracyLevel: AccuracyLevel { accuracyPreset.level ?? customLevel }

    // MARK: - 보정 설정

    /// 네트워크 지연(편도)만큼 시계를 앞당김
    @Published var applyLead: Bool = UserDefaults.standard.object(forKey: "applyLead") as? Bool ?? false {
        didSet { Self.defaults.set(applyLead, forKey: "applyLead"); pushConfig() }
    }
    /// 내 반응속도만큼 시계를 앞당김 (ms, 음수면 늦춤)
    @Published var reactionAdjustMs: Int = UserDefaults.standard.integer(forKey: "reactionAdjustMs") {
        didSet { Self.defaults.set(reactionAdjustMs, forKey: "reactionAdjustMs"); pushConfig() }
    }
    /// PiP 의 앞/뒤 버튼으로 조절하는 단위 (ms)
    @Published var pipStepMs: Int = UserDefaults.standard.object(forKey: "pipStepMs") as? Int ?? 50 {
        didSet { Self.defaults.set(pipStepMs, forKey: "pipStepMs") }
    }
    /// PiP 버튼으로 조절한 누적값 (ms). 재측정해도 유지
    @Published var pipAdjustMs: Int = UserDefaults.standard.integer(forKey: "pipAdjustMs") {
        didSet { Self.defaults.set(pipAdjustMs, forKey: "pipAdjustMs"); pushConfig() }
    }

    // MARK: - 표시 설정

    @Published var appDigits: Int = UserDefaults.standard.object(forKey: "appDigits") as? Int ?? 3 {
        didSet { Self.defaults.set(appDigits, forKey: "appDigits") }
    }
    @Published var pipDigits: Int = UserDefaults.standard.object(forKey: "pipDigits") as? Int ?? 1 {
        didSet { Self.defaults.set(pipDigits, forKey: "pipDigits"); pushConfig() }
    }
    @Published var showDateInPiP: Bool = UserDefaults.standard.object(forKey: "showDateInPiP") as? Bool ?? true {
        didSet { Self.defaults.set(showDateInPiP, forKey: "showDateInPiP"); pushConfig() }
    }
    @Published var showHostInPiP: Bool = UserDefaults.standard.bool(forKey: "showHost") {
        didSet { Self.defaults.set(showHostInPiP, forKey: "showHost"); pushConfig() }
    }
    @Published var redBeforeMinute: Bool = UserDefaults.standard.object(forKey: "redBeforeMinute") as? Bool ?? true {
        didSet { Self.defaults.set(redBeforeMinute, forKey: "redBeforeMinute"); pushConfig() }
    }
    @Published var beepMode: BeepMode = BeepMode(rawValue: UserDefaults.standard.string(forKey: "beepMode") ?? "") ?? .off {
        didSet { Self.defaults.set(beepMode.rawValue, forKey: "beepMode"); pushConfig() }
    }
    @Published var colorMode: ColorMode = ColorMode(rawValue: UserDefaults.standard.string(forKey: "colorMode") ?? "") ?? .system {
        didSet { Self.defaults.set(colorMode.rawValue, forKey: "colorMode") }
    }

    @Published var pipStyle: PiPStyle = PiPStyle(rawValue: UserDefaults.standard.string(forKey: "pipStyle") ?? "") ?? .standard {
        didSet { Self.defaults.set(pipStyle.rawValue, forKey: "pipStyle"); pushConfig() }
    }

    // MARK: - PiP 자동 닫기

    /// 지정한 서버시각에 PiP 자동으로 닫기 (좌석 선택·결제 화면을 가리지 않도록)
    @Published var autoClosePiP: Bool = UserDefaults.standard.bool(forKey: "autoClosePiP") {
        didSet { Self.defaults.set(autoClosePiP, forKey: "autoClosePiP") }
    }
    /// 닫는 시각 (하루 중 초, 서버시간 기준)
    @Published var autoCloseSecondOfDay: Int = UserDefaults.standard.object(forKey: "autoCloseSecondOfDay") as? Int ?? 0 {
        didSet { Self.defaults.set(autoCloseSecondOfDay, forKey: "autoCloseSecondOfDay") }
    }

    /// 지금 서버시각 이후 처음 오는 '닫는 시각'
    func nextAutoCloseDate() -> Date? {
        guard autoClosePiP else { return nil }
        let serverNow = Date().addingTimeInterval(result?.offset ?? 0)
        let cal = Calendar.current
        let start = cal.startOfDay(for: serverNow)
        var target = start.addingTimeInterval(TimeInterval(autoCloseSecondOfDay))
        if target <= serverNow { target = cal.date(byAdding: .day, value: 1, to: target) ?? target.addingTimeInterval(86_400) }
        return target
    }

    /// 시트 기본값: 다음 일정 시각 + 5초, 없으면 지금부터 5분 뒤
    func suggestedAutoCloseSecondOfDay() -> Int {
        let serverNow = Date().addingTimeInterval(result?.offset ?? 0)
        let base = nextEvent.map { $0.date.addingTimeInterval(5) } ?? serverNow.addingTimeInterval(300)
        let start = Calendar.current.startOfDay(for: base)
        return Int(base.timeIntervalSince(start)) % 86_400
    }

    // MARK: - 일정

    @Published private(set) var events: [ScheduledEvent] = {
        guard let d = UserDefaults.standard.data(forKey: "events"),
              let list = try? JSONDecoder().decode([ScheduledEvent].self, from: d) else { return [] }
        return list
    }() {
        didSet {
            Self.defaults.set(try? JSONEncoder().encode(events), forKey: "events")
            pushConfig()
            scheduleNotifications()
        }
    }
    /// 일정 N분 전에 자동 재측정 (0 = 끔)
    @Published var autoResyncMinutes: Int = UserDefaults.standard.object(forKey: "autoResyncMinutes") as? Int ?? 4 {
        didSet { Self.defaults.set(autoResyncMinutes, forKey: "autoResyncMinutes") }
    }

    // MARK: - 저장한 사이트

    @Published private(set) var customPresets: [Preset] = {
        guard let data = UserDefaults.standard.data(forKey: "customPresets"),
              let list = try? JSONDecoder().decode([Preset].self, from: data) else { return [] }
        return list
    }() {
        didSet { Self.defaults.set(try? JSONEncoder().encode(customPresets), forKey: "customPresets") }
    }

    /// 기본 제공 사이트. 네이비즘 이용자들이 실제로 많이 찾는 티켓팅 호스트 기준.
    /// (예매창이 다른 서버로 열리는 사이트는 그 예매창 주소를 저장하는 게 가장 정확)
    static let builtInPresets: [Preset] = [
        Preset(name: "NOL 티켓(인터파크)", url: "https://tickets.interpark.com"),
        Preset(name: "멜론티켓", url: "https://ticket.melon.com"),
        Preset(name: "YES24 티켓", url: "https://ticket.yes24.com"),
        Preset(name: "티켓링크", url: "https://www.ticketlink.co.kr"),
        Preset(name: "위버스", url: "https://weverse.io"),
        Preset(name: "캐치테이블", url: "https://app.catchtable.co.kr"),
        Preset(name: "네이버", url: "https://www.naver.com"),
    ]

    var presets: [Preset] { customPresets + Self.builtInPresets }

    // MARK: - 실행 상태

    @Published private(set) var result: SyncResult?
    @Published private(set) var isSyncing = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastError: String?
    @Published private(set) var liveSamples: [DirectServerTimeSource.Sample] = []
    @Published private(set) var plannedSamples = 0

    let clock: DisplayClock
    let pip: PiPClockController

    private var syncTask: Task<Void, Never>?
    private var eventTimer: Timer?
    private var resyncedEventIDs: Set<UUID> = []

    init() {
        let c = DisplayClock()
        clock = c
        pip = PiPClockController(clock: c)
        pip.onSkip = { [weak self] forward in
            guard let self else { return }
            self.pipAdjustMs += forward ? self.pipStepMs : -self.pipStepMs
        }
        // PiP 가 (버튼이든 홈으로 나가서든) 시작될 때마다 자동 닫기 시각 적용
        pip.autoCloseProvider = { [weak self] in self?.nextAutoCloseDate() }
        pushConfig()
        startEventTimer()
    }

    // MARK: - 사이트 선택

    func select(_ preset: Preset) {
        urlText = preset.url
        siteName = preset.name
        sync()
    }

    /// 직접 입력한 주소 사용
    func useTypedURL(_ text: String) {
        urlText = text
        siteName = URLNormalizer.normalize(text)?.host ?? text
        sync()
    }

    func saveCurrentAsPreset(name: String) {
        guard let url = URLNormalizer.normalize(urlText) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let preset = Preset(name: trimmed.isEmpty ? (url.host ?? url.absoluteString) : trimmed,
                            url: url.absoluteString, isCustom: true)
        customPresets.removeAll { $0.url == preset.url }
        customPresets.insert(preset, at: 0)
        siteName = preset.name
    }

    func deletePreset(_ preset: Preset) {
        customPresets.removeAll { $0.url == preset.url }
    }

    // MARK: - 측정

    func sync() {
        syncTask?.cancel()
        let text = urlText
        let name = siteName
        let source = source
        let level = accuracyLevel
        syncTask = Task { [weak self] in
            await self?.performSync(text: text, name: name, source: source, level: level)
        }
    }

    func cancelSync() {
        syncTask?.cancel()
        syncTask = nil
        isSyncing = false
        statusMessage = nil
    }

    private func performSync(text: String, name: String, source: SyncSource, level: AccuracyLevel) async {
        guard let target = URLNormalizer.normalize(text) else {
            lastError = "올바른 주소를 입력하세요."
            return
        }
        isSyncing = true
        lastError = nil
        liveSamples = []
        plannedSamples = level.plannedTotal
        defer {
            if !Task.isCancelled { isSyncing = false; statusMessage = nil }
        }

        var errors: [String] = []
        let host = target.host ?? text

        if source == .auto || source == .direct {
            statusMessage = "서버에 시간 요청 중"
            do {
                let r = try await DirectServerTimeSource.measureOffset(url: target, level: level) { [weak self] p in
                    Task { @MainActor in
                        guard let self, self.isSyncing else { return }
                        self.liveSamples = p.samples
                        self.statusMessage = p.passes > 1 ? "서버에 시간 요청 중 · \(p.pass)/\(p.passes)차" : "서버에 시간 요청 중"
                    }
                }
                guard !Task.isCancelled else { return }
                apply(SyncResult(offset: r.offset, accuracy: r.accuracy, source: .direct, host: host,
                                 siteName: name, syncedAt: Date(), confidence: r.confidence,
                                 rttMedian: r.rttMedian, rttMin: r.rttMin,
                                 passes: r.passes, samples: r.samples))
                return
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                errors.append("직접 측정: \(error.localizedDescription)")
            }
        }

        if source == .auto || source == .navyism {
            statusMessage = "네이비즘에서 불러오는 중"
            do {
                let r = try await NavyismTimeSource.fetchOffset(for: target)
                guard !Task.isCancelled else { return }
                apply(SyncResult(offset: r.offset, accuracy: r.accuracy, source: .navyism,
                                 host: host, siteName: name, syncedAt: Date()))
                if !errors.isEmpty { lastError = errors.joined(separator: "\n") + "\n→ 네이비즘 값을 사용합니다." }
                return
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                errors.append("네이비즘: \(error.localizedDescription)")
            }
        }

        lastError = errors.joined(separator: "\n")
    }

    private func apply(_ r: SyncResult) {
        result = r
        pushConfig()
        scheduleNotifications()
    }

    // MARK: - 보정 합계

    /// 서버 오프셋 외에 시계에 더해지는 보정 (초). +면 시계가 앞당겨짐
    var totalCorrection: TimeInterval {
        var c = Double(reactionAdjustMs + pipAdjustMs) / 1000
        if applyLead, let lead = result?.recommendedLead { c += lead }
        return c
    }

    var nextEvent: ScheduledEvent? {
        let now = Date().addingTimeInterval(result?.offset ?? 0)
        return events.filter { $0.date > now.addingTimeInterval(-60) }.min { $0.date < $1.date }
    }

    /// 화면/PiP 렌더러가 읽는 설정 갱신
    func pushConfig() {
        let base = result?.offset ?? 0
        let corr = totalCorrection
        var label = result?.siteName ?? "기기 시간"
        if abs(corr) >= 0.0005 { label += String(format: " · 보정 %+.3f초", corr) }
        let digits = pipDigits, showDate = showDateInPiP, showLabel = showHostInPiP
        let red = redBeforeMinute, beep = beepMode
        let next = nextEvent
        let style = pipStyle
        let accText: String? = result.map { r in
            r.accuracy.map { String(format: "오차 ±%.0fms", $0 * 1000) } ?? "네이비즘 계산값"
        }
        clock.update {
            $0.style = style
            $0.accuracyText = accText
            $0.offset = base + corr
            $0.serverOffset = base
            $0.label = label
            $0.digits = digits
            $0.showDate = showDate
            $0.showLabel = showLabel
            $0.redBeforeMinute = red
            $0.beepMode = beep
            $0.nextEvent = next
        }
    }

    // MARK: - 일정

    func addEvent(_ e: ScheduledEvent) {
        events.append(e)
        events.sort { $0.date < $1.date }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func updateEvent(_ e: ScheduledEvent) {
        guard let i = events.firstIndex(where: { $0.id == e.id }) else { return }
        events[i] = e
        events.sort { $0.date < $1.date }
        resyncedEventIDs.remove(e.id)
    }

    func deleteEvent(_ e: ScheduledEvent) {
        events.removeAll { $0.id == e.id }
    }

    /// 일정 5분 전 / 1분 전 알림
    private func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let now = Date()
        let offset = result?.offset ?? 0
        for e in events {
            for minutes in [5, 1] {
                // 일정 시각은 '서버시간' 기준이므로 기기 시각으로 환산
                let fire = e.date.addingTimeInterval(-Double(minutes) * 60 - offset)
                guard fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "\(e.name) \(minutes)분 전"
                content.body = "앱을 열어 재측정하고 PiP 시계를 띄워두세요."
                content.sound = .default
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                center.add(UNNotificationRequest(identifier: "\(e.id)-\(minutes)", content: content, trigger: trigger))
            }
        }
    }

    /// 일정 직전 자동 재측정
    private func startEventTimer() {
        eventTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkEvents() }
        }
    }

    private func checkEvents() {
        pushConfig()
        guard autoResyncMinutes > 0, !isSyncing, let e = nextEvent else { return }
        let remain = e.date.timeIntervalSince(clock.now())
        let window = Double(autoResyncMinutes) * 60
        // 정각 30초 전부터는 측정하지 않음 (측정 중 결과가 바뀌면 혼란)
        guard remain <= window, remain > 30, !resyncedEventIDs.contains(e.id) else { return }
        resyncedEventIDs.insert(e.id)
        if let u = e.url, !u.isEmpty, u != urlText {
            urlText = u
            siteName = URLNormalizer.normalize(u)?.host ?? u
        }
        sync()
    }
}
