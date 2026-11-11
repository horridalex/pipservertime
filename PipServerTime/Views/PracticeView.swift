import SwiftUI

/// 반응속도 연습: 서버시계가 목표 초(xx.000)가 되는 순간 탭 → 얼마나 늦게/일찍 눌렀는지 측정
struct PracticeView: View {
    @EnvironmentObject private var store: ClockStore

    private let rounds = 5
    @State private var target: Date?
    @State private var results: [TimeInterval] = []

    /// 연습은 보정 없이 순수 서버시간 기준
    private func serverNow() -> Date { Date().addingTimeInterval(store.clock.config.serverOffset) }

    var body: some View {
        VStack(spacing: 20) {
            Text("시계가 목표 시각이 되는 순간 아래 버튼을 누르세요. \(rounds)번 반복해서 평균을 냅니다.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TimelineView(.animation(minimumInterval: 0.01)) { ctx in
                let now = ctx.date.addingTimeInterval(store.clock.config.serverOffset)
                VStack(spacing: 8) {
                    Text(ClockFormat.time(now, digits: 3))
                        .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                    if let t = target {
                        Text("목표 " + ClockFormat.time(t, digits: 3))
                            .font(.title3.monospacedDigit()).foregroundStyle(Theme.accentText)
                    }
                }
            }

            Button {
                tap()
            } label: {
                Text(target == nil ? (results.count >= rounds ? "다시 시작" : "시작") : "지금!")
                    .font(.title.bold())
                    .frame(maxWidth: .infinity, minHeight: 140)
            }
            .buttonStyle(.borderedProminent)
            .tint(target == nil ? Theme.clockCard : Theme.accent)

            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(results.indices, id: \.self) { i in
                        HStack {
                            Text("\(i + 1)회").foregroundStyle(.secondary)
                            Spacer()
                            Text(describe(results[i])).font(.body.monospacedDigit())
                        }
                    }
                    Divider()
                    HStack {
                        Text("평균").bold()
                        Spacer()
                        Text(describe(average)).font(.body.monospacedDigit().bold())
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))

                if results.count >= rounds {
                    let ms = Int((average * 1000 / 10).rounded()) * 10
                    Button("반응속도 \(ms)ms 를 시계에 반영") {
                        store.reactionAdjustMs = max(-300, min(300, ms))
                    }
                    .buttonStyle(.bordered)
                    Text("늦게 누르는 만큼 시계를 앞당겨 표시해, 시계를 보고 누르면 제때 눌리도록 합니다. (설정 > 반응속도)")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            Spacer()
        }
        .padding(20)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("연습")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var average: TimeInterval {
        results.isEmpty ? 0 : results.reduce(0, +) / Double(results.count)
    }

    private func describe(_ r: TimeInterval) -> String {
        String(format: r >= 0 ? "%.0fms 늦음" : "%.0fms 빠름", abs(r) * 1000)
    }

    private func tap() {
        let now = serverNow()
        if let t = target {
            results.append(now.timeIntervalSince(t))
            target = results.count >= rounds ? nil : nextTarget(after: now)
        } else {
            if results.count >= rounds { results = [] }
            target = nextTarget(after: now)
        }
    }

    /// 2~4초 뒤의 정각(.000)
    private func nextTarget(after now: Date) -> Date {
        let t = floor(now.timeIntervalSince1970) + Double(Int.random(in: 2...4))
        return Date(timeIntervalSince1970: t)
    }
}
