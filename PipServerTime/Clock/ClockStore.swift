import Foundation

/// 서버시간을 어디서 가져올지
enum SyncSource: String, CaseIterable, Identifiable, Codable {
    /// 직접 측정 우선, 실패하면 네이비즘
    case auto
    /// 앱이 대상 사이트의 HTTP Date 헤더로 직접 측정 (ms 단위)
    case direct
    /// 네이비즘(time.navyism.com) 계산값 그대로
    case navyism

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "자동"
        case .direct: return "직접 측정"
        case .navyism: return "네이비즘"
        }
    }
}

enum SyncConfidence: String, Codable {
    case high, medium, low
    var title: String {
        switch self {
        case .high: return "높음"
        case .medium: return "보통"
        case .low: return "낮음"
        }
    }
}

struct Preset: Hashable, Codable, Identifiable {
    var name: String
    var url: String
    var isCustom = false
    var id: String { url }
}

/// 한 번의 동기화 결과
struct SyncResult: Equatable {
    /// 서버시간 - 기기시간 (초). 서버시간 = Date() + offset
    var offset: TimeInterval
    /// 추정 오차 (± 초), 모르면 nil
    var accuracy: TimeInterval?
    /// 실제 사용된 방식
    var source: SyncSource
    var host: String
    var syncedAt: Date
    var confidence: SyncConfidence?
    /// 대상 서버까지 왕복 지연 중앙값 (초)
    var rttMedian: TimeInterval?
    var samplesAgreed: Int?
    var samplesTotal: Int?

    /// 권장 선행 클릭 시간 = 편도 지연(왕복의 절반) + 측정 오차.
    /// 이만큼 일찍 누르면 요청이 서버에 '정각' 즈음 도착합니다.
    var recommendedLead: TimeInterval? {
        guard let rtt = rttMedian else { return nil }
        return rtt / 2 + (accuracy ?? 0)
    }
}

/// 앱 전체의 시계 상태. PiP 렌더러와 SwiftUI 화면이 함께 참조합니다.
@MainActor
final class ClockStore: ObservableObject {
    private static let defaults = UserDefaults.standard

    @Published var urlText: String = UserDefaults.standard.string(forKey: "lastURL") ?? "https://www.naver.com" {
        didSet { Self.defaults.set(urlText, forKey: "lastURL") }
    }
    @Published var source: SyncSource = SyncSource(rawValue: UserDefaults.standard.string(forKey: "syncSource") ?? "") ?? .auto {
        didSet { Self.defaults.set(source.rawValue, forKey: "syncSource") }
    }
    @Published var showTenths: Bool = UserDefaults.standard.object(forKey: "showTenths") as? Bool ?? true {
        didSet { Self.defaults.set(showTenths, forKey: "showTenths"); pip.showTenths = showTenths }
    }
    @Published var showHostInPiP: Bool = UserDefaults.standard.bool(forKey: "showHost") {
        didSet { Self.defaults.set(showHostInPiP, forKey: "showHost"); pip.showHost = showHostInPiP }
    }
    /// 켜면 시계에 권장 선행 시간을 더해서 표시 → 시계가 정각이 될 때 누르면 됨
    @Published var applyLead: Bool = UserDefaults.standard.bool(forKey: "applyLead") {
        didSet { Self.defaults.set(applyLead, forKey: "applyLead"); applyToClock() }
    }
    @Published private(set) var customPresets: [Preset] = {
        guard let data = UserDefaults.standard.data(forKey: "customPresets"),
              let list = try? JSONDecoder().decode([Preset].self, from: data) else { return [] }
        return list
    }() {
        didSet { Self.defaults.set(try? JSONEncoder().encode(customPresets), forKey: "customPresets") }
    }

    @Published private(set) var result: SyncResult?
    @Published private(set) var isSyncing = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastError: String?

    /// 렌더 스레드에서도 읽을 수 있도록 별도로 보관 (락으로 보호)
    let clock: OffsetClock
    /// PiP 시계
    let pip: PiPClockController

