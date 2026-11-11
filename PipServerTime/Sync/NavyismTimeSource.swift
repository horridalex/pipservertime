import Foundation
import UIKit
import WebKit

/// 네이비즘(time.navyism.com)에서 대상 사이트의 서버시간을 가져옵니다.
///
/// 네이비즘은 공개 API 가 없고, 페이지 안의 JavaScript 가 서버시간 시계를 그려줍니다.
/// 그래서 숨겨진 WKWebView 로 `https://time.navyism.com/?host=<호스트>` 를 열고,
/// 페이지에 표시되는 시계 텍스트(예: "19시 16분 00초" / "19:16:00")를 읽습니다.
///
/// 내부 변수명에 의존하지 않고 화면에 표시되는 글자만 읽기 때문에
/// 네이비즘 페이지 구조가 조금 바뀌어도 동작합니다.
///
/// 밀리초 정밀도: 표시되는 '초'가 바뀌는 순간(= 네이비즘 기준 서버시간 xx.000초)을
/// 4ms 간격으로 감시해서 그 순간의 기기시간과 비교합니다.
@MainActor
enum NavyismTimeSource {
    struct Result { let offset: TimeInterval; let accuracy: TimeInterval? }

    enum NavyismError: LocalizedError {
        case loadFailed(String)
        case timeNotFound
        case noSecondTransition

        var errorDescription: String? {
            switch self {
            case .loadFailed(let m): return "페이지를 열 수 없습니다 (\(m))"
            case .timeNotFound: return "페이지에서 서버시간을 찾지 못했습니다"
            case .noSecondTransition: return "초 변경 시점을 감지하지 못했습니다"
            }
        }
    }

    static func navyismURL(for target: URL) -> URL {
        var comps = URLComponents(string: "https://time.navyism.com/")!
        // 네이비즘은 host 파라미터에 도메인을 받습니다. (예: ?host=www.naver.com)
        comps.queryItems = [URLQueryItem(name: "host", value: target.host ?? target.absoluteString)]
        return comps.url!
    }

    static func fetchOffset(for target: URL, timeout: TimeInterval = 15) async throws -> Result {
        let loader = HiddenWebLoader()
        defer { loader.tearDown() }

        try await loader.load(navyismURL(for: target), timeout: timeout)
        // 네이비즘 페이지가 서버시간을 받아와 시계를 보정할 시간을 줍니다.
        try await Task.sleep(nanoseconds: 1_500_000_000)

        // 1회 측정: 초가 바뀌는 순간을 2번 잡아서 평균
        var offsets: [TimeInterval] = []
        for _ in 0..<2 {
            try Task.checkCancellation()
            guard let raw = try await loader.webView.callAsyncJavaScript(
                watchScript, arguments: ["timeoutMs": 6000], in: nil, contentWorld: .page
            ) as? [String: Any] else {
                throw NavyismError.timeNotFound
            }
            guard let h = (raw["h"] as? NSNumber)?.intValue,
                  let m = (raw["m"] as? NSNumber)?.intValue,
                  let s = (raw["s"] as? NSNumber)?.intValue,
                  let t = (raw["t"] as? NSNumber)?.doubleValue else {
                throw NavyismError.timeNotFound
            }
            guard (raw["edge"] as? Bool) == true else { throw NavyismError.noSecondTransition }
            // t: 초가 바뀐 순간의 기기시간 (Date.now(), ms). 이 순간 서버시간 = h:m:s.000
            let deviceAtEdge = Date(timeIntervalSince1970: t / 1000)
            offsets.append(offset(serverH: h, m: m, s: s, at: deviceAtEdge))
        }
        // 두 값이 크게 다르면(페이지가 측정 중 보정됨) 마지막 값을 사용
        let avg = abs(offsets[0] - offsets[1]) > 0.2
            ? offsets[1]
            : offsets.reduce(0, +) / Double(offsets.count)
        // 4ms 폴링 + 네이비즘 자체 오차는 알 수 없으므로 폴링 간격 기준만 표시
        return Result(offset: avg, accuracy: 0.01)
    }

