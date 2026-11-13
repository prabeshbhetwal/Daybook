import SwiftUI

/// One bar per day from the first day on record to today. A day with a
/// figure can be clicked: a search brings it into view below, the overview
/// opens it. Every bar is one ink, and a dashed line can mark the average a bar is read against.
struct HistoryResultChart: View {
    struct Value: Equatable {
        let primary: TimeInterval
        let secondary: TimeInterval
        var total: TimeInterval { primary + secondary }
    }

    let firstDay: Date
    let today: Date
    let values: [Date: Value]
    /// An app's use: in-session and outside parts, in the app-use colour.
    let isLens: Bool
    /// The picked app, so its bars wear its colour.
    var appBundleID: String?
    let onPick: (Date) -> Void
    /// Drawn as a dashed line and named, not printed: its figure is already
    /// the headline's.
    var average: TimeInterval?
    var hint: String?

    static var height: CGFloat { 64.zoomed }

    static let maximumDays = 1_000

    // ponytail: one bar per day; past a year of record the bars thin to a
    // point, and weeks would read better.
    /// The newest `maximumDays` days, oldest first. Each step is the day's
    /// real end: where a clock skips midnight, start of day plus one day
    /// lands past the next day's start, and its bar would find no figure.
    private var days: [Date] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: today)
        let earliest = calendar.date(byAdding: .day, value: -(Self.maximumDays - 1), to: end) ?? end
        var cursor = calendar.startOfDay(for: max(firstDay, earliest))
        var result: [Date] = []
        while cursor <= end, result.count < Self.maximumDays {
            result.append(cursor)
            guard let next = calendar.dateInterval(of: .day, for: cursor)?.end else { break }
            cursor = calendar.startOfDay(for: next)
        }
        return result
    }

    private var primaryColour: Color { Tokens.Palette.appUse }

    var body: some View {
        let days = self.days
        let peak = max(values.values.map(\.total).max() ?? 0, average ?? 0, 1)
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Each day")
                    .font(Tokens.Typography.label)
                    .foregroundStyle(StoryStyle.supportingInk)
                Spacer(minLength: Tokens.Space.s)
                if let hint {
                    Text(hint)
                        .font(Tokens.Typography.body)
                        .foregroundStyle(StoryStyle.supportingInk)
                }
            }
            HStack(alignment: .bottom, spacing: days.count > 240 ? 0 : days.count > 120 ? 1 : 2.zoomed) { // zoom: fixed
                ForEach(days, id: \.self) { day in bar(day, peak: peak) }
            }
            .frame(height: Self.height, alignment: .bottom)
            .overlay(alignment: .bottom) { averageLine(peak: peak) }
            // Room for the average's label, which sits above its line: on a
            // line near the top it rose into the hint and cut its letters.
            .padding(.top, average == nil ? 0 : Tokens.Space.s)
            HStack {
                Text(DateFormats.dayMonth(days.first ?? firstDay))
                Spacer(minLength: Tokens.Space.s)
                Text("Today")
            }
            .font(Tokens.Typography.caption)
            .foregroundStyle(StoryStyle.supportingInk)
            if isLens {
                HStack(spacing: Tokens.Space.m) {
                    swatch("In a session") { primaryColour }
                    swatch("Outside sessions") { outsideFill(primaryColour) }
                }
            }
        }
        .padding(StoryStyle.tileInsets)
        .background(StoryStyle.card, in: RoundedRectangle(cornerRadius: StoryStyle.tileRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: StoryStyle.tileRadius, style: .continuous)
            .strokeBorder(Tokens.Colour.line, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Each day")
        .accessibilityValue(DurationText.spoken(in: spokenSummary))
        // The bars are tap-only, so each day with a figure is also a button
        // of its own under the summary, reachable without a pointer.
        .accessibilityChildren {
            ForEach(days.filter { (values[$0]?.total ?? 0) > 0 }, id: \.self) { day in
                Button(DurationText.spoken(in: "\(DateFormats.longDate(day)), "
                                           + Tokens.duration(values[day]?.total ?? 0))) { onPick(day) }
            }
        }
    }

    @ViewBuilder private func bar(_ day: Date, peak: TimeInterval) -> some View {
        if let value = values[day], value.total > 0 {
            let height = max(4.zoomed, Self.height * value.total / peak)
            let colour = primaryColour
            VStack(spacing: 0) {
                outsideFill(colour)
                    .frame(height: height * value.secondary / value.total)
                Rectangle().fill(colour)
                    .frame(height: height * value.primary / value.total)
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 2.zoomed, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { onPick(day) }
            .help("\(DateFormats.shortDay(day)) · \(Tokens.preciseDuration(value.total))")
        } else {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(StoryStyle.line)
                .frame(maxWidth: .infinity)
                .frame(height: 2.zoomed)
        }
    }

    @ViewBuilder private func averageLine(peak: TimeInterval) -> some View {
        if let average, average > 0 {
            let lift = Self.height * average / peak
            ZStack(alignment: .trailing) {
                DashedRule()
                    .stroke(Color.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3.zoomed, 3.zoomed])) // ink: quiet, a drawn mark
                    .frame(height: 1)
                Text("average day")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(StoryStyle.supportingInk)
                    .padding(.horizontal, Tokens.Space.xs)
                    .background(StoryStyle.card)
                    .offset(y: -8.zoomed)
            }
            .offset(y: -lift)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Time outside a session: the app-use ink at 42% over the stripes the day
    /// uses for time no event explains, so it is not told apart by tint alone.
    private func outsideFill(_ colour: Color) -> some View {
        ZStack {
            HatchFill()
            colour.opacity(0.42)
        }
    }

    private func swatch<Fill: View>(_ label: String, @ViewBuilder fill: () -> Fill) -> some View {
        HStack(spacing: Tokens.Space.xs) {
            fill()
                .frame(width: 9.zoomed, height: 9.zoomed)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.bar, style: .continuous))
            Text(label).font(Tokens.Typography.caption).foregroundStyle(StoryStyle.supportingInk)
        }
    }

    private var spokenSummary: String {
        let used = values.filter { $0.value.total > 0 }
        guard let best = used.max(by: { $0.value.total < $1.value.total }) else { return "nothing recorded" }
        let count = used.count == 1 ? "1 day" : "\(used.count) days"
        var summary = "\(count), the most on \(DateFormats.longDate(best.key)), "
            + Tokens.duration(best.value.total)
        if let average, average > 0 { summary += ", an average day \(Tokens.duration(average))" }
        return summary
    }
}

/// A straight line across its frame, for a dashed stroke.
private struct DashedRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
