import SwiftUI

/// Shared measures, so the hour axis sits exactly over every row's strip.
enum HistoryRowLayout {
    static var dateWidth: CGFloat { 46.zoomed }
    static var figureWidth: CGFloat { 70.zoomed }
    static var spacing: CGFloat { Tokens.Space.m }
    static var inset: CGFloat { Tokens.Space.s }
}

/// The day's recorded entries across its twenty-four hours: sessions in their
/// category's colour, recorded breaks in grey. One scale for every row, so a
/// morning person's list reads as a column of mornings.
struct HistoryDayStrip: View {
    let date: Date
    let entries: [DayEntry]
    var height: CGFloat = 8.zoomed

    private struct Mark: Identifiable {
        let id: String
        let start: Double
        let length: Double
        let colour: Color
    }

    private var marks: [Mark] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let total = max(1, dayEnd.timeIntervalSince(dayStart))
        var result: [Mark] = []
        func add(_ id: String, _ start: Date, _ end: Date, _ colour: Color) {
            let low = max(start, dayStart), high = min(end, dayEnd)
            guard high > low else { return }
            result.append(Mark(id: id, start: low.timeIntervalSince(dayStart) / total,
                               length: high.timeIntervalSince(low) / total, colour: colour))
        }
        for entry in entries {
            switch entry {
            case .session(let session):
                for (index, span) in session.spans.enumerated() {
                    add("\(session.id)-\(index)", span.start, span.end,
                        Tokens.Palette.workType(session.workType))
                }
            case .rest(let rest):
                add("\(rest.id)", rest.start, rest.end, Tokens.Palette.warmGrey.opacity(0.55))
            }
        }
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(StoryStyle.line)
                ForEach(marks) { mark in
                    RoundedRectangle(cornerRadius: 2.zoomed, style: .continuous)
                        .fill(mark.colour)
                        .frame(width: max(3.zoomed, geometry.size.width * mark.length))
                        .offset(x: geometry.size.width * mark.start)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Clock labels over the strips: midnight to midnight, a label every six hours.
struct HistoryStripAxis: View {
    var leading: CGFloat = HistoryRowLayout.inset + HistoryRowLayout.dateWidth + HistoryRowLayout.spacing
    var trailing: CGFloat = HistoryRowLayout.inset + HistoryRowLayout.figureWidth + HistoryRowLayout.spacing

    var body: some View {
        GeometryReader { geometry in
            ForEach([0, 6, 12, 18], id: \.self) { hour in
                Text(HistoryHours.label(hour))
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .offset(x: geometry.size.width * CGFloat(hour) / 24)
            }
        }
        .frame(height: 12.zoomed)
        .padding(.leading, leading)
        .padding(.trailing, trailing)
        .accessibilityHidden(true)
    }
}
