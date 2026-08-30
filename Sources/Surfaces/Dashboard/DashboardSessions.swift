import SwiftUI

/// The selected day's focus sessions as rows, with the rests between them
/// inline — the card the dashboard was missing. Hover a row to frame it on
/// the timeline; click to narrow the page to it.
struct SessionsCard: View {
    let entries: [DayEntry]
    var selected: DaySession?
    /// The live session whose clock is paused for Watching. It remains a focus
    /// session row, but its status must not resemble productive running time.
    var watchingSessionID: UUID?
    let onHover: (DaySession?) -> Void
    let onSelect: (DaySession) -> Void
    @StateObject private var hover = HoverBox()
    /// Sessions whose stretches are unfolded. Local: it is a reading aid.
    @StateObject private var unfolded: SetBox

    /// `unfoldAll` opens every multi-stretch session at once — for the harness,
    /// which cannot click the disclosure.
    init(entries: [DayEntry], selected: DaySession?, watchingSessionID: UUID? = nil,
         unfoldAll: Bool = false,
         onHover: @escaping (DaySession?) -> Void, onSelect: @escaping (DaySession) -> Void) {
        self.entries = entries
        self.selected = selected
        self.watchingSessionID = watchingSessionID
        self.onHover = onHover
        self.onSelect = onSelect
        let open = unfoldAll
            ? Set(entries.compactMap { entry -> UUID? in
                if case .session(let s) = entry, s.stretches > 1 { return s.id }
                return nil
            })
            : []
        _unfolded = StateObject(wrappedValue: SetBox(ids: open))
    }

    private var sessions: [DaySession] {
        entries.compactMap { if case .session(let s) = $0 { return s } else { return nil } }
    }
    private var rests: Int {
        entries.filter { if case .rest = $0 { return true } else { return false } }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(title: "Sessions", trailing: trailing)
                .padding(.bottom, Tokens.Space.xs)
            if entries.isEmpty {
                Text("No focus sessions this day.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, Tokens.Space.s)
            }
            ForEach(entries) { entry in
                switch entry {
                case .session(let session):
                    row(session)
                    if unfoldable(session), unfolded.ids.contains(session.id) {
                        stretchList(session)
                    }
                case .rest(let rest):
                    // A rest inside a session's span belongs to that session's
                    // unfolded list, not to the day's top level.
                    if !sessions.contains(where: { $0.start < rest.start && rest.end <= $0.end }) {
                        restRow(rest)
                    }
                }
            }
        }
    }

