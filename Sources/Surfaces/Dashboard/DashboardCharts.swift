import SwiftUI

// The dashboard's small visualisations. Plain values in, so the gallery can
// drive them from fixtures and the store can swap data without touching them.

/// A per-day series as a strip of bars, the last day full strength. Lives
/// under a stat card's figure: the shape of the week behind today's number.
struct Sparkline: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let values: [Double]
    var tint: Color = .accentColor
    var height: CGFloat = 26

    var body: some View {
        let peak = max(values.max() ?? 1, 0.000_1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint.opacity(index == values.count - 1 ? 1 : 0.4))
                    .frame(height: max(3, height * CGFloat(value / peak)))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height, alignment: .bottom)
        .animation(reduceMotion ? nil : Tokens.Motion.settle,
                   value: values)
        .accessibilityHidden(true)
    }
}

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

/// The work-type split as a ring of arcs with a legend. The centre holds the
/// number of kinds; the arcs hover to their share.
struct WorkTypeDonut: View {
    let shares: [WorkTypeShare]
    var diameter: CGFloat = 88
    var lineWidth: CGFloat = 14

    private var cumulative: [(share: WorkTypeShare, from: Double, to: Double)] {
        var acc = 0.0
        return shares.map { share in
            let from = acc
            acc += share.share
            return (share, from, min(1, acc))
        }
    }

    var body: some View {
        if shares.isEmpty {
            Text("No sessions yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: Tokens.Space.m) {
                ZStack {
                    Circle().stroke(Tokens.Colour.elevated, lineWidth: lineWidth)
                    ForEach(cumulative, id: \.share.id) { slice in
                        Circle()
                            .trim(from: slice.from, to: slice.to)
                            .stroke(Tokens.Palette.workType(slice.share.workType),
                                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                            .help("\(slice.share.workType.displayName) "
                                  + "\(Int((slice.share.share * 100).rounded()))%")
                    }
                    Text("\(shares.count)")
                        .font(Tokens.Typography.ringLabel)
                        .foregroundStyle(.secondary)
                }
                .frame(width: diameter, height: diameter)
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    ForEach(shares) { share in
                        HStack(spacing: Tokens.Space.xs) {
                            Circle().fill(Tokens.Palette.workType(share.workType))
                                .frame(width: 8, height: 8)
                            Text(share.workType.displayName)
                                .font(Tokens.Typography.metadata)
                            Text("\(Int((share.share * 100).rounded()))%")
                                .font(Tokens.Typography.metadata.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// The apps open right now as a row of chips under the title — the right rail
/// they used to fill is gone. Hover for when each was launched.
struct RunningNowChips: View {
    let apps: [RunningApp]

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            SectionHeader(title: "Running now")
                .fixedSize()
            ForEach(apps.prefix(8)) { app in
                HStack(spacing: Tokens.Space.xs) {
                    AppIcon(bundleID: app.bundleID, size: 14, appName: app.appName)
                    Text(app.appName)
                        .font(Tokens.Typography.metadata)
                        .lineLimit(1)
                }
                .padding(.horizontal, Tokens.Space.s)
                .padding(.vertical, 4)
                .overlay(Capsule().strokeBorder(Tokens.Colour.line))
                .help((app.launched.map { Tokens.timeOfDay($0) } ?? "")
                      + (app.openFor.map { " · in front \(Tokens.preciseDuration($0))" } ?? ""))
            }
            if apps.count > 8 {
                Text("+\(apps.count - 8) more")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }
}
