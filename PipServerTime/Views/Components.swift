import SwiftUI

/// 둥근 카드 컨테이너
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Theme.ink)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.border))
    }
}

/// 작은 캡슐 배지
struct Badge: View {
    var text: String
    var tint: Color = Theme.accentText

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(tint)
            .background(Capsule().fill(tint.opacity(0.15)))
    }
}

/// 측정 중 샘플 막대 (민트 = 계산에 사용, 회색 = 지연이 커서 제외, 흐림 = 아직 안 보냄)
struct SampleBars: View {
    var samples: [DirectServerTimeSource.Sample]
    var planned: Int
    var usedColor: Color = Theme.accent
    var excludedColor: Color = Color.gray.opacity(0.6)
    var pendingColor: Color = Color.gray.opacity(0.25)

    var body: some View {
        // 막대가 수백 개여도 화면 폭 안에 들어가도록 Canvas 로 직접 그림
        Canvas { ctx, size in
            let count = max(planned, samples.count, 1)
            // 간격은 막대 폭의 최대 40%, 1.5pt 를 넘지 않음
            let slot = size.width / CGFloat(count)
            let gap = min(1.5, slot * 0.4)
            let w = max(0.5, slot - gap)
            let maxRTT = max(samples.map(\.rtt).max() ?? 0.1, 0.001)
            for i in 0..<count {
                let x = CGFloat(i) * slot
                let h: CGFloat
                let color: Color
                if i < samples.count {
                    let s = samples[i]
                    h = max(6, size.height * CGFloat(s.rtt / maxRTT))
                    color = s.used ? usedColor : excludedColor
                } else {
                    h = size.height * 0.25
                    color = pendingColor
                }
                let rect = CGRect(x: x, y: size.height - h, width: w, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: min(1, w / 2)), with: .color(color))
            }
        }
        .frame(height: 70)
        .accessibilityLabel("측정 샘플 \(samples.count)개 중 \(samples.filter(\.used).count)개 사용")
    }
}

/// 앱 안의 시계 = PiP 원본 레이어 (레이어가 화면에 붙어 있어야 PiP 시작 가능)
struct ClockPreview: UIViewRepresentable {
    let pip: PiPClockController

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = PiPPalette.background
        container.layer.cornerRadius = 12
        container.clipsToBounds = true
        let v = pip.displayView
        v.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            v.topAnchor.constraint(equalTo: container.topAnchor),
            v.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

extension SyncConfidence {
    var color: Color {
        switch self {
        case .high: return Theme.accentText
        case .medium: return Color(UIColor(hex: 0xE67700))
        case .low: return Theme.warning
        }
    }
}

enum Fmt {
    static func ms(_ t: TimeInterval) -> String { String(format: "%.0fms", t * 1000) }
    static func signedSec(_ t: TimeInterval) -> String { String(format: "%+.3f초", t) }

    static func ago(_ d: Date, now: Date) -> String {
        let s = Int(now.timeIntervalSince(d))
        if s < 60 { return "\(max(0, s))초 전" }
        if s < 3600 { return "\(s / 60)분 전" }
        return "\(s / 3600)시간 전"
    }
}
