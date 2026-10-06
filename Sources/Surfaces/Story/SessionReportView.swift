import SwiftUI
import AppKit

/// Set by the main window so an entry card can ask for the full report of a
/// session. Nil where there is no window to draw it in.
private struct OpenSessionReportKey: EnvironmentKey {
    static let defaultValue: ((DaySession) -> Void)? = nil
}

extension EnvironmentValues {
    var openSessionReport: ((DaySession) -> Void)? {
        get { self[OpenSessionReportKey.self] }
        set { self[OpenSessionReportKey.self] = newValue }
    }
}

/// Everything the report says about one session, gathered once so the view
/// reads from plain values and the numbers can be checked without a window.
struct SessionReport {
    struct Stretch: Identifiable {
        let id: UUID
        let start: Date
        let end: Date
        let worked: TimeInterval
        let note: String?
    }

    let session: DaySession
    let detail: StorySessionDetail
    let stretches: [Stretch]
    let power: PowerContextSummary?
    /// Each visit's power reading, by interval id, only where it changed.
    let powerChanges: [String: PowerReading]
    let appColourIndices: [String: Int]

    var title: String { session.workType.sessionTitle(named: session.name) }
    var apps: [AppRank] { detail.apps }
    /// Every recorded visit and every gap, in order.
    var intervals: [RecordedActivity.Interval] { detail.activity.intervals }
    var visitCount: Int { intervals.filter { !$0.isGap }.count }

    /// When the session ran, with its day, for the header: a report opened
    /// from History is for a past day, and clock times alone do not say which.
    /// A session across midnight names both days.
    var whenText: String { when(joiner: "–") }
    /// The same line for VoiceOver, which would read the dash as a symbol.
    var whenSpoken: String { when(joiner: "to") }

    private func when(joiner: String) -> String {
        guard session.isRunning else {
            return DateFormats.datedClockRange(session.start, session.end, joiner: joiner)
        }
        // A session is clipped to its day; its stretches are not, and the
        // earliest says when it really began.
        let began = min(session.start, stretches.map(\.start).min() ?? session.start)
        return "Running since \(DateFormats.datedClockTime(began))"
    }

    /// A stretch's times. They carry their day when the stretch crosses
    /// midnight or lies on another day than the one the header gives, since
    /// the session is clipped to its day and its stretches are not.
    func stretchWhen(_ stretch: Stretch, joiner: String = "–") -> String {
        let calendar = Calendar.current
        return calendar.isDate(stretch.start, inSameDayAs: stretch.end)
            && calendar.isDate(stretch.start, inSameDayAs: session.start)
            ? "\(DateFormats.clockTime(stretch.start)) \(joiner) \(DateFormats.clockTime(stretch.end))"
            : DateFormats.datedClockRange(stretch.start, stretch.end, joiner: joiner)
    }

    /// The power state a visit ended on, when it differs from the visit
    /// before. Nil for a gap, an unchanged reading, or before any reading.
    func power(for interval: RecordedActivity.Interval) -> PowerReading? {
        powerChanges[interval.id]
    }

    static func make(for session: DaySession, store: SessionStore) -> SessionReport {
        // The session's own day, not whichever day the Story happens to be
        // on: a report opened from Insights or History is for a past day.
        let detail = store.storySessionDetail(session, on: session.start)
        let ids = Set(session.recordIDs)
        let stretches = store.engine.archive.records
            .filter { ids.contains($0.id) }
            .sorted { $0.start < $1.start }
            .map { record in
                Stretch(id: record.id, start: record.start, end: record.end, worked: record.workSeconds,
                        note: store.sessionMetadata(for: record.id)?.note)
            }
        let interval = DateInterval(start: session.start, end: max(session.start, session.end))
        let power = session.recordIDs.isEmpty ? nil
            : store.powerSummary(for: session.recordIDs, interval: interval)
        return SessionReport(session: session, detail: detail, stretches: stretches,
                             power: power,
                             powerChanges: PowerReading.changes(
                                 across: detail.activity.intervals,
                                 in: store.powerObservations(for: session.recordIDs)),
                             appColourIndices: colourIndices(apps: detail.apps,
                                                             dayIndices: store.storyAppColourIndices))
    }

    /// The day's palette names its busiest apps; anything below that shares
    /// "Other" grey, which in a full list put two neighbours in one colour.
    /// Apps with a day colour keep it; the rest take the unused colours in
    /// rank order, and only past the sixth does grey return.
    static func colourIndices(apps: [AppRank], dayIndices: [String: Int]) -> [String: Int] {
        let distinct = Tokens.Palette.distinctAppColourCount
        var result: [String: Int] = [:]
        var used = Set<Int>()
        for app in apps {
            if let index = dayIndices[app.bundleID], index < distinct {
                result[app.bundleID] = index
                used.insert(index)
            }
        }
        for app in apps where result[app.bundleID] == nil {
            if let free = (0..<distinct).first(where: { !used.contains($0) }) {
                result[app.bundleID] = free
                used.insert(free)
            } else {
                result[app.bundleID] = distinct
            }
        }
        return result
    }
}

/// The report as a card over the story: dimmed canvas behind, Escape or a
/// click outside to leave. Drawn in the window rather than as a sheet so it
/// can be dismissed the way a reader expects and animates with the rest.
struct SessionReportOverlay: View {
    @ObservedObject var store: SessionStore
    let session: DaySession
    let windowSize: CGSize
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var escape = EscapeKeyMonitor()

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
                .transition(.opacity)
                .accessibilityHidden(true)
            SessionReportCard(store: store, session: session, onClose: onClose)
                .frame(width: min(760, windowSize.width - 64),
                       height: min(760, windowSize.height - 64))
                .transition(Tokens.Motion.transition(
                    .opacity.combined(with: .scale(scale: 0.96, anchor: .center)),
                    reduceMotion: reduceMotion))
        }
        .onAppear {
            escape.install(onClose)
            // The card draws over the story without moving VoiceOver's
            // cursor, so say that it arrived.
            Announcement.post("\(session.workType.sessionTitle(named: session.name)) report")
        }
        .onDisappear { escape.remove() }
    }
}

