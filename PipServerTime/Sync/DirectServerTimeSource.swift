import Foundation

/// 앱이 대상 사이트에 직접 요청해서 서버시간을 측정합니다.
///
/// 1) HTTP `Date` 헤더 + 초 경계 이분 탐색 (모든 사이트)
///    - 요청 보낸 시각 t0, 받은 시각 t1, 헤더 시각 D(초 단위) →  D − t1 ≤ θ < D + 1 − t0
///      (θ = 서버시간 − 기기시간)
///    - 서버의 초가 바뀌는 경계에 요청이 도착하도록 발사 시각을 조절해 범위를 좁힘
///    - 여러 샘플 중 '가장 많은 샘플이 동의하는 구간'을 고르고, 동의하지 않는 샘플(튀는 값)은 버림
///      → 서버가 여러 대이거나 캐시된 응답이 섞여도 견딤
///
/// 참고: Cloudflare `/cdn-cgi/trace` 의 `ts=` 값도 검토했지만, 소수점 아래가 실제 시각과 0~1초 사이로
/// 무작위하게 어긋나(초 단위 정수 부분만 Date 와 같음) 밀리초 기준으로 쓸 수 없어 사용하지 않습니다.
enum DirectServerTimeSource {

    struct Result {
        var offset: TimeInterval
        var accuracy: TimeInterval
        var confidence: SyncConfidence
        var rttMedian: TimeInterval
        var samplesAgreed: Int
        var samplesTotal: Int
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
                              maxRounds: Int = 12,
                              progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Result {
        let client = HTTPClient()
        defer { client.invalidate() }

        // 0) 연결 예열 (DNS/TLS 시간이 측정에 섞이지 않도록)
        progress("서버 연결 중…")
        var bounds: [Bound] = []
        var rtts: [Double] = []
        // (예열 샘플은 연결 수립 시간이 섞여 RTT 통계에는 넣지 않고, 범위만 사용)
        guard let warm = try await client.dateSample(url) else { throw DirectError.noDateHeader }
        bounds.append(warm)

        // 1) Date 헤더 이분 탐색
        bounds.append(try await requireSample(client, url))
        rtts.append(bounds.last!.rtt)

        for i in 0..<maxRounds {
            try Task.checkCancellation()
            progress("정밀 측정 중… (\(i + 1)/\(maxRounds))")

            let consensus = Consensus(bounds)
            let guess = consensus?.mid ?? 0
            let rtt = median(rtts)

            // 서버 도착 예상 시각(서버 기준)이 다음 정수 초가 되도록 발사 시각 계산.
            // 이전 샘플과 다른 쪽(경계 직전/직후)을 번갈아 노려 구간을 양쪽에서 좁힌다.
            let nudge = (i % 2 == 0 ? 1.0 : -1.0) * min(0.01, (consensus?.width ?? 1) / 4)
            let now = Date().timeIntervalSince1970
            let boundary = ceil(now + rtt / 2 + guess + 0.15)
            let fireAt = boundary - guess - rtt / 2 + nudge
            let wait = fireAt - now
            if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }

            let b = try await requireSample(client, url)
            bounds.append(b)
            rtts.append(b.rtt)

            // 충분히 좁혀졌으면 조기 종료 (구간 폭의 하한은 대략 왕복시간)
            if bounds.count >= 6, let c = Consensus(bounds), c.width <= (rtts.min() ?? 0) * 1.3 + 0.01 {
                break
            }
        }

        guard let c = Consensus(bounds) else { throw DirectError.inconsistent }
        let agreement = Double(c.agreed) / Double(bounds.count)

        let offset = c.mid
        let accuracy = c.width / 2

        let confidence: SyncConfidence = {
            if accuracy <= 0.03 && agreement >= 0.9 { return .high }
            if accuracy <= 0.1 && agreement >= 0.7 { return .medium }
            return .low
        }()

        return Result(offset: offset, accuracy: accuracy, confidence: confidence,
                      rttMedian: median(rtts), samplesAgreed: c.agreed, samplesTotal: bounds.count)
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
