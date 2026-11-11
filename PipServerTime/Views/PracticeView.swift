import SwiftUI
import QuartzCore

/// 반응속도 연습: 55.000초에서 시작해 00.000초(정각)가 되는 순간 누르기
struct PracticeView: View {
    @EnvironmentObject private var store: ClockStore

    private let rounds = 5
    /// 시작 후 정각까지 걸리는 시간 (55초 → 00초)
    private let target: TimeInterval = 5
    private let startSecond: TimeInterval = 55

    /// 진행 중인 회차의 시작 시각 (CACurrentMediaTime, 시계 조정 영향 없음)
    @State private var startedAt: CFTimeInterval?
    @State private var results: [TimeInterval] = []
    @State private var lastStop: TimeInterval?

    private var finished: Bool { results.count >= rounds }

    var body: some View {
        CardScreen {
            Text("시작을 누르면 55초부터 흘러가요. 00초(정각)가 되는 순간 누르세요. \(rounds)번 해서 평균을 내요.")
                .font(.subheadline).foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            // 스톱워치
            VStack(spacing: 6) {
                TimelineView(.animation(minimumInterval: 0.005)) { _ in
                    Text(formatSeconds(displayedValue()))
                        .font(.system(size: 72, weight: .heavy).monospacedDigit())
                        .foregroundStyle(Theme.clockText)
                        .minimumScaleFactor(0.5).lineLimit(1)
                }
                Text(statusText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(lastStop.map { abs($0 - target) <= 0.05 } == true ? Theme.accent : Theme.clockDim)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.clockCard))

            Button(action: tap) {
                Text(startedAt != nil ? "지금!" : (finished ? "다시 하기" : (results.isEmpty ? "시작" : "다음 (\(results.count + 1)/\(rounds))")))
                    .font(.title2.weight(.heavy))
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .foregroundStyle(startedAt != nil ? Theme.clockCard : Theme.primaryButtonText)
                    .background(RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(startedAt != nil ? Theme.accent : Theme.primaryButton))
            }
            .buttonStyle(.plain)

            if !results.isEmpty {
                SectionHeader(text: "결과")
                SettingsCard {
                    ForEach(results.indices, id: \.self) { i in
                        if i > 0 { RowDivider() }
                        RowLabel(title: "\(i + 1)회") {
                            Text(describe(results[i] - target)).font(.body.monospacedDigit()).foregroundStyle(Theme.ink)
                        }
                    }
                    if finished {
                        RowDivider()
                        RowLabel(title: "평균") {
                            Text(describe(average)).font(.body.monospacedDigit().weight(.bold)).foregroundStyle(Theme.accentText)
                        }
                    }
                }

                if finished {
                    let ms = Int((average * 1000 / 10).rounded()) * 10
                    Button {
                        store.reactionAdjustMs = max(-300, min(300, ms))
                    } label: {
                        Text("반응속도 \(ms)ms 를 시계에 반영")
                    }
                    .buttonStyle(CapsuleButtonStyle(filled: false))
                    Text("늦게 누르는 만큼 시계를 앞당겨 표시해서, 시계를 보고 누르면 제때 눌리게 해요. (설정 › 반응속도)")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("연습")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 시작 후 경과 시간
    private func displayedValue() -> TimeInterval {
        if let s = startedAt { return CACurrentMediaTime() - s }
        return lastStop ?? 0
    }

    /// 경과 시간을 시계 초로: 55.000 → 59.999 → 00.000 → 01.xxx
    private func formatSeconds(_ elapsed: TimeInterval) -> String {
        let v = (startSecond + elapsed).truncatingRemainder(dividingBy: 60)
        return String(format: "%06.3f", v)
    }

    private var statusText: String {
        if startedAt != nil { return "00.000초에 누르세요" }
        if let last = lastStop { return describe(last - target) }
        return "55초에서 시작 · 목표 00.000초"
    }

    /// 평균 오차 (+ 늦음, − 빠름)
    private var average: TimeInterval {
        results.isEmpty ? 0 : results.map { $0 - target }.reduce(0, +) / Double(results.count)
    }

    private func describe(_ diff: TimeInterval) -> String {
        let ms = Int((abs(diff) * 1000).rounded())
        if ms == 0 { return "정확!" }
        return diff > 0 ? "\(ms)ms 늦음" : "\(ms)ms 빠름"
    }

    private func tap() {
        let now = CACurrentMediaTime()
        if let s = startedAt {
            let elapsed = now - s
            results.append(elapsed)
            lastStop = elapsed
            startedAt = nil
        } else {
            if finished { results = [] }
            lastStop = nil
            startedAt = now
        }
    }
}
