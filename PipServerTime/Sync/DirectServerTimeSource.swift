import Foundation

/// 네이비즘을 쓸 수 없을 때, 앱이 대상 사이트에 직접 요청해서 서버시간을 측정합니다.
///
/// 원리 (네이비즘과 동일한 방식):
///  - 모든 웹 서버는 응답에 `Date: Wed, 11 Nov 2026 10:16:00 GMT` 헤더를 붙입니다. (1초 단위)
///  - 요청을 보낸 기기시각 t0, 응답을 받은 기기시각 t1, 헤더 시각 D 를 알면
///      서버시간 = 기기시간 + θ 에서   D - t1  ≤  θ  <  D + 1 - t0
///  - 서버의 '초'가 바뀌는 경계 근처에 요청이 도착하도록 보내는 시점을 조절하며
///    이 범위를 계속 좁혀(이분 탐색) 밀리초 단위로 θ 를 구합니다.
///  - 최종 오차는 대략 왕복시간(RTT)의 절반 수준입니다.
enum DirectServerTimeSource {
    struct Result { let offset: TimeInterval; let accuracy: TimeInterval }

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

    private struct Sample { let t0: Date; let t1: Date; let serverSecond: Date }

    static func measureOffset(url: URL,
                              rounds: Int = 10,
                              progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Result {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 1
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        var useHead = true

        func sample() async throws -> Sample {
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            // 캐시/CDN 이 오래된 Date 를 주지 않도록 쿼리 추가
            var items = comps.queryItems ?? []
            items.append(URLQueryItem(name: "_pst", value: String(Int(Date().timeIntervalSince1970 * 1000))))
            comps.queryItems = items
            var req = URLRequest(url: comps.url ?? url)
            req.httpMethod = useHead ? "HEAD" : "GET"
            req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            req.setValue("no-cache", forHTTPHeaderField: "Pragma")
            if !useHead { req.setValue("bytes=0-0", forHTTPHeaderField: "Range") }

            let t0 = Date()
            let (_, response) = try await session.data(for: req)
            let t1 = Date()
            guard let http = response as? HTTPURLResponse,
                  let dateString = http.value(forHTTPHeaderField: "Date"),
                  let d = httpDateFormatter.date(from: dateString) else {
                if useHead { useHead = false; return try await sample() }  // HEAD 를 막은 서버 → GET 재시도
                throw DirectError.noDateHeader
            }
            if useHead, http.statusCode == 405 || http.statusCode == 501 {
                useHead = false; return try await sample()
            }
            return Sample(t0: t0, t1: t1, serverSecond: d)
        }

        // 1) 연결 예열 (DNS/TLS 시간이 측정에 섞이지 않도록)
        progress("서버 연결 중…")
        _ = try await sample()

        // 2) 대략적인 범위
        var lower = -Double.infinity
        var upper = Double.infinity
        var rtts: [TimeInterval] = []

        func absorb(_ s: Sample) {
            let d = s.serverSecond.timeIntervalSince1970
            lower = max(lower, d - s.t1.timeIntervalSince1970)
            upper = min(upper, d + 1 - s.t0.timeIntervalSince1970)
            rtts.append(s.t1.timeIntervalSince(s.t0))
        }

        absorb(try await sample())

        // 3) 이분 탐색: 서버의 초 경계에 요청이 도착하도록 발사 시각 조절
        for i in 0..<rounds {
            try Task.checkCancellation()
            progress("정밀 측정 중… (\(i + 1)/\(rounds))")
            if upper < lower {
                // 서버가 여러 대(시각이 서로 다름)일 수 있음 → 처음부터 다시 좁히기
                lower = -Double.infinity; upper = Double.infinity
            }
            let theta = (lower.isFinite && upper.isFinite) ? (lower + upper) / 2 : 0
            let rtt = rtts.sorted()[rtts.count / 2]   // RTT 중앙값
            let now = Date().timeIntervalSince1970
            // 서버 도착 예상 시각(서버 기준)이 다음 정수 초가 되도록 발사 시각 계산
            let arrivalServer = now + rtt / 2 + theta + 0.15
            let boundary = ceil(arrivalServer)
            let fireAt = boundary - theta - rtt / 2
            let wait = fireAt - now
            if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            absorb(try await sample())
        }

        guard lower.isFinite, upper.isFinite, upper >= lower else { throw DirectError.inconsistent }
        let offset = (lower + upper) / 2
        return Result(offset: offset, accuracy: (upper - lower) / 2)
    }

    private static let httpDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()
}
