import Foundation

enum AppInfo {
    /// "1.0 (빌드 18)" — 빌드 번호는 GitHub Actions 실행 번호
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (빌드 \(build))"
    }
}
