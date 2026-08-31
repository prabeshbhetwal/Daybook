import SwiftUI

/// The tiles beside the story. Each one follows the scope above it, carries its
/// own colour, and shows nothing when it has nothing to say — a tile is never a
/// zero-valued placeholder.
struct StoryRail: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            focusTile
            macTile
            if !apps.isEmpty { appsTile }
            if navigation.storyScope == .day, !store.rhythm.isEmpty { rhythmTile }
            if store.streak > 0 { streakTile }
            Text("Tiles follow the scope above. A tile with nothing to say is hidden.")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Tokens.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Focus

    private var focusTile: some View {
        StoryTile(title: focusTitle, tint: Tokens.Palette.workType(.deepWork),
                  trailing: scopeLabel) {
            HStack(alignment: .bottom, spacing: Tokens.Space.m) {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text(Tokens.duration(focusValue))
                        .font(Tokens.Typography.metricValue.monospacedDigit())
                    Text(focusNote)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if goalShare != nil {
                    GoalRing(progress: goalShare ?? 0, diameter: 56, lineWidth: 7,
                             label: "\(Int(((goalShare ?? 0) * 100).rounded()))%",
                             isMet: (goalShare ?? 0) >= 1,
                             labelFont: .system(size: 12, weight: .bold, design: .rounded))
                }
            }
        }
    }

    private var focusTitle: String {
        switch navigation.storyScope {
        case .day: return "Focus time"
        case .week: return "Focus this week"
        case .month: return "Focus this month"
        }
    }

    private var focusValue: TimeInterval {
        switch navigation.storyScope {
        case .day: return store.isToday ? store.todayTotal : store.focusedForSelectedDay
        case .week, .month: return store.reviewFocusedSeconds
        }
    }

    /// Only the day has a goal to be a share of; a week or a month reports its
    /// own shape instead of inventing a period target.
    private var goalShare: Double? {
        guard navigation.storyScope == .day, store.goal.goal > 0 else { return nil }
        return store.selectedDayGoal.share
    }

    private var focusNote: String {
        switch navigation.storyScope {
        case .day:
            let goal = store.selectedDayGoal
            guard goal.goal > 0 else { return "No daily goal set" }
            return goal.isMet
                ? "Goal met"
                : "\(Tokens.duration(max(0, goal.goal - goal.achieved))) "
                  + (store.isToday ? "to go" : "short of the goal")
        case .week, .month:
            let summary = store.reviewSummary
            guard summary.activeDays > 0 else { return "No active days yet" }
            let dayWord = summary.activeDays == 1 ? "active day" : "active days"
            return "\(summary.activeDays) \(dayWord) · "
                + "\(Tokens.duration(summary.averagePerActiveDay)) average"
        }
    }

    private var scopeLabel: String {
        navigation.storyScope == .day ? store.dayLabel : store.reviewPeriodLabel
    }

    // MARK: - On this Mac

    private var macTile: some View {
        StoryTile(title: "On this Mac", tint: Tokens.Palette.app(rank: 1), trailing: nil) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                Text(Tokens.duration(accountedValue))
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text("not all of it deliberate")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            if accountedValue > 0 {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Tokens.Palette.app(rank: 1))
                            .frame(width: geometry.size.width * width(of: insideValue))
                        Rectangle()
                            .fill(Tokens.Palette.app(rank: 1).opacity(0.42))
                            .frame(width: geometry.size.width * width(of: looseValue))
                        Rectangle()
                            .fill(Tokens.Colour.line)
                    }
                }
                .frame(height: 7)
                .clipShape(Capsule())
                .accessibilityHidden(true)
                legendRow(colour: Tokens.Palette.app(rank: 1),
                          label: "In a focus session",
                          value: Tokens.duration(insideValue))
                legendRow(colour: Tokens.Palette.app(rank: 1).opacity(0.42),
                          label: "At the Mac, no session",
                          value: Tokens.duration(looseValue))
                if unrecordedValue > 0 {
                    legendRow(colour: Tokens.Colour.line,
                              label: "Not recorded",
                              value: Tokens.duration(unrecordedValue))
                    Text("Focused time no app recording covers.")
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The three parts are disjoint by construction: observed time splits into
    /// inside and outside a session, and focused time the recorder never saw is
    /// the remainder. Their total is what the day can account for.
    private var accountedValue: TimeInterval { trackedValue + unrecordedValue }

    private var insideValue: TimeInterval { trackedValue * insideShare }

    private var looseValue: TimeInterval { trackedValue * (1 - insideShare) }

    private var unrecordedValue: TimeInterval {
        switch navigation.storyScope {
        case .day: return store.focusQuality.unrecordedFocusSeconds
        case .week, .month: return store.reviewQuality.unrecordedFocusSeconds
        }
    }

    private func width(of value: TimeInterval) -> Double {
        guard accountedValue > 0 else { return 0 }
        return min(1, max(0, value / accountedValue))
    }

    private var trackedValue: TimeInterval {
        switch navigation.storyScope {
        case .day: return store.isToday ? store.trackedToday : store.trackedForSelectedDay
        case .week, .month: return store.reviewSummary.tracked
        }
    }

    /// The day has a measured inside-session share; a period reports its own
    /// focused time against its own tracked time rather than borrowing the
    /// selected day's quality figure.
    private var insideShare: Double {
        switch navigation.storyScope {
        case .day:
            return min(1, max(0, store.focusQuality.insideSessionShare))
        case .week, .month:
            let tracked = store.reviewSummary.tracked
            guard tracked > 0 else { return 0 }
            return min(1, max(0, store.reviewFocusedSeconds / tracked))
        }
    }

    private func legendRow(colour: Color, label: String, value: String) -> some View {
        HStack(spacing: Tokens.Space.s) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(colour)
                .frame(width: 10, height: 10)
            Text(label)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
            Spacer(minLength: Tokens.Space.xs)
            Text(value)
                .font(Tokens.Typography.metadata.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    // MARK: - Apps

    private var apps: [AppRank] {
        navigation.storyScope == .day
            ? store.rankedApps
            : store.reviewAppGroups.map {
                AppRank(bundleID: $0.bundleID, appName: $0.appName,
                        total: $0.total, share: $0.share, longest: $0.longest)
            }
    }

    private var appsTile: some View {
        StoryTile(title: "Apps", tint: Tokens.Palette.app(rank: 5), trailing: "Top 4") {
            ForEach(Array(apps.prefix(4).enumerated()), id: \.element.id) { index, app in
                AppUsageRow(appName: app.appName, bundleID: app.bundleID,
                            rank: index, seconds: app.total, share: app.share,
                            layout: .compact)
            }
        }
    }

    // MARK: - Rhythm

    private var rhythmTile: some View {
        StoryTile(title: "Rhythm", tint: Tokens.Palette.app(rank: 0), trailing: "by hour") {
            RhythmChart(hours: store.rhythm, height: 54)
            if let peak = store.rhythmPeak {
                Text("Your best hours are \(peak).")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Streak

    private var streakTile: some View {
        StoryTile(title: "Streak", tint: Tokens.Palette.app(rank: 4),
                  trailing: store.streak == 1 ? "1 day" : "\(store.streak) days") {
            HStack(spacing: 3) {
                ForEach(Array(store.streakDays().enumerated()), id: \.offset) { _, entry in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(entry.met ? Tokens.Palette.app(rank: 4) : Tokens.Colour.elevated)
                        .frame(height: 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(store.streak) day streak")
            HStack(spacing: Tokens.Space.xs) {
                Text("Days with at least "
                     + "\(Tokens.preciseDuration(FocusConstants.streakMinimum)) of focus.")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                Button("Awards") { navigation.openSheet(.awards) }
                    .buttonStyle(.plain)
                    .font(Tokens.Typography.metadata.weight(.semibold))
                    .foregroundStyle(Tokens.Colour.focus)
            }
        }
    }
}

/// One rail tile: a coloured title, an optional scope note, and its content.
struct StoryTile<Content: View>: View {
    let title: String
    let tint: Color
    let trailing: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack {
                Text(title)
                    .font(Tokens.Typography.metadata.weight(.bold))
                    .foregroundStyle(tint)
                Spacer(minLength: Tokens.Space.xs)
                if let trailing {
                    Text(trailing)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            content
        }
        .padding(Tokens.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Colour.surface,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous)
            .strokeBorder(Tokens.Colour.line))
        .accessibilityElement(children: .contain)
    }
}
