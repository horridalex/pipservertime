import SwiftUI

/// 둥근 카드 컨테이너
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.primary.opacity(0.06)))
    }
}

/// 작은 캡슐 배지
struct Badge: View {
    var text: String
    var tint: Color = .blue

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(tint)
            .background(Capsule().fill(tint.opacity(0.15)))
    }
}

/// 측정 중 샘플 막대 (파랑 = 계산에 사용, 회색 = 지연이 커서 제외, 흐림 = 아직 안 보냄)
struct SampleBars: View {
    var samples: [DirectServerTimeSource.Sample]
    var planned: Int

    var body: some View {
        GeometryReader { geo in
            let count = max(planned, samples.count, 1)
            let spacing: CGFloat = 1.5
            let w = max(1, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            let maxRTT = max(samples.map(\.rtt).max() ?? 0.1, 0.001)
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(0..<count, id: \.self) { i in
                    if i < samples.count {
                        let s = samples[i]
                        RoundedRectangle(cornerRadius: 1)
                            .fill(s.used ? Color.blue : Color.gray.opacity(0.6))
                            .frame(width: w, height: max(6, geo.size.height * CGFloat(s.rtt / maxRTT)))
                    } else {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.gray.opacity(0.25))
                            .frame(width: w, height: geo.size.height * 0.25)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 70)
    }
}

/// 앱 안의 시계 = PiP 원본 레이어 (레이어가 화면에 붙어 있어야 PiP 시작 가능)
struct ClockPreview: UIViewRepresentable {
    let pip: PiPClockController

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
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
            // 렌더 크기(1200x200)와 같은 6:1 비율
            v.heightAnchor.constraint(equalTo: v.widthAnchor, multiplier: 1.0 / 6.0),
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

extension SyncConfidence {
    var color: Color {
        switch self {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .orange
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
