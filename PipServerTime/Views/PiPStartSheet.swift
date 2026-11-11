import SwiftUI

/// 팝업 타이머 시작 옵션: 지정한 서버시각(HH:mm:ss)에 PiP 자동으로 닫기
struct PiPStartSheet: View {
    @EnvironmentObject private var store: ClockStore
    @Environment(\.dismiss) private var dismiss

    @State private var enabled = false
    @State private var h = 0
    @State private var m = 0
    @State private var s = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("좌석 선택·결제 등에 집중할 때 팝업 타이머가 화면을 가리지 않도록, 동기화된 서버시간이 지정한 시각에 도달하면 PiP 를 자동으로 닫습니다.")
                        .font(.subheadline).foregroundStyle(.secondary)

                    Toggle("지정한 시각에 PiP 자동으로 사라지게 하기", isOn: $enabled)
                        .font(.headline)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))

                    Card {
                        Text("사라지는 시각").font(.headline)
                        HStack(spacing: 0) {
                            wheel($h, 0..<24, "시")
                            wheel($m, 0..<60, "분")
                            wheel($s, 0..<60, "초")
                        }
                        .frame(height: 180)
                        Text(String(format: "동기화된 서버시간이 %02d:%02d:%02d에 도달하면 PiP 가 자동으로 닫힙니다.", h, m, s))
                            .font(.footnote).foregroundStyle(.secondary)
                        if store.nextEvent != nil {
                            Button("다음 일정 + 5초로 맞추기") { load(store.suggestedAutoCloseSecondOfDay()) }
                                .font(.footnote)
                        }
                    }
                    .disabled(!enabled)
                    .opacity(enabled ? 1 : 0.5)
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Text("취소").bold().frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        store.autoClosePiP = enabled
                        store.autoCloseSecondOfDay = h * 3600 + m * 60 + s
                        dismiss()
                        // 시트가 닫힌 뒤 시작해야 PiP 원본 레이어가 화면에 보이는 상태
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.pip.toggle() }
                    } label: {
                        Text("PiP 시작").bold().frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(16)
                .background(.bar)
            }
            .navigationTitle("팝업 타이머 시작 옵션")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                enabled = store.autoClosePiP
                load(store.autoCloseSecondOfDay == 0 ? store.suggestedAutoCloseSecondOfDay() : store.autoCloseSecondOfDay)
            }
        }
        .presentationDetents([.large])
    }

    private func load(_ secondOfDay: Int) {
        h = secondOfDay / 3600
        m = (secondOfDay % 3600) / 60
        s = secondOfDay % 60
    }

    private func wheel(_ value: Binding<Int>, _ range: Range<Int>, _ unit: String) -> some View {
        VStack(spacing: 4) {
            Picker(unit, selection: value) {
                ForEach(range, id: \.self) { Text(String(format: "%02d", $0)).font(.title2.monospacedDigit()).tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()
            Text(unit).font(.subheadline.weight(.semibold))
        }
    }
}
