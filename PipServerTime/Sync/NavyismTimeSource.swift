import Foundation

/// 네이비즘(time.navyism.com)과 '똑같은' 서버시간을 계산합니다.
///
/// 네이비즘 페이지(`/?host=<도메인>`)에는 다음 값이 박혀서 내려옵니다.
///
///     var mgap = 743;                          // 네이비즘 서버시각의 밀리초 부분
///     var thisTime2 = 1794396026;              // 네이비즘 서버시각 (초)
///     var mgval = new Date().getTime() - (thisTime2 * 1000 + mgap);
///     show(1794396026 - time() + 0);           // 대상 사이트 서버시각(초) - 네이비즘 시각 + 보정
///     mgval = mgval + 900;
///
/// 그리고 화면에는 `timeGap + floor((Date.now() - mgval) / 1000)` 를 0.1초마다 표시합니다.
/// (네이비즘의 '밀리초' 표시는 초가 바뀔 때 40 부터 20씩 올라가는 장식용 카운터라 실제 값이 아님)
///
/// 위 식을 정리하면, 스크립트 실행 시각을 tExec(기기, ms) 라 할 때
///
///     표시시각(ms) = 기기시각 + [ (X + Y − floor((thisTime2·1000 + mgap)/1000))·1000
///                               + thisTime2·1000 + mgap − 900 − tExec ]
///
/// 이므로 대괄호 부분이 곧 오프셋입니다. 페이지 HTML 만 받으면 웹뷰 없이 정확히 재현됩니다.
/// (이 식이 네이비즘 원본 JS 와 같은 결과를 내는지 무작위 2만 회 비교해서 확인함)
enum NavyismTimeSource {
    struct Result { let offset: TimeInterval; let accuracy: TimeInterval? }

    enum NavyismError: LocalizedError {
        case http(Int)
        case serverHasNoTime
        case parseFailed(String)

        var errorDescription: String? {
            switch self {
            case .http(let c): return "네이비즘 응답 오류 (HTTP \(c))"
            case .serverHasNoTime: return "네이비즘: 이 사이트는 서버시간을 알려주지 않습니다"
            case .parseFailed(let what): return "네이비즘 페이지 형식이 바뀌었습니다 (\(what) 없음)"
            }
        }
    }

    /// 네이비즘 페이지에서 읽어낸 값
    struct PageValues: Equatable {
        var mgap: Int
        var thisTime2: Int
        var targetSeconds: Int       // show( X - time() + Y ) 의 X
        var targetAdjust: Int        // Y
        var mgvalAdjust: Int         // mgval = mgval + A 의 A

        /// tExec(기기 시각)에 스크립트가 실행됐다고 할 때 네이비즘 표시시각 - 기기시각 (초)
        func offset(scriptExecutedAt tExec: Date) -> TimeInterval {
            let base = Double(thisTime2) * 1000 + Double(mgap)
            let gap = Double(targetSeconds + targetAdjust) - floor(base / 1000)
            let ms = gap * 1000 + base - Double(mgvalAdjust) - tExec.timeIntervalSince1970 * 1000
            return ms / 1000
        }
    }

    static func navyismURL(for target: URL) -> URL {
        var comps = URLComponents(string: "https://time.navyism.com/")!
        comps.queryItems = [URLQueryItem(name: "host", value: target.host ?? target.absoluteString)]
        return comps.url!
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        c.urlCache = nil
        c.httpShouldSetCookies = false
        c.timeoutIntervalForRequest = 15
        return URLSession(configuration: c)
    }()

    static func fetchOffset(for target: URL) async throws -> Result {
        var req = URLRequest(url: navyismURL(for: target))
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("ko-KR,ko;q=0.9", forHTTPHeaderField: "Accept-Language")

        // 페이지를 스트리밍으로 받다가, 시계 스크립트(mgval 보정 줄)가 도착한 '그 순간'을 기준 시각으로 잡는다.
        // 브라우저도 이 스크립트 블록이 도착하자마자 mgval 을 계산하므로, 페이지 나머지(광고·댓글 등)를
        // 다 받을 때까지 기다리면 그만큼 기준이 늦어진다.
        let (bytes, response) = try await session.bytes(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw NavyismError.http(http.statusCode)
        }
        var lines: [String] = []
        var tExec: Date?
        for try await line in bytes.lines {
            lines.append(line)
            if line.range(of: #"mgval\s*=\s*mgval\s*[+-]"#, options: .regularExpression) != nil {
                tExec = Date()
                break   // 필요한 값은 모두 이 줄 이전에 있음
            }
        }
        let receivedAt = tExec ?? Date()
        let values = try parse(lines.joined(separator: "\n"))
        return Result(offset: values.offset(scriptExecutedAt: receivedAt), accuracy: nil)
    }

    static func parse(_ html: String) throws -> PageValues {
        if html.range(of: #"show\(\s*['"]e['"]\s*\)"#, options: .regularExpression) != nil,
           html.range(of: #"show\(\s*\d+\s*-\s*time\(\)"#, options: .regularExpression) == nil {
            throw NavyismError.serverHasNoTime
        }
        guard let mgap = firstInt(#"var\s+mgap\s*=\s*(-?\d+)"#, in: html) else {
            throw NavyismError.parseFailed("mgap")
        }
        guard let t2 = firstInt(#"var\s+thisTime2\s*=\s*(\d+)"#, in: html) else {
            throw NavyismError.parseFailed("thisTime2")
        }
        guard let show = groups(#"show\(\s*(\d+)\s*-\s*time\(\)\s*(?:([+-])\s*(\d+))?\s*\)"#, in: html),
              let x = Int(show[0] ?? "") else {
            throw NavyismError.parseFailed("show()")
        }
        var y = 0
        if let sign = show[1], let v = Int(show[2] ?? "") { y = sign == "-" ? -v : v }

        var a = 0
        if let adj = groups(#"mgval\s*=\s*mgval\s*([+-])\s*(\d+)"#, in: html),
           let sign = adj[0], let v = Int(adj[1] ?? "") {
            a = sign == "-" ? -v : v
        }
        return PageValues(mgap: mgap, thisTime2: t2, targetSeconds: x, targetAdjust: y, mgvalAdjust: a)
    }

    // MARK: - regex helpers

    private static func firstInt(_ pattern: String, in s: String) -> Int? {
        groups(pattern, in: s).flatMap { $0.first ?? nil }.flatMap { Int($0) }
    }

    /// 첫 매치의 캡처 그룹들 (매치되지 않은 그룹은 nil)
    private static func groups(_ pattern: String, in s: String) -> [String?]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (1..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: s).map { String(s[$0]) }
        }
    }
}
