import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ClockStore

    var body: some View {
        Form {
            timeSection
            networkSection
            accuracySection
            timerSection
            displaySection
            scheduleSection
        }
        .navigationTitle("설정")
    }

    // MARK: - 시간 계산

    private var timeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("반응속도를 시계에 반영하기")
                    Spacer()
                    Text("\(store.reactionAdjustMs)ms").font(.body.monospacedDigit()).foregroundStyle(.blue)
                }
                HStack {
                    Button { store.reactionAdjustMs = max(-300, store.reactionAdjustMs - 10) } label: { Image(systemName: "minus") }
                        .buttonStyle(.borderless)
                    Slider(value: Binding(get: { Double(store.reactionAdjustMs) },
                                          set: { store.reactionAdjustMs = Int(($0 / 10).rounded()) * 10 }),
                           in: -300...300)
                    Button { store.reactionAdjustMs = min(300, store.reactionAdjustMs + 10) } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                }
            }

            Stepper(value: $store.pipStepMs, in: 10...500, step: 10) {
                HStack {
                    Text("PiP 내에서 보정 시 단위")
                    Spacer()
                    Text(String(format: "%.2f초", Double(store.pipStepMs) / 1000))
                        .font(.body.monospacedDigit()).foregroundStyle(.blue)
                }
            }

            HStack {
                Text("PiP 에서 조정한 값")
                Spacer()
                Text("\(store.pipAdjustMs)ms").font(.body.monospacedDigit()).foregroundStyle(.secondary)
                Button("초기화") { store.pipAdjustMs = 0 }
                    .buttonStyle(.borderless)
                    .disabled(store.pipAdjustMs == 0)
            }
        } header: {
            Text("시간 계산")
        } footer: {
            Text("연습 모드에서 측정한 내 반응속도만큼 시계를 앞당겨 두면 제때 누르기 쉬워요. PiP 창의 ◀◀ / ▶▶ 버튼으로도 위 단위만큼 늦추거나 앞당길 수 있습니다.")
        }
    }

    private var networkSection: some View {
        Section {
            Toggle(isOn: $store.applyLead) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("네트워크 딜레이를 시계에 반영하기")
                    if let lead = store.result?.recommendedLead {
                        Text(String(format: "현재 약 %.3f초", lead)).font(.footnote.monospacedDigit()).foregroundStyle(.blue)
                    } else {
                        Text("직접 측정 후 계산됩니다").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        } footer: {
            Text("동기화한 사이트까지 신호가 가는 시간(왕복 지연의 절반)만큼 시계를 앞당겨 보여줘요. 해외 사이트처럼 서버가 멀리 있을 때 유용해요.")
        }
    }

    // MARK: - 정확도

    private var accuracySection: some View {
        Section {
            Picker("측정 방식", selection: $store.source) {
                ForEach(SyncSource.allCases) { Text($0.title).tag($0) }
            }
            ForEach(AccuracyPreset.allCases) { p in
                Button {
                    store.accuracyPreset = p
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.title).foregroundStyle(.primary)
                            let l = p.level ?? store.customLevel
                            Text("\(p.subtitle) (샘플: \(l.samples)/반복: \(l.passes)/경계보정: \(l.boundary))")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.accuracyPreset == p { Image(systemName: "checkmark").foregroundStyle(.blue) }
                    }
                }
            }
            if store.accuracyPreset == .custom {
                Stepper("샘플 \(store.customLevel.samples)", value: $store.customLevel.samples, in: 8...128, step: 8)
                Stepper("반복 \(store.customLevel.passes)", value: $store.customLevel.passes, in: 1...6)
                Stepper("경계 보정 \(store.customLevel.boundary)", value: $store.customLevel.boundary, in: 0...16)
            }
        } header: {
            Text("정확도 설정")
        } footer: {
            Text("높을수록 정확하지만 동기화가 오래 걸립니다. 안정된 네트워크(와이파이)에서 측정할수록 정확합니다.")
        }
    }

    // MARK: - 타이머

    private var timerSection: some View {
        Section("타이머") {
            Picker("카운트다운 소리", selection: $store.beepMode) {
                ForEach(BeepMode.allCases) { Text($0.title).tag($0) }
            }
            Toggle("정각 10초 전 빨간 표시", isOn: $store.redBeforeMinute)
            Toggle(isOn: $store.autoClosePiP) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("지정한 시각에 PiP 자동으로 닫기")
                    Text(String(format: "서버시간 %02d:%02d:%02d · 팝업 타이머 시작 옵션에서 변경",
                                store.autoCloseSecondOfDay / 3600, (store.autoCloseSecondOfDay % 3600) / 60,
                                store.autoCloseSecondOfDay % 60))
                        .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Picker("화면 모드", selection: $store.colorMode) {
                ForEach(ColorMode.allCases) { Text($0.title).tag($0) }
            }
        }
    }

    private var displaySection: some View {
        Section {
            Picker("앱 시계 소수점", selection: $store.appDigits) {
                Text("1초").tag(0)
                Text("0.1초").tag(1)
                Text("0.01초").tag(2)
                Text("0.001초").tag(3)
            }
            Picker("PiP 소수점", selection: $store.pipDigits) {
                Text("1초").tag(0)
                Text("0.1초").tag(1)
                Text("0.01초").tag(2)
                Text("0.001초").tag(3)
            }
            NavigationLink {
                PiPSizeView()
            } label: {
                HStack {
                    Text("PiP 크기")
                    Spacer()
                    Text(store.pipStyle.title).foregroundStyle(.secondary)
                }
            }
            Toggle("PiP 에 날짜 표시", isOn: $store.showDateInPiP)
            Toggle("PiP 에 사이트 이름 표시", isOn: $store.showHostInPiP)
        } header: {
            Text("표시")
        } footer: {
            Text("날짜를 끄면 PiP 글자가 커집니다. 소리는 '정각 3초 전부터 짧게, 정각에 길게' 울립니다.")
        }
    }

    private var scheduleSection: some View {
        Section {
            Picker("일정 전 자동 재측정", selection: $store.autoResyncMinutes) {
                Text("끄기").tag(0)
                ForEach([2, 3, 4, 5, 10], id: \.self) { Text("\($0)분 전").tag($0) }
            }
        } header: {
            Text("일정")
        } footer: {
            Text("앱이나 PiP 가 켜져 있으면 일정 시각 전에 자동으로 다시 측정합니다. 일정 5분·1분 전에는 알림도 보냅니다.")
        }
    }
}