    init() {
        let c = OffsetClock()
        clock = c
        pip = PiPClockController(clock: c)
        pip.showTenths = showTenths
        pip.showHost = showHostInPiP
        applyToClock()
    }

    /// 기본 제공 사이트. 네이비즘 이용자들이 실제로 많이 찾는 티켓팅 호스트 기준.
    /// (예매창이 다른 서버로 열리는 사이트는 그 예매창 주소를 '현재 주소 저장'으로 추가하는 게 가장 정확)
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

    /// 지금 입력한 주소를 내 사이트로 저장
    func saveCurrentAsPreset(name: String) {
        guard let url = URLNormalizer.normalize(urlText) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let preset = Preset(name: trimmed.isEmpty ? (url.host ?? url.absoluteString) : trimmed,
                            url: url.absoluteString, isCustom: true)
        customPresets.removeAll { $0.url == preset.url }
        customPresets.insert(preset, at: 0)
    }

    func deletePreset(_ preset: Preset) {
        customPresets.removeAll { $0.url == preset.url }
    }

    private var syncTask: Task<Void, Never>?

    func sync() {
        syncTask?.cancel()
        let text = urlText
        let source = source
        syncTask = Task { [weak self] in
            await self?.performSync(text: text, source: source)
        }
    }

    private func performSync(text: String, source: SyncSource) async {
        guard let target = URLNormalizer.normalize(text) else {
            lastError = "올바른 주소를 입력하세요."
            return
        }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false; statusMessage = nil }

        var errors: [String] = []
        let host = target.host ?? text

        if source == .auto || source == .direct {
            statusMessage = "사이트에서 직접 서버시간 측정 중…"
            do {
                let r = try await DirectServerTimeSource.measureOffset(url: target) { [weak self] progress in
                    Task { @MainActor in self?.statusMessage = progress }
                }
                apply(SyncResult(offset: r.offset, accuracy: r.accuracy, source: .direct, host: host,
                                 syncedAt: Date(), confidence: r.confidence, rttMedian: r.rttMedian,
                                 samplesAgreed: r.samplesAgreed, samplesTotal: r.samplesTotal))
                return
            } catch is CancellationError {
                return
            } catch {
                errors.append("직접 측정: \(error.localizedDescription)")
            }
        }

        if source == .auto || source == .navyism {
            statusMessage = "네이비즘에서 서버시간 불러오는 중…"
            do {
                let r = try await NavyismTimeSource.fetchOffset(for: target)
                apply(SyncResult(offset: r.offset, accuracy: r.accuracy, source: .navyism,
                                 host: host, syncedAt: Date()))
                if !errors.isEmpty { lastError = errors.joined(separator: "\n") + "\n→ 네이비즘 값을 사용합니다." }
                return
            } catch is CancellationError {
                return
            } catch {
                errors.append("네이비즘: \(error.localizedDescription)")
            }
        }

        lastError = errors.joined(separator: "\n")
    }

    private func apply(_ r: SyncResult) {
        result = r
        applyToClock()
    }

    private func applyToClock() {
        let base = result?.offset ?? 0
        var label = result?.host ?? "기기 시간"
        var lead: TimeInterval = 0
        if applyLead, let l = result?.recommendedLead {
            lead = l
            label += String(format: " · 선행 +%.0fms", l * 1000)
        }
        clock.set(offset: base + lead, label: label)
    }
}

/// 렌더링 스레드에서 안전하게 읽는 오프셋 시계
final class OffsetClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _offset: TimeInterval = 0
    private var _label: String = "기기 시간"

    func set(offset: TimeInterval, label: String) {
        lock.lock(); _offset = offset; _label = label; lock.unlock()
    }

    var offset: TimeInterval { lock.lock(); defer { lock.unlock() }; return _offset }
    var label: String { lock.lock(); defer { lock.unlock() }; return _label }

    /// 현재 서버시간
    func now() -> Date { Date().addingTimeInterval(offset) }
}
