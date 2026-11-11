import Foundation
import CoreGraphics

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
    /// 추정 오차 (± 초)
    var accuracy: TimeInterval?
    var siteName: String
    var syncedAt: Date
    var confidence: SyncConfidence?
    /// 대상 서버까지 왕복 지연 중앙값 (초)
    var rttMedian: TimeInterval?
    var rttMin: TimeInterval?
    var passes: [DirectServerTimeSource.PassResult] = []
    var samples: [DirectServerTimeSource.Sample] = []
    /// 패스별로 따로 잰 값의 최대 차이 (초)
    var passSpread: TimeInterval?
    /// 서버마다 시각이 다른 것으로 보임
    var multiServerSuspected = false

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

/// PiP 창 모양. PiP 창 비율은 그리는 버퍼 비율을 따라갑니다.
enum PiPStyle: String, CaseIterable, Identifiable, Codable {
    case standard, barL, barM, thin, ultraSlim, square
    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "기본 16:9"
        case .barL: return "긴 막대 L"
        case .barM: return "긴 막대 M"
        case .thin: return "얇은 막대"
        case .ultraSlim: return "초슬림 선형"
        case .square: return "정사각형"
        }
    }

    var subtitle: String {
        switch self {
        case .standard: return "큰 숫자와 오차 표시를 함께 보여주는 기본 팝업"
        case .barL: return "가로로 긴 창에 숫자를 크게 배치"
        case .barM: return "다른 앱 위에 올려두기 쉬운 낮은 막대"
        case .thin: return "시야를 덜 가리는 초경량 가로형"
        case .ultraSlim: return "화면 위·아래에 붙여두기 좋은 가장 얇은 형태"
        case .square: return "짧은 가로폭이 필요할 때 쓰는 컴팩트 정사각형"
        }
    }

    /// 렌더 버퍼 크기 (픽셀)
    var pixelSize: CGSize {
        switch self {
        case .standard: return CGSize(width: 1280, height: 720)
        case .barL: return CGSize(width: 1200, height: 200)
        case .barM: return CGSize(width: 1200, height: 150)
        case .thin: return CGSize(width: 1440, height: 120)
        case .ultraSlim: return CGSize(width: 1600, height: 80)
        case .square: return CGSize(width: 720, height: 720)
        }
    }

    var aspect: CGFloat { pixelSize.width / pixelSize.height }
}
