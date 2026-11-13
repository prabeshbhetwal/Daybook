import SwiftUI

// The dashboard's small visualisations. Plain values in, so the gallery can
// drive them from fixtures and the store can swap data without touching them.

/// Minutes at the Mac per hour, every bar in the app-use accent. The app that
/// took most of an hour is named on hover and in the bar's accessibility
/// label, and its icon stands under the bar when the column is wide enough.
struct RhythmChart: View {
    let hours: [RhythmHour]
    var height: CGFloat = 120.zoomed
    /// A bar clicked: the hour, so the timeline's detail row can open on it.
    var onHourTap: ((Date) -> Void)?
    var compactLabels = false
    /// The chart's width, measured, so the icons appear only where they fit.
    @State private var width: CGFloat = 0

    var body: some View {
        if hours.allSatisfy({ $0.seconds == 0 }) {
            Text("Nothing recorded in this window yet.")
                .font(Tokens.Typography.body)
                .foregroundStyle(StoryStyle.supportingInk)
                .frame(height: height + 18.zoomed, alignment: .leading)
        } else {
            VStack(spacing: Tokens.Space.xs) {
                HStack(alignment: .bottom, spacing: barSpacing) {
                    ForEach(hours) { hour in
                        // A button, so the keyboard and VoiceOver reach the
                        // hour; without a handler there is nothing to press,
                        // and a disabled button would dim the bar.
                        Group {
                            if let onHourTap {
                                Button { onHourTap(hour.hour) } label: { bar(for: hour) }
                                    .buttonStyle(.plain)
                            } else {
                                bar(for: hour)
                            }
                        }
                            .help("\(DateFormats.hourLabel(hour.hour)) · "
                                  + Tokens.preciseDuration(hour.seconds)
                                  + (hour.seconds > 0 ? hour.topAppName.map { " · \($0)" } ?? "" : "")
                                  + (onHourTap == nil ? "" : " · click to open the hour"))
                            .accessibilityLabel(Self.label(for: hour))
                    }
                }
                .frame(height: height, alignment: .bottom)
                .overlay(alignment: .bottom) { Rectangle().fill(Tokens.Colour.line).frame(height: 1) }
                if showsIcons {
                    HStack(spacing: barSpacing) {
                        ForEach(hours) { hour in
                            Group {
                                if hour.seconds > 0, let bundleID = hour.topBundleID {
                                    AppIcon(bundleID: bundleID, size: AppMarkLayout.iconPoints.zoomed,
                                            appName: hour.topAppName ?? "")
                                        .help(hour.topAppName ?? "")
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: AppMarkLayout.iconPoints.zoomed)
                        }
                    }
                }
                if compactLabels {
                    // Each label under the bar it names: the first and last on
                    // the chart's edges, the middle centred on its own bar.
                    // Spread by spacers, the middle one fell between two bars.
                    let named: Set<Int> = [0, hours.count - 1, hours.count > 2 ? hours.count / 2 : 0]
                    Text(" ")
                        .frame(maxWidth: .infinity)
                        .overlay {
                            HStack(spacing: barSpacing) {
                                ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                                    Color.clear.overlay(alignment: index == 0 ? Alignment.leading
                                                        : (index == hours.count - 1 ? .trailing : .center)) {
                                        if named.contains(index) {
                                            Text(DateFormats.hourLabel(hour.hour)).fixedSize()
                                        }
                                    }
                                }
                            }
                        }
                        .font(Tokens.Typography.caption).foregroundStyle(StoryStyle.supportingInk)
                        .accessibilityHidden(true)
                } else {
                  HStack(spacing: barSpacing) {
                    ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                        Text(index % labelStep == 0 ? DateFormats.hourLabel(hour.hour) : "")
                            .font(Tokens.Typography.body)
                            .foregroundStyle(StoryStyle.supportingInk)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                  }
                }
            }
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { width = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, new in width = new }
            })
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Recorded app use by hour")
        }
    }

    /// The hour, the time, and the app that held it, so the app is named
    /// whether or not its icon fits under the bar.
    static func label(for hour: RhythmHour) -> String {
        let base = "\(DateFormats.hourLabel(hour.hour)), \(Tokens.spent(hour.seconds)) recorded"
        guard hour.seconds > 0, let name = hour.topAppName ?? hour.topBundleID else { return base }
        return base + ", mostly \(name)"
    }

    private var showsIcons: Bool {
        let count = CGFloat(hours.count)
        guard count > 0, hours.contains(where: { $0.seconds > 0 && $0.topBundleID != nil }) else { return false }
        let column = (width - barSpacing * (count - 1)) / count
        return AppMarkLayout.showsIcon(width: Double(column), scale: ZoomModel.shared.scale)
    }

    /// One label per bar up to twelve bars; every second or third beyond, so a
    /// 24-hour day does not collide.
    private var labelStep: Int { hours.count <= 12 ? 1 : (hours.count <= 18 ? 2 : 3) }
    private func bar(for hour: RhythmHour) -> some View {
        RoundedRectangle(cornerRadius: Tokens.Radius.mark, style: .continuous)
            .fill(hour.seconds > 0 ? AnyShapeStyle(Tokens.Palette.appUse)
                                   : AnyShapeStyle(Tokens.Colour.elevated))
            .frame(height: max(3.zoomed, height * CGFloat(hour.seconds / scaleMaximum)))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
    }

    private var barSpacing: CGFloat { labelStep == 1 ? Tokens.Space.s : Tokens.Space.xs }
    private var scaleMaximum: TimeInterval { max(3_600, hours.map(\.seconds).max() ?? 0) }
}

