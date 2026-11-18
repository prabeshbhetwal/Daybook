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
                .frame(width: min(760.zoomed, windowSize.width - 64.zoomed),
                       height: min(760.zoomed, windowSize.height - 64.zoomed))
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

/// The full account of a session: what it was, each stretch, every app, the
/// recorded activity minute by minute, each note under its stretch. Nothing here is
/// summarised away — that is the point of asking for it.
struct SessionReportView: View {
    let report: SessionReport
    /// The Recorded activity rows and their column widths, worked out once
    /// with the report rather than with each draw of it.
    let activityList: ReportActivityList
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
                WorkTypeMark(workType: session.workType, size: 44.zoomed)
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text(report.title)
                        .font(Tokens.Typography.title)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: Tokens.Space.s) {
                        // An unnamed session is titled by its category already.
                        if !session.name.isEmpty {
                            Text(session.workType.displayName)
                                .font(Tokens.Typography.caption)
                                .padding(.horizontal, 7.zoomed).padding(.vertical, 2.zoomed)
                                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Tokens.Radius.swatch))
                                .foregroundStyle(StoryStyle.workTypeInk(session.workType))
                        }
                        Text(report.whenText)
                            .font(Tokens.Typography.body)
                            .foregroundStyle(StoryStyle.supportingInk)
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
            if let origin = report.origin { OriginMark(text: origin, stacked: true) }
            if let text = report.detail.text {
                Text(text)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(StoryStyle.supportingInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let line = report.contradiction {
                Text(line)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(StoryStyle.supportingInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = report.detail.reportNote {
                Text(note)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(StoryStyle.supportingInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let power = report.power {
                VStack(alignment: .leading, spacing: 2.zoomed) {
                    Label(power.headline, systemImage: power.symbolName)
                        .font(Tokens.Typography.body)
                    if let detail = power.detail {
                        Text(detail)
                            .font(Tokens.Typography.body)
                            .foregroundStyle(StoryStyle.supportingInk)
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
                .foregroundStyle(StoryStyle.supportingInk)
        }
        .accessibilityElement(children: .combine)
    }

    private var stretches: some View {
        section("Stretches") {
            ForEach(Array(report.stretches.enumerated()), id: \.element.id) { index, stretch in
                VStack(alignment: .leading, spacing: 3.zoomed) {
                    HStack(spacing: Tokens.Space.s) {
                        Text("\(index + 1)")
                            .font(Tokens.Typography.caption)
                            .frame(width: 20.zoomed, height: 20.zoomed)
                            .background(tint.opacity(0.14), in: Circle())
                            .foregroundStyle(StoryStyle.workTypeInk(session.workType))
                        Text(report.stretchWhen(stretch))
                            .font(Tokens.Typography.body)
                        Spacer(minLength: Tokens.Space.s)
                        Text(durations: Tokens.preciseDuration(stretch.worked))
                            .font(Tokens.Typography.body.monospacedDigit())
                            .foregroundStyle(StoryStyle.supportingInk)
                    }
                    if let note = stretch.note {
                        Text(note)
                            .font(Tokens.Typography.body)
                            .foregroundStyle(StoryStyle.supportingInk)
                            .padding(.leading, 28.zoomed)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Stretch \(index + 1), \(report.stretchWhen(stretch, joiner: "to")), "
                                    + Tokens.spent(stretch.worked)
                                    + (stretch.note.map { ". Note: \($0)" } ?? ""))
            }
        }
    }

    private var apps: some View {
        section("Every app in this session") {
            ForEach(Array(report.apps.enumerated()), id: \.element.id) { _, app in
                StoryAppRow(app: app)
            }
        }
    }

    private var activity: some View {
        section("Recorded activity") {
            SessionPhaseStrip.ifShown(report.detail.phases, lasted: report.detail.activity.elapsed, tint: tint)
            StoryShapeChart(activity: report.detail.activity, runsListedBelow: true)
            // Latest first: the reader opens a report to see where it ended.
            // The chart above stays left-to-right in time.
            // Lazy: a session of hundreds of visits builds the rows in view.
            // The report scrolls in its card, so nothing pins.
            LazyVStack(spacing: 0) {
                ForEach(Array(activityList.rows.enumerated()), id: \.element.id) { index, model in
                    ReportActivityRow(model: model, widths: activityList.widths).equatable()
                    if index < activityList.rows.count - 1 { Divider() }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            // DESIGN.md: section headers are headings.
            Text(title)
                .font(Tokens.Typography.heading)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}
