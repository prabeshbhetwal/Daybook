import SwiftUI

// The dashboard's small visualisations. Plain values in, so the gallery can
// drive them from fixtures and the store can swap data without touching them.

/// Minutes at the Mac per hour, each bar in the colour of the app that took
/// most of that hour. Hover names the hour and the minutes.
struct RhythmChart: View {
    let hours: [RhythmHour]
    var height: CGFloat = 120
    /// A bar clicked: the hour, so the timeline's detail row can open on it.
    var onHourTap: ((Date) -> Void)?
    var compactLabels = false

    var body: some View {
        if hours.allSatisfy({ $0.seconds == 0 }) {
            Text("Nothing recorded in this window yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(height: height + 18, alignment: .leading)
        } else {
            VStack(spacing: Tokens.Space.xs) {
                HStack(alignment: .bottom, spacing: labelStep == 1 ? 8 : 4) {
                    ForEach(hours) { hour in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(hour.seconds > 0 ? AnyShapeStyle(Tokens.Palette.app(rank: hour.colorIndex))
                                                   : AnyShapeStyle(Tokens.Colour.elevated))
                            .frame(height: max(3, height * CGFloat(hour.seconds / scaleMaximum)))
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture { onHourTap?(hour.hour) }
                            .help("\(DayTimelineView.hourLabel(hour.hour)) · "
                                  + Tokens.preciseDuration(hour.seconds)
                                  + (onHourTap == nil ? "" : " · click to open the hour"))
                            .accessibilityLabel("\(DayTimelineView.hourLabel(hour.hour)), \(Tokens.spent(hour.seconds)) recorded")
                    }
                }
                .frame(height: height, alignment: .bottom)
                .overlay(alignment: .bottom) { Rectangle().fill(Tokens.Colour.line).frame(height: 1) }
                if compactLabels, let first = hours.first, let last = hours.last {
                    HStack {
                        Text(DayTimelineView.hourLabel(first.hour))
                        Spacer()
                        if hours.count > 2 { Text(DayTimelineView.hourLabel(hours[hours.count / 2].hour)) }
                        Spacer()
                        Text(DayTimelineView.hourLabel(last.hour))
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                } else {
                  HStack(spacing: labelStep == 1 ? 8 : 4) {
                    ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                        Text(index % labelStep == 0 ? DayTimelineView.hourLabel(hour.hour) : "")
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                  }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Recorded app use by hour")
        }
    }

    /// One label per bar up to twelve bars; every second or third beyond, so a
    /// 24-hour day does not collide.
    private var labelStep: Int { hours.count <= 12 ? 1 : (hours.count <= 18 ? 2 : 3) }
    private var scaleMaximum: TimeInterval { max(3_600, hours.map(\.seconds).max() ?? 0) }
}

