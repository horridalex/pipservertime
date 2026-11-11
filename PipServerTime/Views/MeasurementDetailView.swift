import SwiftUI
import Charts

struct MeasurementDetailView: View {
    @EnvironmentObject private var store: ClockStore

    var body: some View {
        ScrollView {
            if let r = store.result {
                VStack(alignment: .leading, spacing: 16) {
                    header(r)
                    if !r.samples.isEmpty {
                        rttChart(r)
                        passTable(r)
                    }
                    if r.multiServerSuspected { multiServerCard(r) }
                    if r.accuracy != nil { driftCard(r) }
                    if r.source == .navyism { navyismNote }
                }
                .padding(16)
            } else {
                Text("아직 측정 결과가 없습니다.").foregroundStyle(.secondary).padding(40)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("측정 근거")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ r: SyncResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(r.siteName) · 추정 오차").font(.headline).foregroundStyle(.secondary)
            if let a = r.accuracy {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "±%.0f", a * 1000))
                        .font(.system(size: 64, weight: .bold, design: .rounded)).foregroundStyle(Theme.accentText)
                    Text("ms").font(.title.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text("표시되는 서버시간은 실제 서버시간과 대부분 이 범위 안에서 차이 납니다.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("네이비즘 계산값").font(.largeTitle.bold())
            }
            HStack(spacing: 8) {
                if let c = r.confidence { Badge(text: "신뢰도 " + c.title, tint: c.color) }
                Badge(text: r.source == .navyism ? "네이비즘" : "직접 측정", tint: Theme.secondary)
                Badge(text: "서버 " + Fmt.signedSec(r.offset), tint: Theme.secondary)
            }
        }
    }

    private func rttChart(_ r: SyncResult) -> some View {
        Card {
            HStack {
                Text("응답 지연(RTT) 샘플 \(r.samples.count)개").font(.headline)
                Spacer()
                Text("ms").font(.footnote).foregroundStyle(.secondary)
            }
            Chart(r.samples) { s in
                PointMark(x: .value("순서", s.id), y: .value("RTT", s.rtt * 1000))
                    .foregroundStyle(s.used ? Theme.accentText : Color.gray.opacity(0.6))
                    .symbolSize(s.boundary ? 60 : 30)
            }
            .chartXAxis(.hidden)
            .frame(height: 180)
            HStack(spacing: 16) {
                Label("계산에 사용 \(r.usedCount)", systemImage: "circle.fill").foregroundStyle(Theme.accentText)
                Label("지연이 커서 제외 \(r.samples.count - r.usedCount)", systemImage: "circle.fill")
                    .foregroundStyle(.gray)
            }
            .font(.footnote)
            if let rtt = r.rttMedian {
                Text(String(format: "사용 샘플 왕복 지연 중앙값 %.0fms · 최소 %.0fms", rtt * 1000, (r.rttMin ?? rtt) * 1000))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func passTable(_ r: SyncResult) -> some View {
        Card {
            Text("패스별 결과 (누적)").font(.headline)
            ForEach(r.passes) { p in
                HStack {
                    Text("\(p.pass)차").foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
                    Text(String(format: "RTT %.0f", p.rttMin * 1000)).font(.body.monospaced())
                    Spacer()
                    Text(String(format: "±%.0f", p.halfWidth * 1000)).font(.footnote.monospaced()).foregroundStyle(.secondary)
                    Text(String(format: "%+.0fms", p.offset * 1000)).font(.body.monospaced())
                        .frame(width: 90, alignment: .trailing)
                }
                Divider()
            }
            HStack {
                Text("최종").bold()
                Spacer()
                Text(String(format: "%+.0fms", r.offset * 1000)).font(.body.monospaced().bold()).foregroundStyle(Theme.accentText)
            }
        }
    }

    private func multiServerCard(_ r: SyncResult) -> some View {
        Card {
            Label("서버마다 시각이 달라요", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(Theme.warning)
            Text("패스마다 따로 잰 값이 최대 \(Int(((r.passSpread ?? 0) * 1000).rounded()))ms 차이 나요. 사이트가 서버 여러 대를 쓰고 서버마다 시계가 조금씩 다른 경우예요. 예매 요청이 어느 서버로 갈지는 알 수 없어서, 실제 오차는 표시된 ±값보다 클 수 있어요.")
                .font(.footnote).foregroundStyle(Theme.secondary)
        }
    }

    private func driftCard(_ r: SyncResult) -> some View {
        Card {
            Text("시간이 지나면").font(.headline)
            HStack {
                ForEach([0, 10, 30], id: \.self) { m in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(m == 0 ? "지금" : "\(m)분 뒤").font(.footnote).foregroundStyle(.secondary)
                        Text("±" + Fmt.ms(r.projectedAccuracy(at: Date().addingTimeInterval(Double(m) * 60)) ?? 0))
                            .font(.title3.monospacedDigit().weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("폰 시계는 시간이 지나며 조금씩 어긋납니다(분당 약 0.6ms 가정). 오픈 3–5분 전에 한 번 더 측정하면 가장 정확합니다. 일정을 등록하면 자동으로 재측정합니다.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var navyismNote: some View {
        Card {
            Text("네이비즘 계산값에 대해").font(.headline)
            Text("네이비즘은 사이트와의 차이를 초 단위로만 반영하고, 밀리초는 네이비즘 자체 서버 시계 + −900ms 보정으로 정해집니다. 그래서 오차 범위를 계산할 수 없고, 실제 서버시간보다 수백 ms 늦을 수 있습니다.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
