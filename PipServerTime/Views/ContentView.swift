import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ClockStore
    @FocusState private var urlFocused: Bool
    @State private var showSavePreset = false
    @State private var newPresetName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ClockPreview(pip: store.pip)
                        .listRowInsets(EdgeInsets())
                    PiPButton(pip: store.pip)
                } footer: {
                    Text("PiP 를 켠 뒤 홈으로 나가면 다른 앱 위에 시계가 떠 있습니다. 홈으로 나갈 때 자동으로 켜지기도 합니다.")
                }

                Section {
                    TextField("예) https://app.catchtable.co.kr", text: $store.urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($urlFocused)
                        .submitLabel(.go)
                        .onSubmit { store.sync() }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(store.presets) { preset in
                                Button {
                                    store.urlText = preset.url
                                    store.sync()
                                } label: {
                                    Label(preset.name, systemImage: preset.isCustom ? "star.fill" : "globe")
                                        .labelStyle(.titleOnly)
                                }
                                .buttonStyle(.bordered)
                                .tint(preset.isCustom ? .yellow : nil)
                                .font(.footnote)
                                .contextMenu {
                                    if preset.isCustom {
                                        Button("삭제", role: .destructive) { store.deletePreset(preset) }
                                    }
                                }
                            }
                        }
                    }

                    Button("현재 주소를 내 사이트로 저장") {
                        newPresetName = ""
                        showSavePreset = true
                    }
                    .font(.footnote)

                    Picker("방식", selection: $store.source) {
                        ForEach(SyncSource.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Button {
                        urlFocused = false
                        store.sync()
                    } label: {
                        HStack {
                            if store.isSyncing { ProgressView().padding(.trailing, 4) }
                            Text(store.isSyncing ? (store.statusMessage ?? "동기화 중…") : "서버시간 동기화")
                                .bold()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isSyncing)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("서버시간 가져올 사이트")
                } footer: {
                    Text("가장 정확한 건 실제 예매·신청 버튼을 눌렀을 때 열리는 창(예매창)의 주소입니다. 예매창 주소를 복사해 넣고 '내 사이트로 저장'하세요. 저장한 사이트는 길게 눌러 삭제할 수 있습니다.")
                }

                Section("동기화 상태") {
                    if let r = store.result {
                        LabeledContent("사이트", value: r.host)
                        LabeledContent("방식", value: r.source == .navyism ? "네이비즘 계산값" : "앱 직접 측정")
                        LabeledContent("기기 대비", value: formatOffset(r.offset))
                        if let acc = r.accuracy {
                            LabeledContent("추정 오차", value: String(format: "±%.0f ms", acc * 1000))
                        }
                        if let c = r.confidence {
                            LabeledContent("신뢰도") {
                                Text(c.title).bold().foregroundStyle(color(for: c))
                            }
                        }
                        if let a = r.samplesAgreed, let t = r.samplesTotal {
                            LabeledContent("샘플 합의", value: "\(a) / \(t)")
                        }
                        if let rtt = r.rttMedian {
                            LabeledContent("왕복 지연", value: String(format: "%.0f ms", rtt * 1000))
                        }
                        TimelineView(.periodic(from: .now, by: 30)) { ctx in
                            let mins = Int(ctx.date.timeIntervalSince(r.syncedAt) / 60)
                            LabeledContent("측정 시각") {
                                Text(r.syncedAt.formatted(date: .omitted, time: .standard)
                                     + (mins >= 1 ? " (\(mins)분 전)" : ""))
                                    .foregroundStyle(mins >= 10 ? Color.orange : Color.secondary)
                            }
                        }
                        if r.source == .navyism {
                            Text("네이비즘은 사이트와의 차이를 초 단위로만 반영하고 −900ms 보정이 들어가 있어, 실제 서버시간보다 수백 ms 늦을 수 있습니다.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("아직 동기화하지 않았습니다. 지금은 기기 시간을 표시합니다.")
                            .foregroundStyle(.secondary)
                    }
                    if let err = store.lastError {
                        Text(err).font(.footnote).foregroundStyle(.orange)
                    }
                }

                Section {
                    if let lead = store.result?.recommendedLead {
                        LabeledContent("권장 선행 클릭", value: String(format: "약 %.0f ms 먼저", lead * 1000))
                        Toggle("시계에 선행 시간 반영", isOn: $store.applyLead)
                    } else {
                        Text("직접 측정으로 동기화하면 내 통신 지연을 바탕으로 계산됩니다.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("선행 클릭")
                } footer: {
                    Text("버튼을 누른 요청이 서버까지 가는 데 걸리는 시간(왕복 지연의 절반)에 측정 오차를 더한 참고값입니다. '시계에 반영'을 켜면 그만큼 앞당겨 표시하므로, 시계가 정각이 될 때 누르면 됩니다. 실제 예매 서버 상황에 따라 달라질 수 있습니다.")
                }

                Section("표시") {
                    Toggle("0.1초 단위 표시", isOn: $store.showTenths)
                    Toggle("PiP 에 사이트 이름 표시", isOn: $store.showHostInPiP)
                }
            }
            .navigationTitle("서버시간 PiP")
        }
        .task { if store.result == nil { store.sync() } }
        .alert("내 사이트로 저장", isPresented: $showSavePreset) {
            TextField("이름 (예: 아이유 콘서트 예매창)", text: $newPresetName)
            Button("저장") { store.saveCurrentAsPreset(name: newPresetName) }
            Button("취소", role: .cancel) {}
        } message: {
            Text(store.urlText)
        }
    }

    private func color(for c: SyncConfidence) -> Color {
        switch c {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .orange
        }
    }

    private func formatOffset(_ o: TimeInterval) -> String {
        let ms = Int((o * 1000).rounded())
        if ms == 0 { return "기기와 동일" }
        return ms > 0 ? "서버가 \(ms) ms 빠름" : "서버가 \(-ms) ms 느림"
    }
}

/// 앱 안의 시계 = PiP 원본 레이어 (레이어가 화면에 있어야 PiP 시작 가능)
struct ClockPreview: UIViewRepresentable {
    let pip: PiPClockController

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
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

struct PiPButton: View {
    @ObservedObject var pip: PiPClockController

    var body: some View {
        Button {
            pip.toggle()
        } label: {
            Label(pip.isActive ? "PiP 끄기" : "PiP 켜기",
                  systemImage: pip.isActive ? "pip.exit" : "pip.enter")
                .frame(maxWidth: .infinity)
        }
        .disabled(!pip.isPossible && !pip.isActive)
    }
}
