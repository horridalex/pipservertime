import Foundation

/// 정확도 설정 (샘플 수 / 반복 패스 수 / 경계 보정 횟수)
struct AccuracyLevel: Codable, Equatable {
    var samples: Int      // 패스마다 빠르게 보내는 샘플 수
    var passes: Int       // 독립 측정 반복 횟수 (결과는 중앙값)
    var boundary: Int     // 패스마다 '초 경계'를 겨냥해 보내는 보정 샘플 수

    var plannedTotal: Int { passes * (samples + boundary) }
}

enum AccuracyPreset: String, CaseIterable, Codable, Identifiable {
    case low, normal, high, veryHigh, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "낮음"
        case .normal: return "보통"
        case .high: return "높음"
        case .veryHigh: return "매우 높음"
        case .custom: return "커스텀"
        }
    }

    var subtitle: String {
        switch self {
        case .low: return "빠른 동기화"
        case .normal: return "균형 잡힌 동기화"
        case .high: return "높은 정확도"
        case .veryHigh: return "매우 높은 정확도 · 동기화가 오래 걸림"
        case .custom: return "샘플/반복/경계 보정 직접 설정"
        }
    }

    var level: AccuracyLevel? {
        switch self {
        case .low: return AccuracyLevel(samples: 16, passes: 3, boundary: 4)
        case .normal: return AccuracyLevel(samples: 32, passes: 3, boundary: 6)
        case .high: return AccuracyLevel(samples: 48, passes: 3, boundary: 6)
        case .veryHigh: return AccuracyLevel(samples: 64, passes: 4, boundary: 8)
        case .custom: return nil
        }
    }
}

/// 앱이 대상 사이트에 직접 요청해서 서버시간을 측정합니다.
///
/// 원리: 서버 응답의 `Date` 헤더(1초 단위)
///  - 요청 보낸 시각 t0, 받은 시각 t1, 헤더 시각 D →  D − t1 ≤ θ < D + 1 − t0   (θ = 서버시간 − 기기시간)
///  - 여러 샘플의 범위를 겹치면 θ 가 좁혀짐. 응답이 빨리 온(왕복이 짧은) 샘플일수록 범위가 좁아 정확함.
///
/// 한 패스:
///  1) 샘플 N개를 0~10ms 무작위 간격으로 빠르게 보냄 (서버의 1초 안 여러 위치에 고르게 떨어지도록)
///  2) 왕복이 느린 샘플은 제외 (최소 RTT 의 1.5배 초과)
///  3) 경계 보정: 지금까지의 합의 구간을 바탕으로 다음 '초 경계' 앞뒤에 시차를 둔 샘플을
///     한꺼번에(동시에) 보냄. 넓게 한 번, 좁혀서 한 번. (하나씩 다음 초를 기다리던 방식보다 훨씬 빠름)
/// 샘플은 패스를 거치며 계속 누적되고, 최종값 = 전체 샘플이 가장 많이 동의하는 구간의 중앙.
///
/// 참고: Cloudflare `/cdn-cgi/trace` 의 `ts=` 값은 소수점 아래가 실제와 0~1초 사이로 무작위하게
/// 어긋나 밀리초 기준으로 쓸 수 없어 사용하지 않습니다.
enum DirectServerTimeSource {

    struct Sample: Identifiable, Equatable, Sendable {
        let id: Int
        let pass: Int
        let rtt: Double
        var used: Bool
        let boundary: Bool
    }

    struct PassResult: Identifiable, Equatable, Sendable {
        var id: Int { pass }
        let pass: Int
        let rttMin: Double
        let offset: Double
        let halfWidth: Double
        let used: Int
        let total: Int
    }

    struct Progress: Sendable {
        var samples: [Sample]
        var plannedTotal: Int
        var pass: Int
        var passes: Int
    }

