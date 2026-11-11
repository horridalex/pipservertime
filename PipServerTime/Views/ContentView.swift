import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ClockStore
    @EnvironmentObject private var network: NetworkMonitor
    @State private var showSitePicker = false
    @State private var showFocus = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    clockCard
                    if store.result != nil && !store.isSyncing {
                        statTiles
                    }
                    scheduleCard
                    if !store.isSyncing, let lead = store.result?.recommendedLead {
                        leadHint(lead)
                    }
                    if let err = store.lastError {
                        Text(err).font(.footnote).foregroundStyle(Theme.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
            .background(Theme.bg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { bottomButtons }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSitePicker) { SitePickerView() }
            .fullScreenCover(isPresented: $showFocus) { FocusClockView() }
        }
        .task { if store.result == nil && !store.isSyncing { store.sync() } }
    }

    // MARK: - 상단

    private var header: some View {
        HStack {
            Text("서버시간").font(.system(size: 24, weight: .heavy)).foregroundStyle(Theme.ink)
            Spacer()
            HStack(spacing: 8) {
                NavigationLink { ScheduleView() } label: { RoundIconLabel(systemName: "calendar") }
                    .accessibilityLabel("일정")
                NavigationLink { PracticeView() } label: { RoundIconLabel(systemName: "stopwatch") }
                    .accessibilityLabel("연습")
                NavigationLink { SettingsView() } label: { RoundIconLabel(systemName: "gearshape") }
                    .accessibilityLabel("설정")
            }
        }
        .padding(.top, 8)
    }

    // MARK: - 시계 카드 (잉크)

    private var clockCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { showSitePicker = true } label: {
                    HStack(spacing: 8) {
                        Circle().fill(dotColor).frame(width: 8, height: 8)
                        Text(store.siteName).font(.subheadline.weight(.bold)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption.weight(.bold))
                    }
                    .foregroundStyle(Theme.clockText)
                    .padding(.horizontal, 14).frame(height: 36)
                    .background(Capsule().fill(Theme.clockPill))
                }
                .accessibilityLabel("사이트 변경: \(store.siteName)")
                Spacer()
                if store.isSyncing {
                    pill("측정 중", fill: Theme.accent, text: Theme.clockCard)
                } else {
                    if abs(store.totalCorrection) >= 0.0005 {
                        pill("보정 " + Fmt.signedSec(store.totalCorrection), fill: Theme.clockPill, text: Theme.clockDim)
                    }
                    Button { showFocus = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.clockText)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Theme.clockPill))
                    }
                    .accessibilityLabel("타이머 집중 화면")
                }
            }

            if store.isSyncing {
                measuringBody
            } else {
                clockBody
            }

            // PiP 원본 (PiP 를 켜려면 화면에 있어야 함)
            VStack(alignment: .leading, spacing: 6) {
                Text("PiP 미리보기 · \(store.pipStyle.title)").font(.caption).foregroundStyle(Theme.clockDim)
                ClockPreview(pip: store.pip)
                    .aspectRatio(store.pipStyle.aspect, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.clockCardLine))
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.clockCard))
    }

    private func pill(_ text: String, fill: Color, text color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(fill))
    }

    private var dotColor: Color {
        if store.isSyncing { return Theme.clockDim }
        guard let r = store.result else { return Theme.clockDim }
        switch r.confidence {
        case .low: return Theme.warning
        case .medium: return Color(UIColor(hex: 0xFAB005))
        default: return Theme.accent
        }
    }

    private var clockBody: some View {
        TimelineView(.animation(minimumInterval: 0.01)) { ctx in
            let cfg = store.clock.config
            let server = ctx.date.addingTimeInterval(cfg.offset)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ClockFormat.dateOnly(server)).font(.footnote).foregroundStyle(Theme.clockDim)
                    clockText(server)
                }
                Rectangle().fill(Theme.clockCardLine).frame(height: 1)
                HStack {
                    Text("내 폰 ") + Text(ClockFormat.time(ctx.date, digits: store.appDigits)).monospacedDigit()
                    Spacer()
                    if let r = store.result { diffPill(r.offset) }
                }
                .font(.footnote)
                .foregroundStyle(Theme.clockDim)
            }
        }
    }

    /// 큰 시계: 소수점 아래만 민트
    private func clockText(_ server: Date) -> some View {
        let full = ClockFormat.time(server, digits: store.appDigits)
        let parts = full.split(separator: ".", maxSplits: 1).map(String.init)
        let red = highlight(server)
        return (Text(parts[0]).foregroundColor(red ? Theme.alert : Theme.clockText)
                + Text(parts.count > 1 ? "." + parts[1] : "").foregroundColor(red ? Theme.alert : Theme.accent))
            .font(.system(size: 56, weight: .heavy).monospacedDigit())
            .minimumScaleFactor(0.4)
            .lineLimit(1)
    }

    private func diffPill(_ offset: TimeInterval) -> some View {
        let ms = Int((abs(offset) * 1000).rounded())
        let text = ms == 0 ? "폰과 같음" : String(format: "서버 %.3f초 %@", abs(offset), offset >= 0 ? "빠름" : "느림")
        return pill(text, fill: Theme.accent, text: Theme.clockCard)
    }

    private func highlight(_ server: Date) -> Bool {
        guard store.redBeforeMinute else { return false }
        let s = server.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
        return s >= 60 - DisplayClock.redWindow
    }

    private var measuringBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("--:--:--.---")
                .font(.system(size: 56, weight: .heavy).monospacedDigit())
                .foregroundStyle(Theme.clockCardLine)
                .minimumScaleFactor(0.4).lineLimit(1)
            SampleBars(samples: store.liveSamples, planned: store.plannedSamples,
                       usedColor: Theme.accent, excludedColor: Color(UIColor(hex: 0x4A4D57)),
                       pendingColor: Theme.clockCardLine)
            HStack {
                Text(store.statusMessage ?? "측정 중").font(.subheadline.weight(.semibold))
                Spacer()
                Text("샘플 \(store.liveSamples.count)/\(store.plannedSamples)").font(.subheadline.monospacedDigit())
            }
            .foregroundStyle(Theme.clockText)
            Text("응답이 빨리 온 샘플(민트)만 골라 계산합니다. 정확도가 높을수록 오래 걸리니 끝날 때까지 화면을 그대로 두세요.")
                .font(.footnote).foregroundStyle(Theme.clockDim)
            if network.isCellular {
                Label("데이터 네트워크 사용 중 · 기지국·이동·혼잡도에 따라 오차가 커질 수 있습니다", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(Color(UIColor(hex: 0xFFA94D)))
            }
        }
    }

    // MARK: - 측정 근거 타일

    private var statTiles: some View {
        NavigationLink { MeasurementDetailView() } label: {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                if let r = store.result {
                    HStack(spacing: 8) {
                        tile("추정 오차", r.projectedAccuracy(at: ctx.date).map { String(format: "±%.0f", $0 * 1000) } ?? "—",
                             unit: r.accuracy == nil ? nil : "ms")
                        tile("사용 샘플", r.samples.isEmpty ? "—" : "\(r.usedCount)", unit: r.samples.isEmpty ? nil : "/\(r.samples.count)")
                        tile("측정", Fmt.ago(r.syncedAt, now: ctx.date), unit: nil,
                             color: ctx.date.timeIntervalSince(r.syncedAt) > 600 ? Theme.warning : (r.confidence?.color ?? Theme.ink))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("측정 근거 자세히 보기")
    }

    private func tile(_ title: String, _ value: String, unit: String?, color: Color = Theme.ink) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Theme.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value).font(.title3.weight(.heavy).monospacedDigit()).foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let unit { Text(unit).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.border))
    }

    // MARK: - 일정

    private var scheduleCard: some View {
        NavigationLink { ScheduleView() } label: {
            Card {
                if let e = store.nextEvent {
                    TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                        let remain = e.date.timeIntervalSince(ctx.date.addingTimeInterval(store.clock.config.offset))
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(e.name).font(.headline.weight(.heavy)).lineLimit(1)
                                Spacer()
                                Text(e.date.formatted(date: .omitted, time: .standard))
                                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary)
                            }
                            ProgressView(value: progress(remain))
                                .tint(remain > 0 && remain < 60 ? Theme.alert : Theme.ink)
                            HStack {
                                Text(store.autoResyncMinutes > 0 ? "\(store.autoResyncMinutes)분 전 자동 재측정" : "자동 재측정 꺼짐")
                                    .foregroundStyle(Theme.secondary)
                                Spacer()
                                Text(remain > 0 ? ClockFormat.countdown(remain) + " 남음" : "시작됨")
                                    .fontWeight(.heavy).monospacedDigit()
                                    .foregroundStyle(remain > 0 && remain < 60 ? Theme.alert : Theme.ink)
                            }
                            .font(.footnote)
                        }
                    }
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("다가오는 일정이 없어요").font(.headline.weight(.heavy))
                            Text("오픈 시각을 등록하면 카운트다운·알림·자동 재측정").font(.footnote).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Theme.accentText)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// 1시간 전부터 채워지는 진행 막대
    private func progress(_ remain: TimeInterval) -> Double {
        min(1, max(0, 1 - remain / 3600))
    }

    private func leadHint(_ lead: TimeInterval) -> some View {
        (Text("요청이 서버까지 가는 데 약 ") + Text(String(format: "%.0fms", lead * 1000)).bold()
         + Text(store.applyLead ? ". 시계에 이미 반영돼 있어요." : ". 이만큼 먼저 누르면 정각에 도착해요."))
            .font(.footnote)
            .foregroundStyle(Theme.accentSoftText)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.accentSoft))
    }

    // MARK: - 하단 버튼

    private var bottomButtons: some View {
        HStack(spacing: 10) {
            if store.isSyncing {
                Button("취소") { store.cancelSync() }
                    .buttonStyle(CapsuleButtonStyle(filled: false))
            } else {
                Button { store.sync() } label: {
                    Label("다시 측정", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(CapsuleButtonStyle(filled: false))
            }
            PiPButton(pip: store.pip)
                .layoutPriority(1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Theme.bg.opacity(0.95).ignoresSafeArea(edges: .bottom))
    }
}

struct PiPButton: View {
    @ObservedObject var pip: PiPClockController
    @State private var showOptions = false

    var body: some View {
        Button {
            if pip.isActive { pip.toggle() } else { showOptions = true }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: pip.isActive ? "pip.exit" : "pip.enter")
                    .foregroundStyle(Theme.accent)
                Text(pip.isActive ? "팝업 닫기" : "팝업 타이머")
            }
        }
        .buttonStyle(CapsuleButtonStyle(filled: true))
        .disabled(!pip.isPossible && !pip.isActive)
        .opacity(!pip.isPossible && !pip.isActive ? 0.5 : 1)
        .sheet(isPresented: $showOptions) { PiPStartSheet() }
    }
}
