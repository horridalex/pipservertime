import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ClockStore

    private let digitOptions: [(Int, String)] = [(0, "1초"), (1, "0.1초"), (2, "0.01초"), (3, "0.001초")]

    var body: some View {
        CardScreen {
            SectionHeader(text: "시간 계산")
            SettingsCard {
                reactionRow
                StepRow(title: "PiP 내에서 보정 시 단위",
                        value: String(format: "%.2f초", Double(store.pipStepMs) / 1000),
                        minus: { store.pipStepMs = max(10, store.pipStepMs - 10) },
                        plus: { store.pipStepMs = min(500, store.pipStepMs + 10) })
                if store.pipAdjustMs != 0 {
                    RowLabel(title: "PiP 에서 조정한 값") {
                        Text("\(store.pipAdjustMs)ms").font(.body.monospacedDigit()).foregroundStyle(Theme.accentText)
                        Button("초기화") { store.pipAdjustMs = 0 }
                            .buttonStyle(.plain).foregroundStyle(Theme.secondary)
                    }
                }
                CardNote(text: "연습 모드에서 측정한 내 반응속도만큼 시계를 앞당겨 두면 제때 누르기 쉬워요. PiP 창의 ◀◀ / ▶▶ 버튼으로도 위 단위만큼 늦추거나 앞당길 수 있어요.")
            }

            SettingsCard {
                ToggleRow(title: "네트워크 딜레이를 시계에 반영하기",
                          subtitle: store.result?.recommendedLead.map { String(format: "현재 약 %.3f초", $0) } ?? "직접 측정 후 계산돼요",
                          isOn: $store.applyLead)
                CardNote(text: "동기화한 사이트까지 신호가 가는 시간(왕복 지연의 절반)만큼 시계를 앞당겨 보여줘요. 해외 사이트처럼 서버가 멀리 있을 때 유용해요.")
            }

            SectionHeader(text: "측정")
            SettingsCard {
                NavRow(title: "정확도 설정", value: store.accuracyPreset.title) { AccuracyView() }
                RowDivider()
                MenuRow(title: "오픈 전 자동 재측정", selection: $store.autoResyncSeconds,
                        options: ClockStore.autoResyncOptions)
                CardNote(text: "일정이 있으면 오픈 전 정한 시점에 한 번 자동으로 다시 측정해요. 앱이나 PiP 가 켜져 있어야 해요.")
            }

            SectionHeader(text: "타이머")
            SettingsCard {
                MenuRow(title: "카운트다운 소리", selection: $store.beepMode,
                        options: BeepMode.allCases.map { ($0, $0.title) })
                RowDivider()
                ToggleRow(title: "정각 10초 전 빨간 표시", isOn: $store.redBeforeMinute)

                RowDivider()
                MenuRow(title: "화면 모드", selection: $store.colorMode,
                        options: ColorMode.allCases.map { ($0, $0.title) })
            }

            SectionHeader(text: "표시")
            SettingsCard {
                NavRow(title: "PiP 크기", value: store.pipStyle.title) { PiPSizeView() }
                RowDivider()
                MenuRow(title: "앱 시계 소수점", selection: $store.appDigits, options: digitOptions)
                RowDivider()
                MenuRow(title: "PiP 소수점", selection: $store.pipDigits, options: digitOptions)
                RowDivider()
                ToggleRow(title: "PiP 에 날짜 표시", subtitle: "끄면 PiP 글자가 커져요", isOn: $store.showDateInPiP)
                RowDivider()
                ToggleRow(title: "PiP 에 사이트 이름 표시", isOn: $store.showHostInPiP)
            }
        }
        .navigationTitle("설정")
        .navigationBarTitleDisplayMode(.large)
    }

    private var reactionRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("반응속도를 시계에 반영하기").foregroundStyle(Theme.ink)
                Spacer()
                Text("\(store.reactionAdjustMs)ms").font(.body.monospaced().weight(.semibold)).foregroundStyle(Theme.accentText)
            }
            HStack(spacing: 12) {
                Button { store.reactionAdjustMs = max(-300, store.reactionAdjustMs - 10) } label: {
                    Image(systemName: "minus").font(.body.weight(.bold)).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain).foregroundStyle(Theme.accentText).accessibilityLabel("반응속도 줄이기")
                Slider(value: Binding(get: { Double(store.reactionAdjustMs) },
                                      set: { store.reactionAdjustMs = Int(($0 / 10).rounded()) * 10 }),
                       in: -300...300)
                    .tint(Theme.accent)
                Button { store.reactionAdjustMs = min(300, store.reactionAdjustMs + 10) } label: {
                    Image(systemName: "plus").font(.body.weight(.bold)).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain).foregroundStyle(Theme.accentText).accessibilityLabel("반응속도 늘리기")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }
}

/// 정확도 설정
struct AccuracyView: View {
    @EnvironmentObject private var store: ClockStore

    var body: some View {
        CardScreen {
            SettingsCard {
                ForEach(AccuracyPreset.allCases) { p in
                    if p != AccuracyPreset.allCases.first { RowDivider() }
                    let l = p.level ?? store.customLevel
                    CheckRow(title: p.title,
                             subtitle: "\(p.subtitle) (샘플: \(l.samples)/반복: \(l.passes)/경계보정: \(l.boundary))",
                             checked: store.accuracyPreset == p) { store.accuracyPreset = p }
                }
            }
            .padding(.top, 8)

            if store.accuracyPreset == .custom {
                SectionHeader(text: "커스텀")
                SettingsCard {
                    StepRow(title: "샘플", value: "\(store.customLevel.samples)",
                            minus: { store.customLevel.samples = max(8, store.customLevel.samples - 8) },
                            plus: { store.customLevel.samples = min(128, store.customLevel.samples + 8) })
                    RowDivider()
                    StepRow(title: "반복", value: "\(store.customLevel.passes)",
                            minus: { store.customLevel.passes = max(1, store.customLevel.passes - 1) },
                            plus: { store.customLevel.passes = min(6, store.customLevel.passes + 1) })
                    RowDivider()
                    StepRow(title: "경계 보정", value: "\(store.customLevel.boundary)",
                            minus: { store.customLevel.boundary = max(0, store.customLevel.boundary - 1) },
                            plus: { store.customLevel.boundary = min(16, store.customLevel.boundary + 1) })
                }
            }

            Text("높을수록 정확하지만 동기화가 오래 걸려요. 안정된 네트워크(와이파이)에서 측정할수록 정확해요.")
                .font(.footnote).foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
        }
        .navigationTitle("정확도 설정")
        .navigationBarTitleDisplayMode(.inline)
    }
}
