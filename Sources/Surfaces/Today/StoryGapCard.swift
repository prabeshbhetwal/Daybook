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
                GapStretchList(anatomy: anatomy, stretches: anatomy.stretches)
                Text("Not assumed to be work or rest.")
                    .font(Tokens.Typography.body).foregroundStyle(StoryStyle.supportingInk)
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
                    .font(Tokens.Typography.body).foregroundStyle(StoryStyle.supportingInk)
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
                    .font(Tokens.Typography.caption).foregroundStyle(StoryStyle.supportingInk)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
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
            Text(event.title)
            if let back { Text("· " + back).foregroundStyle(StoryStyle.supportingInk) }
        }
        .font(Tokens.Typography.body)
        .padding(.vertical, 10.zoomed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Tokens.timeOfDayOnly(event.at)), \(event.title)"
                            + (back.map { ". \($0)" } ?? ""))
    }

    private var back: String? { event.returnLine(resumed: resumed) }
}

extension MachineEvent {
    /// When Daybook was back after this event, as a pin or a run card says it.
    func returnLine(resumed: Date?) -> String? {
        guard let resumed else { return nil }
        return isQuickReturn(at: resumed) ? "Daybook back within a minute"
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
        case .lock, .unlock: return StoryPin(symbol: "lock", tint: StoryStyle.supportingInk)
        case .displaySleep, .displayWake: return StoryPin(symbol: "display", tint: StoryStyle.supportingInk)
        case .userSwitchedOut, .userSwitchedIn: return StoryPin(symbol: "person.2", tint: StoryStyle.supportingInk)
        case .systemSleep: return StoryPin(symbol: "moon", tint: StoryStyle.supportingInk)
        case .wake: return StoryPin(symbol: "sun.max", tint: StoryStyle.supportingInk)
        case .logOut, .restart, .shutDown, .restartOrShutDown, .powerOffUnknown, .macStarted:
            return StoryPin(symbol: "power", tint: StoryStyle.supportingInk)
        case .macOSUpdated: return StoryPin(symbol: "arrow.down.circle", tint: StoryStyle.supportingInk)
        case .quit, .updateRelaunch, .quitByApp, .logOutCancelled, .restartCancelled, .shutDownCancelled,
             .daybookStarted:
            return StoryPin(symbol: "smallcircle.filled.circle", tint: StoryStyle.supportingInk)
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