    struct Result: Equatable, Sendable {
        var offset: TimeInterval
        var accuracy: TimeInterval
        /// 패스마다 따로 잰 값들의 최대 차이 (초). 오차보다 크게 벌어지면 서버마다 시각이 다를 가능성
        var passSpread: TimeInterval
        var multiServerSuspected: Bool
        var confidence: SyncConfidence
        var rttMedian: TimeInterval
        var rttMin: TimeInterval
        var passes: [PassResult]
        var samples: [Sample]
        var usedCount: Int { samples.filter(\.used).count }
    }

    enum DirectError: LocalizedError {
        case noDateHeader
        case inconsistent
        var errorDescription: String? {
            switch self {
            case .noDateHeader: return "서버 응답에 Date 헤더가 없습니다"
            case .inconsistent: return "측정값이 일관되지 않습니다 (서버가 여러 대이거나 캐시된 응답)"
            }
        }
    }

    /// Date 헤더 샘플 하나가 주는 θ 범위
    struct Bound { let lower: Double; let upper: Double; let rtt: Double }

    // MARK: - 진입점

    static func measureOffset(url: URL,
                              level: AccuracyLevel = AccuracyPreset.normal.level!,
                              progress: @escaping @Sendable (Progress) -> Void = { _ in }) async throws -> Result {
        let client = HTTPClient()
        defer { client.invalidate() }

        // 연결 예열 (DNS/TLS 시간이 측정에 섞이지 않도록) - 통계에는 넣지 않음
        guard try await client.dateSample(url) != nil else { throw DirectError.noDateHeader }
        // 경계 보정 샘플을 동시에 보낼 연결들도 미리 열어 둠
        let burstSize = max(1, (level.boundary + 1) / 2)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<burstSize { group.addTask { _ = try? await client.dateSample(url) } }
            try await group.waitForAll()
        }

        var allSamples: [Sample] = []
        var bounds: [(Bound, Int)] = []      // 모든 패스의 샘플을 누적 (범위, allSamples 인덱스)
        var passResults: [PassResult] = []
        var independentMids: [Double] = []
        var nextID = 0
        let passes = max(1, level.passes)

        func report(_ pass: Int) {
            progress(Progress(samples: allSamples, plannedTotal: level.plannedTotal, pass: pass, passes: passes))
        }
        func add(_ b: Bound, pass: Int, boundary: Bool) {
            allSamples.append(Sample(id: nextID, pass: pass, rtt: b.rtt, used: true, boundary: boundary))
            bounds.append((b, allSamples.count - 1))
            nextID += 1
            markUsed(&allSamples, bounds)
        }
        func usedBounds() -> [Bound] { bounds.filter { allSamples[$0.1].used }.map { $0.0 } }

        for pass in 1...passes {
            // 1) 빠른 샘플들: 0~10ms 무작위 간격 → 서버의 1초 안 여러 위치에 고르게 떨어짐
            for _ in 0..<max(3, level.samples) {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: UInt64.random(in: 0...10_000_000))
                add(try await requireSample(client, url), pass: pass, boundary: false)
                report(pass)
            }

            // 2) 경계 보정: 다음 '초 경계' 앞뒤로 조금씩 시차를 둔 샘플을 한꺼번에 보냄 (2번: 넓게 → 좁게)
            var remaining = max(0, level.boundary)
            while remaining > 0 {
                try Task.checkCancellation()
                let n = min(burstSize, remaining)
                remaining -= n
                let used = usedBounds()
                let c = Consensus(used)
                let guess = c?.mid ?? 0
                let rtt = median(used.map(\.rtt))
                let spread = min(0.3, max(0.01, (c?.width ?? 0.3) * 0.8))
                let now = Date().timeIntervalSince1970
                // 서버 도착 예상 시각이 다음 정수 초가 되는 기기 시각
                let base = ceil(now + rtt / 2 + guess + 0.05) - guess - rtt / 2
                let fireTimes = (0..<n).map { k in
                    n > 1 ? base - spread / 2 + spread * Double(k) / Double(n - 1) : base
                }
                let results = try await withThrowingTaskGroup(of: Bound?.self) { group -> [Bound] in
                    for t in fireTimes {
                        group.addTask {
                            let wait = t - Date().timeIntervalSince1970
                            if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                            return try await client.dateSample(url)
                        }
                    }
                    var out: [Bound] = []
                    for try await b in group { if let b { out.append(b) } }
                    return out
                }
                for b in results { add(b, pass: pass, boundary: true) }
                report(pass)
            }

