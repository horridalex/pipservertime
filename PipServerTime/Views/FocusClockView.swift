import SwiftUI

/// 타이머 집중 화면: 서버시계 하나만 화면 가득 (가로로 돌리면 더 크게)
struct FocusClockView: View {
    @EnvironmentObject private var store: ClockStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TimelineView(.animation(minimumInterval: 0.01)) { ctx in
                let cfg = store.clock.config
                let now = ctx.date.addingTimeInterval(cfg.offset)
                let remain: TimeInterval? = store.nextEvent.map { $0.date.timeIntervalSince(now) }
                let red = isRed(now: now, remain: remain)

                VStack(spacing: 12) {
                    Spacer()
                    Text(ClockFormat.dateOnly(now))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.gray)
                    Text(ClockFormat.time(now, digits: store.appDigits))
                        .font(.system(size: 400, weight: .bold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.05)
                        .lineLimit(1)
                        .foregroundStyle(red ? Color.red : Color.white)
                        .padding(.horizontal, 12)
                    if let e = store.nextEvent, let remain {
                        Text("\(e.name)  \(remain > 0 ? ClockFormat.countdown(remain) + " 남음" : "시작됨")")
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .foregroundStyle(remain > 0 && remain < 60 ? Color.red : Color.blue)
                    }
                    if let r = store.result {
                        Text(infoLine(r))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.gray)
                    }
                    Spacer()
                    Text("화면을 두 번 탭하면 닫힙니다 · 가로로 돌리면 더 크게 보입니다")
                        .font(.caption).foregroundStyle(Color.gray.opacity(0.7))
                        .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(Circle().fill(Color.white.opacity(0.15)))
            }
            .padding(16)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { dismiss() }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }     // 화면 꺼짐 방지
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func isRed(now: Date, remain: TimeInterval?) -> Bool {
        guard store.redBeforeMinute else { return false }
        let secOfMinute = now.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
        if secOfMinute >= 60 - DisplayClock.redWindow { return true }
        if let remain, remain > 0, remain <= DisplayClock.redWindow { return true }
        return false
    }

    private func infoLine(_ r: SyncResult) -> String {
        var parts: [String] = [r.siteName]
        if let a = r.accuracy { parts.append(String(format: "오차 ±%.0fms", a * 1000)) }
        let c = store.totalCorrection
        if abs(c) >= 0.0005 { parts.append("보정 " + Fmt.signedSec(c)) }
        return parts.joined(separator: "  ·  ")
    }
}