/// Escape closes the report whichever control has focus. `onExitCommand`
/// only fires for the focused view, and a report has nothing focused.
final class EscapeKeyMonitor: ObservableObject {
    private var monitor: Any?

    func install(_ action: @escaping () -> Void) {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }
            action()
            return nil
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit { remove() }
}

struct SessionReportCard: View {
    @ObservedObject var store: SessionStore
    let session: DaySession
    let onClose: () -> Void

    var body: some View {
        let report = SessionReport.make(for: session, store: store)
        StorySheet(title: "Session report", onClose: onClose) {
            ScrollView {
                SessionReportView(report: report)
                    .padding(Tokens.Space.xl)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: StoryStyle.tileRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: StoryStyle.tileRadius, style: .continuous)
            .strokeBorder(StoryStyle.line))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
        .accessibilityAddTraits(.isModal)
    }
}

/// The full account of a session: what it was, each stretch, every app, the
/// recorded activity minute by minute, each note under its stretch. Nothing here is
/// summarised away — that is the point of asking for it.
struct SessionReportView: View {
    let report: SessionReport
    @Environment(\.focusInterfaceDensity) private var density

    private var session: DaySession { report.session }
    private var tint: Color { Tokens.Palette.workType(session.workType) }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            header
            if !report.stretches.isEmpty { stretches }
            if !report.apps.isEmpty { apps }
            if report.detail.activity.hasRecordedActivity { activity }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(alignment: .top, spacing: Tokens.Space.m) {
                WorkTypeMark(workType: session.workType, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.title)
                        .font(Tokens.Typography.title)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: Tokens.Space.s) {
                        // An unnamed session is titled by its category already.
                        if !session.name.isEmpty {
                            Text(session.workType.displayName)
                                .font(Tokens.Typography.caption)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                                .foregroundStyle(StoryStyle.workTypeInk(session.workType))
                        }
                        Text(report.whenText)
                            .font(Tokens.Typography.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(report.whenSpoken)
                    }
                }
                Spacer(minLength: Tokens.Space.m)
            }
            HStack(spacing: Tokens.Space.xl) {
                figure(Tokens.preciseDuration(session.worked), "focused")
                figure(Tokens.preciseDuration(report.detail.activity.coverage), "recorded app use")
                figure("\(session.stretches)", session.stretches == 1 ? "stretch" : "stretches")
                figure("\(report.apps.count)", report.apps.count == 1 ? "app" : "apps")
                figure("\(report.visitCount)", report.visitCount == 1 ? "app visit" : "app visits")
            }
            if let text = report.detail.text {
                Text(text)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = report.detail.reportNote {
                Text(note)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let power = report.power {
                VStack(alignment: .leading, spacing: 2) {
                    Label(power.headline, systemImage: power.symbolName)
                        .font(Tokens.Typography.body)
                    if let detail = power.detail {
                        Text(detail)
                            .font(Tokens.Typography.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Power during this session. \(power.headline). \(power.detail ?? "")")
            }
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(durations: value)
                .font(Tokens.Typography.heading.monospacedDigit())
            Text(label)
                .font(Tokens.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var stretches: some View {
        section("Stretches") {
            ForEach(Array(report.stretches.enumerated()), id: \.element.id) { index, stretch in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Tokens.Space.s) {
                        Text("\(index + 1)")
                            .font(Tokens.Typography.caption)
                            .frame(width: 20, height: 20)
                            .background(tint.opacity(0.14), in: Circle())
                            .foregroundStyle(StoryStyle.workTypeInk(session.workType))
                        Text(report.stretchWhen(stretch))
                            .font(Tokens.Typography.body)
                        Spacer(minLength: Tokens.Space.s)
                        Text(durations: Tokens.preciseDuration(stretch.worked))
                            .font(Tokens.Typography.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if let note = stretch.note {
                        Text(note)
                            .font(Tokens.Typography.body)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 28)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(minHeight: 28)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Stretch \(index + 1), \(report.stretchWhen(stretch, joiner: "to")), "
                                    + Tokens.spent(stretch.worked)
                                    + (stretch.note.map { ". Note: \($0)" } ?? ""))
            }
        }
    }

    private var apps: some View {
        section("Every app in this session") {
            ForEach(Array(report.apps.enumerated()), id: \.element.id) { index, app in
                StoryAppRow(app: app, rank: report.appColourIndices[app.bundleID] ?? index)
            }
        }
    }

    private var activity: some View {
        section("Recorded activity") {
            StoryShapeChart(activity: report.detail.activity, appColourIndices: report.appColourIndices,
                            runsListedBelow: true)
            // Latest first: the reader opens a report to see where it ended.
            // The chart above stays left-to-right in time.
            VStack(spacing: 0) {
                ForEach(Array(report.intervals.reversed().enumerated()), id: \.element.id) { index, interval in
                    ReportActivityRow(interval: interval,
                                      colourRank: interval.bundleID.flatMap { report.appColourIndices[$0] }
                                          ?? Tokens.Palette.distinctAppColourCount,
                                      power: report.power(for: interval))
                    if index < report.intervals.count - 1 { Divider() }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text(title)
                .font(Tokens.Typography.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}
