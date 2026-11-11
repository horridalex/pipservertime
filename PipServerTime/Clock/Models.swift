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

enum ColorMode: String, CaseIterable, Identifiable, Codable {
    case system, dark, light
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "시스템 설정"
        case .dark: return "다크"
        case .light: return "라이트"
        }
    }
}

/// 카운트다운 소리
enum BeepMode: String, CaseIterable, Identifiable, Codable {
    case off, eventsOnly, everyMinute
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "끄기"
        case .eventsOnly: return "일정 직전만"
        case .everyMinute: return "매 분 정각"
        }
    }
}

struct Preset: Hashable, Codable, Identifiable {
    var name: String
    var url: String
    var isCustom = false
    var id: String { url }
}

/// 오픈 일정 (티켓팅·수강신청 등)
struct ScheduledEvent: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var date: Date
    /// 이 일정에 쓸 사이트 (선택). 자동 재측정 때 이 주소로 측정
    var url: String?
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
    var siteName: String
    var syncedAt: Date
    var confidence: SyncConfidence?
    /// 대상 서버까지 왕복 지연 중앙값 (초)
    var rttMedian: TimeInterval?
    var rttMin: TimeInterval?
    var passes: [DirectServerTimeSource.PassResult] = []
    var samples: [DirectServerTimeSource.Sample] = []

    var usedCount: Int { samples.filter(\.used).count }

    /// 권장 선행 클릭 시간 = 편도 지연(왕복의 절반).
    /// 이만큼 일찍 누르면 요청이 서버에 '정각' 즈음 도착합니다.
    var recommendedLead: TimeInterval? {
        guard let rtt = rttMedian else { return nil }
        return rtt / 2
    }

    /// 기기 시계는 시간이 지나며 조금씩 어긋남(드리프트). 보수적으로 분당 0.6ms 가정.
    static let driftPerMinute: TimeInterval = 0.0006

    /// t 시점의 예상 오차
    func projectedAccuracy(at t: Date) -> TimeInterval? {
        guard let a = accuracy else { return nil }
        let minutes = max(0, t.timeIntervalSince(syncedAt) / 60)
        return a + minutes * Self.driftPerMinute
    }
}