            // 3) 이 패스 샘플만으로 따로 낸 값 (서버 간 차이 감지용)
            let thisPass = bounds.filter { allSamples[$0.1].pass == pass && allSamples[$0.1].used }.map { $0.0 }
            if let own = Consensus(thisPass) { independentMids.append(own.mid) }

            // 4) 이 패스까지 누적된 샘플의 합의 구간
            let used = usedBounds()
            if let c = Consensus(used) {
                passResults.append(PassResult(pass: pass, rttMin: used.map(\.rtt).min() ?? 0,
                                              offset: c.mid, halfWidth: c.width / 2,
                                              used: c.agreed, total: bounds.count))
            }
            report(pass)
        }

        // 최종: 전체 샘플의 합의 구간. 합의에 들지 못한 샘플(튀는 값)은 '제외'로 표시
        guard let final = Consensus(usedBounds()) else { throw DirectError.inconsistent }
        for (b, idx) in bounds where allSamples[idx].used {
            if !(b.lower <= final.mid && final.mid < b.upper) { allSamples[idx].used = false }
        }

        let offset = final.mid
        let accuracy = final.width / 2
        let usedRTTs = allSamples.filter(\.used).map(\.rtt)
        let usedRatio = Double(usedRTTs.count) / Double(max(1, allSamples.count))

        let passSpread = (independentMids.max() ?? 0) - (independentMids.min() ?? 0)
        // 패스끼리 오차 범위(±)를 훌쩍 넘게 다르면 서버가 여러 대이거나 서버 시각이 흔들리는 것
        let multiServer = independentMids.count >= 2 && passSpread > max(0.04, accuracy * 2)

        let confidence: SyncConfidence = {
            if multiServer { return accuracy <= 0.1 ? .medium : .low }
            if accuracy <= 0.04 && usedRatio >= 0.3 { return .high }
            if accuracy <= 0.1 { return .medium }
            return .low
        }()

        return Result(offset: offset, accuracy: accuracy, passSpread: passSpread, multiServerSuspected: multiServer,
                      confidence: confidence,
                      rttMedian: median(usedRTTs.isEmpty ? allSamples.map(\.rtt) : usedRTTs),
                      rttMin: allSamples.map(\.rtt).min() ?? 0,
                      passes: passResults, samples: allSamples)
    }

    /// 왕복이 느린 샘플 제외: 최소 RTT 의 1.5배(최소 +15ms) 초과
    private static func markUsed(_ samples: inout [Sample], _ bounds: [(Bound, Int)]) {
        guard let minRTT = bounds.map({ $0.0.rtt }).min() else { return }
        let limit = max(minRTT * 1.5, minRTT + 0.015)
        for (b, idx) in bounds { samples[idx].used = b.rtt <= limit }
    }

    // MARK: - 합의 구간

    /// 가장 많은 샘플이 동시에 만족하는 θ 구간 (동률이면 평균 RTT 가 작은 쪽)
    struct Consensus {
        let lower: Double
        let upper: Double
        let agreed: Int
        var mid: Double { (lower + upper) / 2 }
        var width: Double { upper - lower }

        init?(_ bounds: [Bound]) {
            guard !bounds.isEmpty else { return nil }
            let eps = 1e-6
            let candidates = bounds.flatMap { [$0.lower, $0.upper - eps] }
            var best: (point: Double, count: Int, rtt: Double)?
            for p in candidates {
                let inside = bounds.filter { $0.lower <= p && p < $0.upper }
                guard !inside.isEmpty else { continue }
                let avgRTT = inside.map(\.rtt).reduce(0, +) / Double(inside.count)
                if best == nil || inside.count > best!.count || (inside.count == best!.count && avgRTT < best!.rtt) {
                    best = (p, inside.count, avgRTT)
                }
            }
            guard let best else { return nil }
            let inside = bounds.filter { $0.lower <= best.point && best.point < $0.upper }
            lower = inside.map(\.lower).max()!
            upper = inside.map(\.upper).min()!
            agreed = inside.count
        }
    }

    // MARK: - helpers

    private static func requireSample(_ client: HTTPClient, _ url: URL) async throws -> Bound {
        guard let s = try await client.dateSample(url) else { throw DirectError.noDateHeader }
        return s
    }

    static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}

