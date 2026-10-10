import SwiftUI

/// A hole in the day's recording as a card. Folded, it names the most telling
/// cause, the time and a small bar of what the Mac did; unfolded, the bar
/// gains its moments and each stretch gets a line. A hole no event names has
/// nothing to unfold and stays a single card.
struct StoryGapCard: View {
    let span: DateInterval
    let reason: StoryGapReason
    let anatomy: GapAnatomy
    let power: PowerContextSummary?
    let isOpen: Bool
    let onToggle: () -> Void
    @Environment(\.focusInterfaceDensity) private var density

    /// Only a hole an event names unfolds, a rule Expand all can apply
    /// without reading the log.
    static func unfolds(_ reason: StoryGapReason) -> Bool {
        if case .machine = reason { return true }
        return false
    }

    /// Even a piece of a hole an away answer split keeps its name and so
    /// unfolds, though its own stretch may be nothing recorded.
    private var canUnfold: Bool { Self.unfolds(reason) }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            if canUnfold {
                Button(action: onToggle) { header }
                    .buttonStyle(StoryPressStyle())
                    .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
                    .accessibilityHint(isOpen ? "Fold what the Mac did" : "Show what the Mac did in this time")
            } else {
                header
            }
            if canUnfold && isOpen {
                GapTrack(span: span, anatomy: anatomy)
                Rectangle().fill(StoryStyle.line).frame(height: 1)
                stretchList
                Text("Not assumed to be work or rest.")
                    .font(Tokens.Typography.body).foregroundStyle(.secondary)
            }
        }
        .padding(StoryStyle.entryInsets(for: density))
        .background(StoryStyle.well.opacity(0.6), in: RoundedRectangle(cornerRadius: StoryStyle.entryRadius))
        .help(reason.explanation ?? "")
    }

    private var header: some View {
        HStack(spacing: Tokens.Space.m) {
            VStack(alignment: .leading, spacing: 2.zoomed) {
                Text(reason.title).font(Tokens.Typography.label)
                // Nothing was recorded but the Mac's power, which is the one
                // thing the card can honestly add to the time.
                Text(Tokens.timeRange(span.start, span.end) + (power.map { " · \($0.headline)" } ?? ""))
                    .font(Tokens.Typography.body).foregroundStyle(.secondary)
            }
            Spacer(minLength: Tokens.Space.s)
            if canUnfold && !isOpen {
                GapBar(span: span, anatomy: anatomy)
                    .frame(width: 72.zoomed, height: 5.zoomed)
            }
            Text(durations: Tokens.duration(span.duration))
                .font(Tokens.Typography.body.monospacedDigit())
            if canUnfold {
                Image(systemName: "chevron.right")
                    .font(Tokens.Typography.caption).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var stretchList: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Tokens.Space.m,
             verticalSpacing: Tokens.Space.s) {
            ForEach(Array(anatomy.stretches.enumerated()), id: \.offset) { _, stretch in
                GridRow {
                    GapSwatch(state: stretch.state)
                        .frame(width: 10.zoomed, height: 10.zoomed)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                    Text(Tokens.timeRange(stretch.span.start, stretch.span.end))
                        .font(Tokens.Typography.body.monospacedDigit()).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2.zoomed) {
                        Text(stretch.title).font(Tokens.Typography.body)
                        if let detail = detail(of: stretch) {
                            Text(detail).font(Tokens.Typography.body).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(durations: Tokens.preciseDuration(stretch.span.duration))
                        .font(Tokens.Typography.body.monospacedDigit())
                        .gridColumnAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// What a stretch adds beyond its name and time.
    private func detail(of stretch: GapAnatomy.Stretch) -> String? {
        switch stretch.state {
        case .locked:
            guard let dark = stretch.displayOff else { return nil }
            return dark == stretch.span ? "Display off throughout"
                : "Display off \(Tokens.timeRange(dark.start, dark.end))"
        case .uncertain:
            let found = stretch.foundAt.map { "; found when Daybook opened at \(Tokens.timeOfDayOnly($0))" }
            return "Some time in this window" + (found ?? "")
        case .unexplained:
            let inside = anatomy.starts.filter { stretch.span.start < $0.at && $0.at < stretch.span.end }
            guard !inside.isEmpty else { return nil }
            return inside.map { "\($0.kind.title) at \(Tokens.timeOfDayOnly($0.at))" }.joined(separator: ", ")
        case .asleep, .off:
            return nil
        }
    }

    private var spoken: String {
        var parts = ["\(reason.title), \(Tokens.timeRange(span.start, span.end))."]
        if let explanation = reason.explanation { parts.append(explanation) }
        if canUnfold {
            parts.append(anatomy.stretches.map {
                "\($0.title) \(Tokens.timeRange($0.span.start, $0.span.end))"
            }.joined(separator: "; ") + ".")
        }
        if let power { parts.append("Power: \(power.headline).") }
        parts.append("This interval is not assumed to be work or rest.")
        return parts.joined(separator: " ")
    }
}

/// A restart, quit or crash that left no hole: one line on the rule, and
/// when Daybook was back.
struct StoryMachinePin: View {
    let event: MachineEvent
    let resumed: Date?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.xs) {
            Text(event.kind.title)
            if let back { Text("· " + back).foregroundStyle(.secondary) }
        }
        .font(Tokens.Typography.body)
        .padding(.vertical, 10.zoomed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Tokens.timeOfDayOnly(event.at)), \(event.kind.title)"
                            + (back.map { ". \($0)" } ?? ""))
    }

    private var back: String? {
        guard let resumed else { return nil }
        return event.isQuickReturn(at: resumed) ? "Daybook back within a minute"
            : "Daybook back at \(Tokens.timeOfDayOnly(resumed))"
    }
}

/// The glyph a row wears on the story's rule in place of its dot.
struct StoryPin {
    let symbol: String
    let tint: Color
}

extension MachineEvent.Kind {
    var pin: StoryPin {
        switch self {
        case .lock, .unlock: return StoryPin(symbol: "lock", tint: .secondary)
        case .displaySleep, .displayWake: return StoryPin(symbol: "display", tint: .secondary)
        case .userSwitchedOut, .userSwitchedIn: return StoryPin(symbol: "person.2", tint: .secondary)
        case .systemSleep: return StoryPin(symbol: "moon", tint: .secondary)
        case .wake: return StoryPin(symbol: "sun.max", tint: .secondary)
        case .logOut, .restart, .shutDown, .powerOffUnknown, .macStarted:
            return StoryPin(symbol: "power", tint: .secondary)
        case .quit, .updateRelaunch, .daybookStarted:
            return StoryPin(symbol: "smallcircle.filled.circle", tint: .secondary)
        // A run that ended without saying so is the one kind the rule flags.
        case .crashed, .forceQuit, .powerLost, .kernelPanic:
            return StoryPin(symbol: "exclamationmark.triangle", tint: StoryStyle.attentionInk)
        }
    }
}

extension StoryGapReason {
    /// A hole an event names wears that event's glyph; the rest keep a dot.
    var pin: StoryPin? {
        if case .machine(let kind) = self { return kind.pin }
        return nil
    }
}
