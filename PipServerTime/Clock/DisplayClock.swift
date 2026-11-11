import Foundation

/// PiP 렌더 스레드와 화면이 함께 읽는 시계 상태 (락으로 보호)
struct DisplayConfig: Equatable {
    /// 표시 시각 = 기기시각 + offset  (서버 오프셋 + 각종 보정 합)
    var offset: TimeInterval = 0
    /// 서버 오프셋만 (보정 제외)
    var serverOffset: TimeInterval = 0
    var label: String = "기기 시간"
    /// 소수점 자릿수 (0~3)
    var digits: Int = 1
    var showDate: Bool = true
    var showLabel: Bool = false
    /// 매 분 정각 직전 N초 동안 빨간색
    var redBeforeMinute: Bool = false
    var beepMode: BeepMode = .off
    var nextEvent: ScheduledEvent?
    /// 이 서버시각(보정 제외)이 되면 PiP 자동으로 닫기
    var autoCloseAt: Date?
    var style: PiPStyle = .standard
    /// "오차 ±57ms" (기본 16:9 / 정사각형에 표시)
    var accuracyText: String?
}

final class DisplayClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _config = DisplayConfig()

    var config: DisplayConfig {
        get { lock.lock(); defer { lock.unlock() }; return _config }
        set { lock.lock(); _config = newValue; lock.unlock() }
    }

    func update(_ body: (inout DisplayConfig) -> Void) {
        lock.lock(); body(&_config); lock.unlock()
    }

    /// 현재 표시 시각
    func now() -> Date { Date().addingTimeInterval(config.offset) }

    static let redWindow: TimeInterval = 10
}

enum ClockFormat {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "E  yyyy. M. d.,"
        return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// "20:49:39.819" (digits 자리까지, 반올림 없이 버림)
    static func time(_ date: Date, digits: Int) -> String {
        let base = timeFormatter.string(from: date)
        guard digits > 0 else { return base }
        let t = date.timeIntervalSince1970
        let frac = t - floor(t)
        let scale = pow(10, Double(digits))
        let v = min(Int(scale) - 1, Int(frac * scale))
        return base + "." + String(format: "%0\(digits)d", v)
    }

    /// "수  2026. 11. 11."
    static func dateOnly(_ date: Date) -> String {
        dateFormatter.string(from: date).trimmingCharacters(in: CharacterSet(charactersIn: ", "))
    }

    /// "수  2026. 11. 11., 20:49:39.8"
    static func full(_ date: Date, digits: Int, showDate: Bool) -> String {
        showDate ? dateFormatter.string(from: date) + " " + time(date, digits: digits) : time(date, digits: digits)
    }

    /// 남은 시간 "D-1 02:03:04" / "02:03" / "5.2초"
    static func countdown(_ interval: TimeInterval) -> String {
        if interval <= 0 { return "지금" }
        let total = Int(interval)
        let days = total / 86400
        let h = (total % 86400) / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if days > 0 { return String(format: "D-%d %02d:%02d:%02d", days, h, m, s) }
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        if total >= 60 { return String(format: "%d:%02d", m, s) }
        return String(format: "%.1f초", interval)
    }
}