    /// The stretches of one session in order, with the rests that fell between
    /// them — the session seen from inside.
    private func stretchList(_ session: DaySession) -> some View {
        // Stretches and the rests recorded inside the session, in time order —
        // a rest can sit between two stretches or inside one (a film watched
        // mid-session pauses the clock without ending the stretch).
        var items: [(start: Date, id: String, time: String, label: String, isRest: Bool)] = []
        for (index, span) in session.spans.enumerated() {
            items.append((span.start, "s\(index)", Tokens.timeRange(span.start, span.end),
                          "stretch \(index + 1) · \(Tokens.preciseDuration(span.duration))", false))
        }
        for rest in insideRests(session) {
            items.append((rest.start, rest.id.uuidString, Tokens.timeRange(rest.start, rest.end),
                          "\(rest.name) · \(Tokens.preciseDuration(rest.length))", true))
        }
        let lines = items.sorted { $0.start < $1.start }
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(lines, id: \.id) { line in
                HStack(spacing: Tokens.Space.s) {
                    Text(line.time)
                        .font(Tokens.Typography.metadata.monospacedDigit())
                        .foregroundStyle(line.isRest ? .tertiary : .secondary)
                        .frame(width: 150, alignment: .leading)
                    if line.isRest {
                        Rectangle().fill(Tokens.Colour.line).frame(height: 1)
                    }
                    Text(line.label)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(line.isRest ? .tertiary : .secondary)
                        .fixedSize()
                    if line.isRest {
                        Rectangle().fill(Tokens.Colour.line).frame(height: 1)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.leading, Tokens.Space.l + Tokens.Space.s)
        .padding(.trailing, Tokens.Space.s)
        .padding(.bottom, Tokens.Space.xs)
    }

    private var trailing: String? {
        guard !sessions.isEmpty else { return nil }
        // A thread resumed after other work makes two rows of one session; the
        // count is of sessions, so it agrees with the KPI.
        let count = Set(sessions.map(\.threadID)).count
        var parts = [count == 1 ? "1 session" : "\(count) sessions"]
        if rests > 0 { parts.append(rests == 1 ? "1 break" : "\(rests) breaks") }
        return parts.joined(separator: " · ")
    }

    private func row(_ session: DaySession) -> some View {
        let isSelected = selected?.id == session.id
        let dimmed = selected != nil && !isSelected
        let hovered = hover.id == session.id.uuidString
        return Button { onSelect(session) } label: {
            HStack(alignment: .center, spacing: Tokens.Space.m) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Tokens.Palette.workType(session.workType))
                    .frame(width: 4, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Tokens.timeRange(session.start, session.end))
                        .font(Tokens.Typography.rowTitle.weight(.medium).monospacedDigit())
                    if unfoldable(session) {
                        // A disclosure for the stretches; it must not select.
                        Button {
                            if unfolded.ids.contains(session.id) { unfolded.ids.remove(session.id) }
                            else { unfolded.ids.insert(session.id) }
                        } label: {
                            HStack(spacing: 3) {
                                Text(stretchLine(session))
                                Image(systemName: unfolded.ids.contains(session.id)
                                      ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help(unfolded.ids.contains(session.id) ? "Hide the stretches" : "Show the stretches and breaks inside")
                    } else {
                        Text(stretchLine(session))
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 150, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Tokens.Space.xs) {
                        Text(session.name.isEmpty ? session.workType.displayName : session.name)
                            .font(Tokens.Typography.rowTitle.weight(.medium))
                            .lineLimit(1)
                        if watchingSessionID == session.id {
                            Text("Watching · focus paused")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Tokens.Colour.attention)
                        } else if session.isRunning {
                            Text("active")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Tokens.Colour.focus)
                        }
                    }
                    Text(session.workType.displayName)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(Tokens.preciseDuration(session.worked))
                    .font(Tokens.Typography.rowTitle.weight(.medium).monospacedDigit())
                    .frame(width: 60, alignment: .trailing)
            }
            .padding(.horizontal, Tokens.Space.s)
            .padding(.vertical, Tokens.Space.s)
            .background(hovered && !isSelected ? Tokens.Colour.hover : Color.clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isSelected ? 0.9 : 0), lineWidth: 1.5))
            .opacity(dimmed ? 0.45 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.nested))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hover.id = inside ? session.id.uuidString : nil
            onHover(inside ? session : nil)
        }
        .help(isSelected ? "Click again to show the whole day"
                         : "Click to narrow the page to this session")
        .accessibilityLabel("\(Tokens.timeRange(session.start, session.end)), "
                            + "\(session.name.isEmpty ? session.workType.displayName : session.name), "
                            + Tokens.spent(session.worked))
    }

    /// `4 stretches · 2 breaks` — the breaks being the rests *recorded* inside
    /// the session, the same count the header, the summary and the unfolded
    /// list use. A gap the user answered "I was away" to is a gap, not a break.
    private func stretchLine(_ session: DaySession) -> String {
        let stretches = session.stretches == 1 ? "1 stretch" : "\(session.stretches) stretches"
        let breaksInside = insideRests(session).count
        return breaksInside == 0 ? stretches
            : "\(stretches) · \(breaksInside == 1 ? "1 break" : "\(breaksInside) breaks")"
    }

    /// A row unfolds when there is something inside it to show.
    private func unfoldable(_ session: DaySession) -> Bool {
        session.stretches > 1 || !insideRests(session).isEmpty
    }

    /// The rests that fell inside this session's span.
    private func insideRests(_ session: DaySession) -> [RestEntry] {
        entries.compactMap { entry -> RestEntry? in
            if case .rest(let rest) = entry, session.start < rest.start, rest.end <= session.end { return rest }
            return nil
        }
    }

    /// A rest between sessions, drawn as a labelled rule so the day's shape
    /// reads top to bottom without a second column.
    private func restRow(_ rest: RestEntry) -> some View {
        HStack(spacing: Tokens.Space.s) {
            Text(Tokens.timeRange(rest.start, rest.end))
                .font(Tokens.Typography.metadata.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 150, alignment: .leading)
            Rectangle().fill(Tokens.Colour.line).frame(height: 1)
            Label("\(rest.name) · \(Tokens.preciseDuration(rest.length))",
                  systemImage: "pause.fill")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(Tokens.Palette.workType(.breakTime))
                .fixedSize()
            Rectangle().fill(Tokens.Colour.line).frame(height: 1)
        }
        .padding(.horizontal, Tokens.Space.s)
        .padding(.vertical, 2)
        .accessibilityLabel("\(rest.name), \(Tokens.spent(rest.length))")
    }
}

/// A set of ids a view can toggle. `@State` is unavailable on this toolchain.
final class SetBox: ObservableObject {
    @Published var ids: Set<UUID>
    init(ids: Set<UUID> = []) { self.ids = ids }
}
