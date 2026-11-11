import Foundation

/// 서버시간을 어디서 가져올지
enum SyncSource: String, CaseIterable, Identifiable, Codable {
    /// 네이비즘 우선, 실패하면 앱이 직접 측정
    case auto
    /// 네이비즘(time.navyism.com)만 사용
    case navyism
    /// 앱이 대상 사이트의 HTTP Date 헤더로 직접 측정
    case direct

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "자동"
        case .navyism: return "네이비즘"
        case .direct: return "직접 측정"
        }
    }
}

struct Preset: Hashable {
    let name: String
    let url: String
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

    static let presets: [Preset] = [
        Preset(name: "네이버", url: "https://www.naver.com"),
        Preset(name: "캐치테이블", url: "https://app.catchtable.co.kr"),
        Preset(name: "인터파크 티켓", url: "https://tickets.interpark.com"),
        Preset(name: "멜론티켓", url: "https://ticket.melon.com"),
        Preset(name: "YES24 티켓", url: "https://ticket.yes24.com"),
        Preset(name: "쿠팡", url: "https://www.coupang.com"),
    ]

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

        if source == .auto || source == .navyism {
            statusMessage = "네이비즘에서 서버시간 불러오는 중…"
            do {
                let r = try await NavyismTimeSource.fetchOffset(for: target)
                apply(SyncResult(offset: r.offset, accuracy: r.accuracy, source: .navyism,
                                 host: target.host ?? text, syncedAt: Date()))
                return
            } catch is CancellationError {
                return
            } catch {
                errors.append("네이비즘: \(error.localizedDescription)")
            }
        }

        if source == .auto || source == .direct {
            statusMessage = "사이트에서 직접 서버시간 측정 중…"
            do {
                let r = try await DirectServerTimeSource.measureOffset(url: target) { [weak self] progress in
                    Task { @MainActor in self?.statusMessage = progress }
                }
                apply(SyncResult(offset: r.offset, accuracy: r.accuracy, source: .direct,
                                 host: target.host ?? text, syncedAt: Date()))
                if !errors.isEmpty { lastError = errors.joined(separator: "\n") + "\n→ 직접 측정값을 사용합니다." }
                return
            } catch is CancellationError {
                return
            } catch {
                errors.append("직접 측정: \(error.localizedDescription)")
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
        clock.set(offset: base, label: result?.host ?? "기기 시간")
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
