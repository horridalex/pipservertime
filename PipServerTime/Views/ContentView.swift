import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ClockStore
    @EnvironmentObject private var network: NetworkMonitor
    @State private var showSitePicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    siteRow
                    clockCard
                    if store.result != nil && !store.isSyncing { evidenceCard }
                    scheduleCard
                    if let err = store.lastError {
                        Text(err).font(.footnote).foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
            .safeAreaInset(edge: .bottom) { bottomButtons }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    NavigationLink { ScheduleView() } label: { Label("일정", systemImage: "calendar") }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    NavigationLink { PracticeView() } label: { Label("연습", systemImage: "flag.checkered") }
                    NavigationLink { SettingsView() } label: { Label("설정", systemImage: "gearshape") }
                }
            }
            .navigationTitle("서버시간")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSitePicker) { SitePickerView() }
        }
        .task { if store.result == nil && !store.isSyncing { store.sync() } }
    }

    // MARK: - 사이트

    private var siteRow: some View {
        Button { showSitePicker = true } label: {
            HStack {
                Circle().fill(dotColor).frame(width: 10, height: 10)
                Text(store.siteName).font(.title3.bold()).lineLimit(1)
                Spacer()
                Label("변경", systemImage: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }

    private var dotColor: Color {
        if store.isSyncing { return .blue }
        if let c = store.result?.confidence { return c.color }
        return store.result == nil ? .gray : .green
    }

    // MARK: - 서버 시계

    private var clockCard: some View {
        Card {
            HStack {
                Text("서버 시계").font(.headline).foregroundStyle(.secondary)
                Spacer()
                if store.isSyncing {
                    Badge(text: "측정 중")
                } else if abs(store.totalCorrection) >= 0.0005 {
                    Badge(text: "보정 " + Fmt.signedSec(store.totalCorrection), tint: .secondary)
                }
            }

            // PiP 원본 (PiP 를 켜려면 화면에 있어야 함)
            ClockPreview(pip: store.pip)
                .aspectRatio(6, contentMode: .fit)

            if store.isSyncing {
                measuringBody
            } else {
                clockBody
            }
        }
    }

    private var measuringBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            SampleBars(samples: store.liveSamples, planned: store.plannedSamples)
            HStack {
                Text(store.statusMessage ?? "측정 중").font(.subheadline.weight(.semibold))
                Spacer()
                Text("샘플 \(store.liveSamples.count)/\(store.plannedSamples)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Divider()
            Text("응답이 빨리 온 샘플(파랑)만 골라 계산합니다. 정확도가 높을수록 오래 걸리니 끝날 때까지 화면을 그대로 두세요.")
                .font(.footnote).foregroundStyle(.secondary)
            cellularWarning
        }
    }

    @ViewBuilder
    private var cellularWarning: some View {
        if network.isCellular {
            Label {
                Text("데이터 네트워크 사용 중\n기지국 상황, 이동 상황, 인원 혼잡도에 따라 오차가 증가할 수 있습니다.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.footnote).foregroundStyle(.orange)
        }
    }

    private var clockBody: some View {
        TimelineView(.animation(minimumInterval: 0.01)) { ctx in
            let cfg = store.clock.config
            let server = ctx.date.addingTimeInterval(cfg.offset)
            VStack(alignment: .leading, spacing: 12) {
                Text(ClockFormat.time(server, digits: store.appDigits))
                    .font(.system(size: 60, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(highlight(server) ? Color.red : Color.primary)
                Divider()
                HStack {
                    Text("내 폰 시계").foregroundStyle(.secondary)
                    Spacer()
                    Text(ClockFormat.time(ctx.date, digits: store.appDigits))
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if let r = store.result {
                    differenceBox(r.offset)
                }
            }
        }
    }

    private func highlight(_ server: Date) -> Bool {
        guard store.redBeforeMinute else { return false }
        let s = server.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
        return s >= 60 - DisplayClock.redWindow
    }

    private func differenceBox(_ offset: TimeInterval) -> some View {
        let sec = String(format: "%.3f초", abs(offset))
        let ahead = offset >= 0
        return VStack(alignment: .leading, spacing: 4) {
            (Text("서버가 내 폰보다 ") + Text(sec).foregroundColor(.blue) + Text(ahead ? " 빠릅니다" : " 느립니다"))
                .font(.headline)
            Text(ahead ? "폰 시계를 보고 누르면 그만큼 늦게 도착해요" : "폰 시계를 보고 누르면 그만큼 일찍 도착해요")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.blue.opacity(0.1)))
    }

    // MARK: - 측정 근거

    private var evidenceCard: some View {
        Card {
            HStack {
                Text("측정 근거").font(.headline)
                Spacer()
                NavigationLink { MeasurementDetailView() } label: {
                    HStack(spacing: 2) { Text("자세히"); Image(systemName: "chevron.right") }
                        .font(.subheadline.weight(.semibold))
                }
            }
            if let r = store.result {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    HStack(alignment: .top) {
                        stat("추정 오차", r.projectedAccuracy(at: ctx.date).map { "±" + Fmt.ms($0) } ?? "네이비즘")
                        stat("사용 샘플", r.samples.isEmpty ? "—" : "\(r.usedCount)/\(r.samples.count)")
                        stat("마지막 측정", Fmt.ago(r.syncedAt, now: ctx.date),
                             warn: ctx.date.timeIntervalSince(r.syncedAt) > 600)
                    }
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(warn ? Color.orange : Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 일정

    private var scheduleCard: some View {
        NavigationLink { ScheduleView() } label: {
            Card {
                Text("내 일정").font(.headline)
                if let e = store.nextEvent {
                    TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                        let remain = e.date.timeIntervalSince(ctx.date.addingTimeInterval(store.clock.config.offset))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(e.name).font(.title3.bold())
                            Text(e.date.formatted(date: .abbreviated, time: .standard))
                                .font(.footnote).foregroundStyle(.secondary)
                            Text(remain > 0 ? ClockFormat.countdown(remain) + " 남음" : "시작됨")
                                .font(.title2.monospacedDigit().weight(.semibold))
                                .foregroundStyle(remain > 0 && remain < 60 ? Color.red : Color.blue)
                        }
                    }
                } else {
                    Text("다가오는 일정이 없어요").font(.title3.bold())
                    Text("일정 보기 · 추가").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 하단 버튼

    private var bottomButtons: some View {
        HStack(spacing: 12) {
            if store.isSyncing {
                Button { store.cancelSync() } label: {
                    Text("취소").bold().frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
            } else {
                Button { store.sync() } label: {
                    Label("다시 측정", systemImage: "arrow.triangle.2.circlepath")
                        .bold().frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
            }
            PiPButton(pip: store.pip)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

struct PiPButton: View {
    @ObservedObject var pip: PiPClockController

    var body: some View {
        Button { pip.toggle() } label: {
            Label(pip.isActive ? "팝업 닫기" : "팝업 타이머",
                  systemImage: pip.isActive ? "pip.exit" : "pip.enter")
                .bold().frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!pip.isPossible && !pip.isActive)
    }
}
