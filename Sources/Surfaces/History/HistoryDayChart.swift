import SwiftUI

/// One bar per day from the first day on record to today. A day with a
/// figure can be clicked: a search brings it into view below, the overview
/// opens it. Bars take their own colour when given one, and a dashed line
/// can mark the average a bar is read against.
struct HistoryResultChart: View {
    struct Value: Equatable {
        let primary: TimeInterval
        let secondary: TimeInterval
        /// The bar's own colour, such as its day's main category; nil draws
        /// it in the chart's.
        var colour: Color?
        var total: TimeInterval { primary + secondary }
    }

    let firstDay: Date
    let today: Date
    let values: [Date: Value]
    /// An app's use: in-session and outside parts, in the app-use colour.
    let isLens: Bool
    let onPick: (Date) -> Void
    /// Drawn as a dashed line and named, not printed: its figure is already
    /// the headline's.
    var average: TimeInterval?
    var hint: String?

    static let height: CGFloat = 64

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

    private var primaryColour: Color { isLens ? Tokens.Palette.app(rank: 1) : Tokens.Colour.focus }

    var body: some View {
        let days = self.days
        let peak = max(values.values.map(\.total).max() ?? 0, average ?? 0, 1)
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Each day")
                    .font(Tokens.Typography.label)
                    .foregroundStyle(.secondary)
                Spacer(minLength: Tokens.Space.s)
                if let hint {
                    Text(hint)
                        .font(Tokens.Typography.body)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .bottom, spacing: days.count > 120 ? 1 : 2) {
                ForEach(days, id: \.self) { day in bar(day, peak: peak) }
            }
            .frame(height: Self.height, alignment: .bottom)
            .overlay(alignment: .bottom) { averageLine(peak: peak) }
            HStack {
                Text(DateFormats.australian("d MMM").string(from: days.first ?? firstDay))
                Spacer(minLength: Tokens.Space.s)
                Text("Today")
            }
            .font(Tokens.Typography.caption)
            .foregroundStyle(.secondary)
            if isLens {
                HStack(spacing: Tokens.Space.m) {
                    swatch(primaryColour, "In a session")
                    swatch(primaryColour.opacity(0.42), "Outside sessions")
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
    }

    @ViewBuilder private func bar(_ day: Date, peak: TimeInterval) -> some View {
        if let value = values[day], value.total > 0 {
            let height = max(4, Self.height * value.total / peak)
            let colour = value.colour ?? primaryColour
            VStack(spacing: 0) {
                Rectangle().fill(colour.opacity(0.42))
                    .frame(height: height * value.secondary / value.total)
                Rectangle().fill(colour)
                    .frame(height: height * value.primary / value.total)
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { onPick(day) }
            .help("\(DateFormats.australian("EEE d MMM").string(from: day)) · \(Tokens.preciseDuration(value.total))")
        } else {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(StoryStyle.line)
                .frame(maxWidth: .infinity)
                .frame(height: 2)
        }
    }

    @ViewBuilder private func averageLine(peak: TimeInterval) -> some View {
        if let average, average > 0 {
            let lift = Self.height * average / peak
            ZStack(alignment: .trailing) {
                DashedRule()
                    .stroke(Color.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(height: 1)
                Text("average day")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .background(StoryStyle.card)
                    .offset(y: -8)
            }
            .offset(y: -lift)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func swatch(_ colour: Color, _ label: String) -> some View {
        HStack(spacing: Tokens.Space.xs) {
            RoundedRectangle(cornerRadius: Tokens.Radius.bar, style: .continuous).fill(colour).frame(width: 9, height: 9)
            Text(label).font(Tokens.Typography.caption).foregroundStyle(.secondary)
        }
    }

    private var spokenSummary: String {
        let used = values.filter { $0.value.total > 0 }
        guard let best = used.max(by: { $0.value.total < $1.value.total }) else { return "nothing recorded" }
        let count = used.count == 1 ? "1 day" : "\(used.count) days"
        var summary = "\(count), the most on \(DateFormats.australian("EEEE d MMMM").string(from: best.key)), "
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
