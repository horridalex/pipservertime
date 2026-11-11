import Foundation

enum URLNormalizer {
    /// "naver.com", "https://app.catchtable.co.kr/ct/shop/xxx" 등 무엇을 넣어도 https URL 로 정리
    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        guard var comps = URLComponents(string: s),
              let host = comps.host, host.contains(".") else { return nil }
        if comps.scheme != "http" && comps.scheme != "https" { comps.scheme = "https" }
        if comps.path.isEmpty { comps.path = "/" }
        return comps.url
    }
}
