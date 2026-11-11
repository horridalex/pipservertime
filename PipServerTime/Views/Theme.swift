import SwiftUI
import UIKit

/// 페이퍼 테마: 아이보리 + 잉크 + 민트 (다크 모드에선 잉크 바탕)
enum Theme {
    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    /// 화면 바탕
    static let bg = dynamic(0xF4F1EA, 0x0F1013)
    /// 카드 바탕
    static let card = dynamic(0xFFFFFF, 0x1A1C21)
    /// 카드 테두리
    static let border = dynamic(0xE4DFD3, 0x2A2D35)
    /// 본문 글자
    static let ink = dynamic(0x16181D, 0xFBF9F4)
    /// 보조 글자
    static let secondary = dynamic(0x5F6470, 0xA4A8B2)
    /// 강조색 글자 (흰 바탕 대비 확보용 진한 민트)
    static let accentText = dynamic(0x0B7D5C, 0x3DD9A4)
    /// 강조색 채움
    static let accent = Color(UIColor(hex: 0x12B886))
    /// 강조색 옅은 바탕
    static let accentSoft = dynamic(0xE8F7F1, 0x12302A)
    static let accentSoftText = dynamic(0x0B5A43, 0x9BEBCF)

    /// 시계 카드 (밝은 모드에서도 잉크)
    static let clockCard = Color(UIColor(hex: 0x16181D))
    static let clockCardLine = Color(UIColor(hex: 0x2A2D35))
    static let clockText = Color(UIColor(hex: 0xFBF9F4))
    static let clockDim = Color(UIColor(hex: 0xB9BCC4))
    static let clockPill = Color(UIColor(hex: 0x2A2D35))

    static let warning = Color(UIColor(hex: 0xE8590C))
    static let alert = Color(UIColor(hex: 0xFA5252))
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension View {
    /// 리스트/폼 화면에 페이퍼 바탕 적용
    func paperBackground() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
    }
}

/// 둥근 캡슐 버튼 스타일 (다시 측정 / 팝업 타이머)
struct CapsuleButtonStyle: ButtonStyle {
    var filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.bold))
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(filled ? Theme.clockText : Theme.ink)
            .background(Capsule().fill(filled ? Theme.clockCard : Theme.card))
            .overlay(Capsule().stroke(filled ? Color.clear : Theme.border))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// 상단 둥근 아이콘 버튼
struct RoundIconLabel: View {
    var systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Theme.card))
            .overlay(Circle().stroke(Theme.border))
    }
}
