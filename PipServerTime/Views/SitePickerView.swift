import SwiftUI

struct SitePickerView: View {
    @EnvironmentObject private var store: ClockStore
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var showSave = false
    @State private var saveName = ""

    var body: some View {
        NavigationStack {
            CardScreen {
                SectionHeader(text: "직접 입력")
                SettingsCard {
                    HStack(spacing: 10) {
                        Image(systemName: "link").foregroundStyle(Theme.secondary)
                        TextField("예매창 주소 붙여넣기", text: $typed)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit(useTyped)
                            .foregroundStyle(Theme.ink)
                    }
                    .padding(.horizontal, 20).frame(minHeight: 58)
                    RowDivider()
                    Button(action: useTyped) {
                        RowLabel(title: "이 주소로 측정") {
                            Image(systemName: "arrow.right.circle.fill").font(.title3).foregroundStyle(Theme.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(URLNormalizer.normalize(typed) == nil)
                    .opacity(URLNormalizer.normalize(typed) == nil ? 0.5 : 1)
                    RowDivider()
                    Button {
                        saveName = store.siteName
                        showSave = true
                    } label: {
                        RowLabel(title: "현재 사이트를 내 사이트로 저장") {
                            Image(systemName: "star").foregroundStyle(Theme.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    CardNote(text: "가장 정확한 건 실제 예매·신청 버튼을 눌렀을 때 열리는 창의 주소예요.")
                }

                if !store.customPresets.isEmpty {
                    SectionHeader(text: "내 사이트")
                    SettingsCard {
                        ForEach(store.customPresets) { p in
                            if p.id != store.customPresets.first?.id { RowDivider() }
                            row(p)
                                .contextMenu {
                                    Button("삭제", role: .destructive) { store.deletePreset(p) }
                                }
                        }
                    }
                    Text("길게 눌러 삭제할 수 있어요.")
                        .font(.caption).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                }

                SectionHeader(text: "기본 사이트")
                SettingsCard {
                    ForEach(ClockStore.builtInPresets) { p in
                        if p.id != ClockStore.builtInPresets.first?.id { RowDivider() }
                        row(p)
                    }
                }

            }
            .navigationTitle("사이트 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }.foregroundStyle(Theme.ink)
                }
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
            RowLabel(title: p.name, subtitle: URL(string: p.url)?.host ?? p.url) {
                Image(systemName: "checkmark").font(.body.weight(.bold))
                    .foregroundStyle(Theme.accentText)
                    .opacity(p.url == store.urlText ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
    }

    private func useTyped() {
        guard URLNormalizer.normalize(typed) != nil else { return }
        store.useTypedURL(typed)
        dismiss()
    }
}
