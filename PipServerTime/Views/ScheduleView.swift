import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var store: ClockStore
    @State private var editing: ScheduledEvent?

    var body: some View {
        CardScreen {
            if store.events.isEmpty {
                SettingsCard {
                    RowLabel(title: "등록된 일정이 없어요",
                             subtitle: "티켓 오픈, 수강신청 시각을 등록하면 카운트다운·알림·자동 재측정을 해 줘요") {
                        EmptyView()
                    }
                }
                .padding(.top, 8)
            } else {
                SettingsCard {
                    ForEach(store.events) { e in
                        if e.id != store.events.first?.id { RowDivider() }
                        Button { editing = e } label: { eventRow(e) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("삭제", role: .destructive) { store.deleteEvent(e) }
                            }
                    }
                }
                .padding(.top, 8)
                Text("눌러서 수정, 길게 눌러 삭제할 수 있어요.")
                    .font(.caption).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
            }

            Button {
                editing = ScheduledEvent(name: "", date: defaultDate(), url: store.urlText)
            } label: {
                Label("일정 추가", systemImage: "plus")
            }
            .buttonStyle(CapsuleButtonStyle(filled: true))
            .padding(.top, 8)
        }
        .navigationTitle("일정")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { e in
            EventEditor(event: e, isNew: !store.events.contains { $0.id == e.id })
        }
    }

    private func eventRow(_ e: ScheduledEvent) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let remain = e.date.timeIntervalSince(ctx.date.addingTimeInterval(store.clock.config.offset))
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(e.name).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(e.date.formatted(date: .abbreviated, time: .standard))
                        .font(.footnote).foregroundStyle(Theme.secondary)
                    if let u = e.url, !u.isEmpty {
                        Text(URL(string: u)?.host ?? u).font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
                Spacer()
                Text(remain > 0 ? ClockFormat.countdown(remain) : "지남")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(remain > 0 ? Theme.accentText : Theme.secondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .contentShape(Rectangle())
        }
    }

    /// 다음 정시 (정시는 시간대와 무관하게 3600초 단위)
    private func defaultDate() -> Date {
        Date(timeIntervalSince1970: (floor(Date().timeIntervalSince1970 / 3600) + 1) * 3600)
    }
}

struct EventEditor: View {
    @EnvironmentObject private var store: ClockStore
    @Environment(\.dismiss) private var dismiss
    @State var event: ScheduledEvent
    let isNew: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("이름 (예: 콘서트 티켓 오픈)", text: $event.name)
                    .listRowBackground(Theme.card)
                DatePicker("오픈 시각 (서버시간)", selection: Binding(
                    get: { event.date },
                    set: { event.date = Self.zeroSeconds($0) }
                ))
                .listRowBackground(Theme.card)
                Picker("사이트", selection: Binding(
                    get: { event.url ?? "" },
                    set: { event.url = $0.isEmpty ? nil : $0 }
                )) {
                    Text("지정 안 함").tag("")
                    if let u = event.url, !u.isEmpty, !store.presets.contains(where: { $0.url == u }) {
                        Text(URL(string: u)?.host ?? u).tag(u)
                    }
                    ForEach(store.presets) { p in Text(p.name).tag(p.url) }
                }
                .tint(Theme.secondary)
                .listRowBackground(Theme.card)
                Section {
                    Text("사이트를 지정하면 일정 직전 자동 재측정 때 그 사이트로 측정합니다. 시각은 초 단위를 00초로 맞춥니다.")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                        .listRowBackground(Theme.card)
                }
            }
            .paperBackground()
            .navigationTitle(isNew ? "일정 추가" : "일정 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() }.foregroundStyle(Theme.secondary) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        if event.name.trimmingCharacters(in: .whitespaces).isEmpty { event.name = "오픈" }
                        if isNew { store.addEvent(event) } else { store.updateEvent(event) }
                        dismiss()
                    }
                }
            }
        }
    }

    static func zeroSeconds(_ d: Date) -> Date {
        let t = floor(d.timeIntervalSince1970 / 60) * 60
        return Date(timeIntervalSince1970: t)
    }
}