    /// 서버의 '시:분:초'와 기기시간 차이를 계산.
    /// 네이비즘이 어느 시간대로 표시하든(KST/기기 시간대) 영향을 받지 않도록
    /// 분·초만 비교하고 ±30분 범위로 정규화합니다. (서버시간 차이가 30분 이상인 경우는 없음)
    static func offset(serverH: Int, m: Int, s: Int, at device: Date) -> TimeInterval {
        let deviceSec = device.timeIntervalSince1970
        let deviceInHour = deviceSec.truncatingRemainder(dividingBy: 3600)   // 0..<3600 (UTC 기준, 정시 단위 시간대 무관)
        let serverInHour = Double(m * 60 + s)
        var diff = serverInHour - deviceInHour
        while diff >= 1800 { diff -= 3600 }
        while diff < -1800 { diff += 3600 }
        return diff
    }

    /// 페이지에서 시계 텍스트를 찾아 초가 바뀌는 순간을 감시하는 스크립트
    private static let watchScript = #"""
    const patterns = [
      /(\d{1,2})\s*시\s*(\d{1,2})\s*분\s*(\d{1,2})\s*초/,
      /(\d{1,2}):(\d{2}):(\d{2})/
    ];
    const parse = (text) => {
      if (!text) return null;
      for (const p of patterns) {
        const r = p.exec(text);
        if (r) return [parseInt(r[1], 10), parseInt(r[2], 10), parseInt(r[3], 10)];
      }
      return null;
    };
    // 시계 텍스트를 가진 '가장 안쪽' 요소들을 후보로 모은다.
    // 고정된 시각 문구가 섞여 있을 수 있으므로, 실제로 값이 바뀌는 후보를 시계로 판단한다.
    const findCandidates = () => {
      const all = document.body ? document.body.getElementsByTagName('*') : [];
      const out = [];
      for (const el of all) {
        if (el.tagName === 'SCRIPT' || el.tagName === 'STYLE') continue;
        const txt = el.innerText;
        if (!txt || txt.length > 200 || !parse(txt)) continue;
        let childMatches = false;
        for (const c of el.children) { if (c.innerText && parse(c.innerText)) { childMatches = true; break; } }
        if (!childMatches) out.push(el);
      }
      return out;
    };
    const deadline = Date.now() + timeoutMs;
    return await new Promise((resolve) => {
      let cands = [];
      let prev = new Map();
      let last = null;
      const tick = () => {
        const now = Date.now();
        if (cands.length === 0 || cands.some(e => !e.isConnected)) { cands = findCandidates(); prev = new Map(); }
        for (const el of cands) {
          const cur = parse(el.innerText);
          if (!cur) continue;
          last = cur;
          const key = cur.join(':');
          const p = prev.get(el);
          if (p !== undefined && p !== key) {
            resolve({ h: cur[0], m: cur[1], s: cur[2], t: now, edge: true });
            return;
          }
          prev.set(el, key);
        }
        if (now > deadline) {
          resolve(last ? { h: last[0], m: last[1], s: last[2], t: now, edge: false } : null);
          return;
        }
        setTimeout(tick, cands.length ? 4 : 100);
      };
      tick();
    });
    """#
}

/// 화면에 거의 보이지 않게 붙여두는 WKWebView. (윈도우에 붙어있지 않으면 JS 타이머가 느려질 수 있음)
@MainActor
final class HiddenWebLoader: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private var continuation: CheckedContinuation<Void, Error>?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = .all
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.alpha = 0.01
        webView.isUserInteractionEnabled = false
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        window?.insertSubview(webView, at: 0)
    }

    func load(_ url: URL, timeout: TimeInterval) async throws {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("ko-KR,ko;q=0.9", forHTTPHeaderField: "Accept-Language")
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            continuation = c
            webView.load(request)
        }
    }

    func tearDown() {
        webView.stopLoading()
        webView.removeFromSuperview()
    }

    private func finish(_ error: Error?) {
        guard let c = continuation else { return }
        continuation = nil
        if let error { c.resume(throwing: NavyismTimeSource.NavyismError.loadFailed(error.localizedDescription)) }
        else { c.resume() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(nil) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(error) }
}