/// 요청 하나의 iOS 측 타이밍 기록을 받아 둠
private final class MetricsBox: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _metrics: URLSessionTaskMetrics?
    var metrics: URLSessionTaskMetrics? { lock.lock(); defer { lock.unlock() }; return _metrics }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.lock(); _metrics = metrics; lock.unlock()
    }

    /// 리다이렉트는 따라가지 않음 (3xx 응답에도 Date 가 있고, 왕복 1회만 재기 위해)
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}

/// 측정용 HTTP 클라이언트. 리다이렉트를 따라가지 않아(3xx 응답에도 Date 가 있음) 왕복 1회만 잰다.
final class HTTPClient: @unchecked Sendable {
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.httpMaximumConnectionsPerHost = 4   // 경계 보정 샘플 동시 전송
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()
    private let lock = NSLock()
    private var _useHead = true
    private var useHead: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _useHead }
        set { lock.lock(); _useHead = newValue; lock.unlock() }
    }

    func invalidate() { session.finishTasksAndInvalidate() }

    private func request(_ url: URL, method: String) -> URLRequest {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        // 캐시/CDN 이 오래된 응답을 주지 않도록 쿼리 추가
        var items = comps.queryItems ?? []
        items.append(URLQueryItem(name: "_pst", value: String(Int(Date().timeIntervalSince1970 * 1000))))
        comps.queryItems = items
        var req = URLRequest(url: comps.url ?? url)
        req.httpMethod = method
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.setValue("no-cache", forHTTPHeaderField: "Pragma")
        if method == "GET" { req.setValue("bytes=0-0", forHTTPHeaderField: "Range") }
        return req
    }

    /// Date 헤더 샘플 1개
    ///
    /// 시각은 iOS 가 기록하는 '요청이 실제로 나간 순간(requestStart)'과 '응답 첫 바이트가 온 순간(responseStart)'을
    /// 씁니다. 앱이 요청을 지시한 시각/응답을 다 받은 시각을 쓰면 연결 대기·응답 처리 시간까지 섞여 범위가 넓어집니다.
    func dateSample(_ url: URL) async throws -> DirectServerTimeSource.Bound? {
        let req = request(url, method: useHead ? "HEAD" : "GET")
        let box = MetricsBox()
        let wall0 = Date().timeIntervalSince1970
        let (_, response) = try await session.data(for: req, delegate: box)
        let wall1 = Date().timeIntervalSince1970
        var t0 = wall0, t1 = wall1
        if let tx = box.metrics?.transactionMetrics.last,
           let start = tx.requestStartDate?.timeIntervalSince1970,
           let first = tx.responseStartDate?.timeIntervalSince1970,
           start >= wall0 - 0.05, first <= wall1 + 0.05, first >= start {
            t0 = start
            t1 = first
        }
        let http = response as? HTTPURLResponse
        let date = http?.value(forHTTPHeaderField: "Date").flatMap { Self.httpDate.date(from: $0) }
        if useHead, date == nil || http?.statusCode == 405 || http?.statusCode == 501 {
            useHead = false        // HEAD 를 막은 서버 → GET 으로 재시도
            return try await dateSample(url)
        }
        guard let d = date?.timeIntervalSince1970 else { return nil }
        return .init(lower: d - t1, upper: d + 1 - t0, rtt: t1 - t0)
    }

    static let httpDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()
}
