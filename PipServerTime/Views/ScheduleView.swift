import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var store: ClockStore
    @State private var editing: ScheduledEvent?

    var body: some View {
        List {
            if store.events.isEmpty {
                Text("등록된 일정이 없어요. 티켓 오픈, 수강신청 시각을 등록하면 카운트다운·알림·자동 재측정을 해 줍니다.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.events) { e in
                Button { editing = e } label: {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let remain = e.date.timeIntervalSince(ctx.date.addingTimeInterval(store.clock.config.offset))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(e.name).font(.headline).foregroundStyle(.primary)
                            Text(e.date.formatted(date: .abbreviated, time: .standard))
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(remain > 0 ? ClockFormat.countdown(remain) + " 남음" : "지남")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(remain > 0 ? Theme.accentText : Color.secondary)
                            if let u = e.url, !u.isEmpty {
                                Text(URL(string: u)?.host ?? u).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .onDelete { idx in
                for i in idx { store.deleteEvent(store.events[i]) }
            }
        }
        .paperBackground()
        .navigationTitle("일정")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = ScheduledEvent(name: "", date: defaultDate(), url: store.urlText)
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { e in
            EventEditor(event: e, isNew: !store.events.contains { $0.id == e.id })
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
                DatePicker("오픈 시각 (서버시간)", selection: Binding(
                    get: { event.date },
                    set: { event.date = Self.zeroSeconds($0) }
                ))
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
                Section {
                    Text("사이트를 지정하면 일정 직전 자동 재측정 때 그 사이트로 측정합니다. 시각은 초 단위를 00초로 맞춥니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .paperBackground()
            .navigationTitle(isNew ? "일정 추가" : "일정 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
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
