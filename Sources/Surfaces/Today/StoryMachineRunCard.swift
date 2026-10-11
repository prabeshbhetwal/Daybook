import SwiftUI

/// Back-to-back restarts, quits or crashes as one card, drawn like a gap
/// card. Folded, it names what happened, how often and across what time;
/// unfolded, each event gets a line with when Daybook was back.
struct StoryMachineRunCard: View {
    let run: StoryMachineRun
    let isOpen: Bool
    let onToggle: () -> Void
    @Environment(\.focusInterfaceDensity) private var density

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Button(action: onToggle) { header }
                .buttonStyle(StoryPressStyle())
                .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
                .accessibilityHint(isOpen ? "Fold these events" : "Show each event")
            if isOpen {
                Rectangle().fill(StoryStyle.line).frame(height: 1)
                eventList
            }
        }
        .padding(StoryStyle.entryInsets(for: density))
        .background(StoryStyle.well.opacity(0.6), in: RoundedRectangle(cornerRadius: StoryStyle.entryRadius))
    }

    private var header: some View {
        HStack(spacing: Tokens.Space.m) {
            VStack(alignment: .leading, spacing: 2.zoomed) {
                Text(run.title).font(Tokens.Typography.label)
                Text(caption).font(Tokens.Typography.body).foregroundStyle(.secondary)
            }
            Spacer(minLength: Tokens.Space.s)
            Image(systemName: "chevron.right")
                .font(Tokens.Typography.caption).foregroundStyle(.secondary)
                .rotationEffect(.degrees(isOpen ? 90 : 0))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var caption: String {
        let time = run.span.map { Tokens.timeRange($0.start, $0.end) } ?? ""
        return run.allQuickReturns ? time + " · Daybook back within a minute each time" : time
    }

    private var eventList: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Tokens.Space.m,
             verticalSpacing: Tokens.Space.s) {
            ForEach(Array(run.pins.enumerated()), id: \.offset) { _, pin in
                GridRow {
                    Text(Tokens.timeOfDayOnly(pin.event.at))
                        .font(Tokens.Typography.body.monospacedDigit()).foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text(pin.event.title).font(Tokens.Typography.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(pin.event.returnLine(resumed: pin.resumed) ?? "")
                        .font(Tokens.Typography.body).foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var spoken: String {
        let lines = run.pins.map { pin in
            "\(Tokens.timeOfDayOnly(pin.event.at)), \(pin.event.title)"
                + (pin.event.returnLine(resumed: pin.resumed).map { ", \($0)" } ?? "") + "."
        }
        return (["\(run.title), \(caption)."] + lines).joined(separator: " ")
    }
}
