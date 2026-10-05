import SwiftUI

/// History's rail while a search runs: about the matches, never about the
/// period the tree had open. A picked app gets its own tiles: how its time
/// splits around sessions, when in the day it falls, what ran beside it and
/// which categories it shows up in.
struct HistorySearchRail: View {
    @ObservedObject var store: SessionStore
    let entries: [JournalEntry]
    let lens: HistoryAppLens?

    var body: some View {
        if let lens, let bundleID = store.historyFilter.appBundleID {
            let name = store.historyAppName(for: bundleID)
            splitTile(lens, name: name)
            rhythmTile(lens)
            if !lens.alongside.isEmpty {
                StoryTile(title: "Alongside it", trailing: "same sessions") {
                    ForEach(Array(lens.alongside.prefix(4).enumerated()), id: \.element.id) { index, app in
                        StoryAppRow(app: app, rank: index)
                    }
                }
            }
            categoryTile(lens)
        } else {
            let apps = store.historySearchApps()
            if !apps.isEmpty {
                StoryTile(title: "Apps in these sessions", trailing: apps.count == 1 ? "1 app" : "\(apps.count) apps") {
                    ForEach(Array(apps.prefix(4).enumerated()), id: \.element.id) { index, app in
                        StoryAppRow(app: app, rank: index)
                    }
                }
            }
            bestDayTile
        }
    }

    /// The app's whole record in two parts that add up to the figure.
    private func splitTile(_ lens: HistoryAppLens, name: String) -> some View {
        let inside = StoryRailFigures.minutes(lens.inSession)
        let outside = StoryRailFigures.minutes(lens.outsideTotal)
        let colour = Tokens.Palette.app(rank: 1)
        return StoryTile(title: name, trailing: "All time") {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                Text(durations: HistorySearchText.lensTotal(lens))
                    .font(Tokens.Typography.heading.monospacedDigit())
                Text("recorded app use")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(.secondary)
            }
            if inside + outside > 0 {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        Rectangle().fill(colour)
                            .frame(width: geometry.size.width * Double(inside) / Double(inside + outside))
                        Rectangle().fill(colour.opacity(0.42))
                    }
                }
                .frame(height: 7)
                .clipShape(Capsule())
                .accessibilityHidden(true)
            }
            legendRow(colour, "In a session", Tokens.duration(TimeInterval(inside * 60)))
            legendRow(colour.opacity(0.42), "Outside sessions", Tokens.duration(TimeInterval(outside * 60)))
        }
    }

    /// When in the day the app was in front, summed over the whole record.
    private func rhythmTile(_ lens: HistoryAppLens) -> some View {
        let calendar = Calendar.current
        let hours = Rhythm.clockHours(colorIndex: 1, calendar: calendar) {
            lens.hoursInSession[$0] + lens.hoursOutside[$0]
        }
        let peak = Rhythm.peakLabel(hours) { HistoryHours.label(calendar.component(.hour, from: $0)) }
        return StoryTile(title: "Rhythm", trailing: "by hour") {
            RhythmChart(hours: hours, height: 54, compactLabels: true)
            if let peak {
                Text("Most use: \(peak).")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The categories of the sessions that used the app.
    @ViewBuilder private func categoryTile(_ lens: HistoryAppLens) -> some View {
        let counts = Self.categoryCounts(lens)
        if !counts.isEmpty {
            let total = Double(lens.sessions.count)
            StoryTile(title: "Shows up in", trailing: nil) {
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        ForEach(counts, id: \.key) { entry in
                            Rectangle().fill(Tokens.Palette.workType(entry.key))
                                .frame(width: max(2, geometry.size.width * Double(entry.value) / total - 2))
                        }
                    }
                }
                .frame(height: 7)
                .clipShape(Capsule())
                .accessibilityHidden(true)
                ForEach(counts, id: \.key) { entry in
                    legendRow(Tokens.Palette.workType(entry.key), entry.key.displayName,
                              entry.value == 1 ? "1 session" : "\(entry.value) sessions")
                }
            }
        }
    }

    /// Sessions per category, most first.
    static func categoryCounts(_ lens: HistoryAppLens) -> [(key: WorkType, value: Int)] {
        var counts: [WorkType: Int] = [:]
        for use in lens.sessions { counts[use.workType, default: 0] += 1 }
        return counts.sorted { left, right in
            left.value == right.value ? left.key.displayName < right.key.displayName : left.value > right.value
        }
    }

    /// The day the matches held the most focus, when there is more than one.
    @ViewBuilder private var bestDayTile: some View {
        let days = entries.compactMap { entry -> JournalDay? in
            if case .day(let day) = entry, day.focused > 0 { return day } else { return nil }
        }
        if days.count > 1, let best = days.max(by: { $0.focused < $1.focused }) {
            StoryTile(title: "Best day", trailing: nil) {
                Text(Tokens.longDate(best.date))
                    .font(Tokens.Typography.heading)
                Text(durations: "\(Tokens.duration(best.focused)) focused")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func legendRow(_ colour: Color, _ label: String, _ value: String) -> some View {
        HStack(spacing: Tokens.Space.s) {
            RoundedRectangle(cornerRadius: Tokens.Radius.bar, style: .continuous).fill(colour).frame(width: 10, height: 10)
            Text(label).font(Tokens.Typography.body).foregroundStyle(.secondary)
            Spacer(minLength: Tokens.Space.xs)
            Text(durations: value)
                .font(Tokens.Typography.label.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(DurationText.spoken(in: "\(label), \(value)"))
    }
}
