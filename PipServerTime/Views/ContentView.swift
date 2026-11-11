import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ClockStore
    @FocusState private var urlFocused: Bool

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

                Section("서버시간 가져올 사이트") {
                    TextField("예) https://app.catchtable.co.kr", text: $store.urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($urlFocused)
                        .submitLabel(.go)
                        .onSubmit { store.sync() }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(ClockStore.presets, id: \.url) { preset in
                                Button(preset.name) {
                                    store.urlText = preset.url
                                    store.sync()
                                }
                                .buttonStyle(.bordered)
                                .font(.footnote)
                            }
                        }
                    }

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
                }

                Section("동기화 상태") {
                    if let r = store.result {
                        LabeledContent("사이트", value: r.host)
                        LabeledContent("방식", value: r.source == .navyism ? "네이비즘" : "앱 직접 측정")
                        LabeledContent("기기 대비", value: formatOffset(r.offset))
                        if let acc = r.accuracy {
                            LabeledContent("추정 오차", value: String(format: "±%.0f ms", acc * 1000))
                        }
                        LabeledContent("동기화 시각", value: r.syncedAt.formatted(date: .omitted, time: .standard))
                    } else {
                        Text("아직 동기화하지 않았습니다. 지금은 기기 시간을 표시합니다.")
                            .foregroundStyle(.secondary)
                    }
                    if let err = store.lastError {
                        Text(err).font(.footnote).foregroundStyle(.orange)
                    }
                }

                Section("표시") {
                    Toggle("0.1초 단위 표시", isOn: $store.showTenths)
                    Toggle("PiP 에 사이트 이름 표시", isOn: $store.showHostInPiP)
                }
            }
            .navigationTitle("서버시간 PiP")
        }
        .task { if store.result == nil { store.sync() } }
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
