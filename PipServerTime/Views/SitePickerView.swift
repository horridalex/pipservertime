import SwiftUI

struct SitePickerView: View {
    @EnvironmentObject private var store: ClockStore
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var showSave = false
    @State private var saveName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("예매창 주소 붙여넣기 (예: https://…)", text: $typed)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit(useTyped)
                    Button("이 주소로 측정", action: useTyped)
                        .disabled(URLNormalizer.normalize(typed) == nil)
                    Button("현재 사이트를 내 사이트로 저장") {
                        saveName = store.siteName
                        showSave = true
                    }
                } header: {
                    Text("직접 입력")
                } footer: {
                    Text("가장 정확한 건 실제 예매·신청 버튼을 눌렀을 때 열리는 창의 주소입니다.")
                }

                if !store.customPresets.isEmpty {
                    Section("내 사이트") {
                        ForEach(store.customPresets) { p in row(p) }
                            .onDelete { idx in
                                for i in idx { store.deletePreset(store.customPresets[i]) }
                            }
                    }
                }

                Section("기본 사이트") {
                    ForEach(ClockStore.builtInPresets) { p in row(p) }
                }

                Section {
                    Picker("측정 방식", selection: $store.source) {
                        ForEach(SyncSource.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("측정 방식")
                } footer: {
                    Text("자동: 직접 측정 → 실패하면 네이비즘. 네이비즘은 사이트와의 차이를 초 단위로만 반영하고 −900ms 보정이 들어가 있어 실제보다 수백 ms 늦을 수 있습니다.")
                }
            }
            .paperBackground()
            .navigationTitle("사이트 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } }
            }
            .onAppear { typed = store.urlText }
            .alert("내 사이트로 저장", isPresented: $showSave) {
                TextField("이름", text: $saveName)
                Button("저장") { store.saveCurrentAsPreset(name: saveName) }
                Button("취소", role: .cancel) {}
            } message: {
                Text(store.urlText)
            }
        }
    }

    private func row(_ p: Preset) -> some View {
        Button {
            store.select(p)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).foregroundStyle(.primary)
                    Text(URL(string: p.url)?.host ?? p.url).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if p.url == store.urlText { Image(systemName: "checkmark").foregroundStyle(Theme.accentText) }
            }
        }
    }

    private func useTyped() {
        guard URLNormalizer.normalize(typed) != nil else { return }
        store.useTypedURL(typed)
        dismiss()
    }
}
