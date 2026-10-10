import SwiftUI

/// The day's machine events under its story: every sleep, wake, lock, quit,
/// crash and start, each with its time. Folded at first: the holes above
/// already name their causes, and this is the record behind them. An event
/// found only afterwards shows the window it happened in.
struct DayMachineEvents: View {
    let events: [MachineEvent]
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Button { isOpen.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                    Text(events.count == 1 ? "1 Mac event" : "\(events.count) Mac events")
                        .font(Tokens.Typography.body)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: Tokens.Space.xs)
                    Image(systemName: "chevron.down")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(StoryPressStyle(hovers: true))
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            .accessibilityHint(isOpen ? "Hide the Mac's events"
                                      : "Show when the Mac slept, woke, locked, quit or started")
            if isOpen {
                Grid(alignment: .leadingFirstTextBaseline,
                     horizontalSpacing: Tokens.Space.m, verticalSpacing: Tokens.Space.xs) {
                    ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                        GridRow {
                            Text(time(of: event)).monospacedDigit()
                            Text(event.kind.title)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(spoken(event))
                    }
                }
                .font(Tokens.Typography.body)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func time(of event: MachineEvent) -> String {
        guard let latest = event.latest else { return Tokens.timeOfDayOnly(event.at) }
        return Tokens.timeRange(event.at, latest)
    }

    private func spoken(_ event: MachineEvent) -> String {
        guard let latest = event.latest else {
            return "\(Tokens.timeOfDayOnly(event.at)), \(event.kind.title)"
        }
        return "Between \(Tokens.timeOfDayOnly(event.at)) and \(Tokens.timeOfDayOnly(latest)), "
            + event.kind.title
    }
}
