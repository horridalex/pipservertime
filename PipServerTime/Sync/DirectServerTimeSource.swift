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
///  1) 샘플 N개를 무작위 간격으로 빠르게 보냄 (서버의 1초 안 여러 위치에 고르게 떨어지도록)
///  2) 왕복이 느린 샘플은 제외 (최소 RTT 의 1.5배 초과)
///  3) 남은 샘플이 가장 많이 동의하는 구간 → 그 가운데를 '초 경계'로 겨냥한 보정 샘플 B개 추가
///  4) 패스 결과 = 최종 합의 구간의 중앙
/// 패스를 여러 번 반복해 중앙값을 최종값으로 쓰고, 패스 간 흔들림을 오차에 더합니다.
///
/// 참고: Cloudflare `/cdn-cgi/trace` 의 `ts=` 값도 검토했지만 소수점 아래가 실제와 0~1초 사이로
/// 무작위하게 어긋나 밀리초 기준으로 쓸 수 없어 사용하지 않습니다.
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
        var confidence: SyncConfidence
        var rttMedian: TimeInterval
        var rttMin: TimeInterval
        var passes: [PassResult]
        var samples: [Sample]
        var usedCount: Int { samples.filter(\.used).count }
        var totalCount: Int { samples.count }
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

        var allSamples: [Sample] = []
        var passResults: [PassResult] = []
        var nextID = 0
        let passes = max(1, level.passes)

        func report(_ pass: Int) {
            progress(Progress(samples: allSamples, plannedTotal: level.plannedTotal, pass: pass, passes: passes))
        }

        for pass in 1...passes {
            var bounds: [(Bound, Int)] = []   // (범위, allSamples 인덱스)

            // 1) 빠른 샘플들
            for _ in 0..<max(3, level.samples) {
                try Task.checkCancellation()
                // 0~30ms 무작위 간격 → 샘플이 서버의 1초 안 여러 위치에 고르게 떨어짐
                try await Task.sleep(nanoseconds: UInt64.random(in: 0...30_000_000))
                let b = try await requireSample(client, url)
                allSamples.append(Sample(id: nextID, pass: pass, rtt: b.rtt, used: true, boundary: false))
                bounds.append((b, allSamples.count - 1))
                nextID += 1
                markUsed(&allSamples, bounds)
                report(pass)
            }

            // 2) 경계 보정 샘플들
            for i in 0..<max(0, level.boundary) {
                try Task.checkCancellation()
                let used = bounds.filter { allSamples[$0.1].used }.map { $0.0 }
                let c = Consensus(used)
                let guess = c?.mid ?? 0
                let rtt = median(used.map(\.rtt))
                // 서버 도착 예상 시각이 다음 정수 초가 되도록 발사. 경계 앞/뒤를 번갈아 살짝 비켜 겨냥.
                let nudge = (i % 2 == 0 ? 1.0 : -1.0) * min(0.01, (c?.width ?? 1) / 4)
                let now = Date().timeIntervalSince1970
                let boundary = ceil(now + rtt / 2 + guess + 0.1)
                let wait = boundary - guess - rtt / 2 + nudge - now
                if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }

                let b = try await requireSample(client, url)
                allSamples.append(Sample(id: nextID, pass: pass, rtt: b.rtt, used: true, boundary: true))
                bounds.append((b, allSamples.count - 1))
                nextID += 1
                markUsed(&allSamples, bounds)
                report(pass)
            }

            // 3) 패스 결과
            let used = bounds.filter { allSamples[$0.1].used }.map { $0.0 }
            if let c = Consensus(used) {
                // 합의에 들지 못한 샘플(튀는 값)도 '제외'로 표시
                for (b, idx) in bounds where allSamples[idx].used {
                    if !(b.lower <= c.mid && c.mid < b.upper) { allSamples[idx].used = false }
                }
                passResults.append(PassResult(pass: pass, rttMin: used.map(\.rtt).min() ?? 0,
                                              offset: c.mid, halfWidth: c.width / 2,
                                              used: c.agreed, total: bounds.count))
            }
            report(pass)
        }

        guard !passResults.isEmpty else { throw DirectError.inconsistent }

        let offset = median(passResults.map(\.offset))
        let spread = passResults.map { abs($0.offset - offset) }.max() ?? 0
        let accuracy = median(passResults.map(\.halfWidth)) + spread
        let usedRTTs = allSamples.filter(\.used).map(\.rtt)
        let usedRatio = Double(usedRTTs.count) / Double(max(1, allSamples.count))

        let confidence: SyncConfidence = {
            if accuracy <= 0.04 && usedRatio >= 0.4 { return .high }
            if accuracy <= 0.1 { return .medium }
            return .low
        }()

        return Result(offset: offset, accuracy: accuracy, confidence: confidence,
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

/// 측정용 HTTP 클라이언트. 리다이렉트를 따라가지 않아(3xx 응답에도 Date 가 있음) 왕복 1회만 잰다.
final class HTTPClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.httpMaximumConnectionsPerHost = 1
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    private var useHead = true

    func invalidate() { session.finishTasksAndInvalidate() }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }

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
    func dateSample(_ url: URL) async throws -> DirectServerTimeSource.Bound? {
        let req = request(url, method: useHead ? "HEAD" : "GET")
        let t0 = Date().timeIntervalSince1970
        let (_, response) = try await session.data(for: req)
        let t1 = Date().timeIntervalSince1970
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
