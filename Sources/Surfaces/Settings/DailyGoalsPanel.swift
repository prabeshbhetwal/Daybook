import AppKit
import SwiftUI

/// What a goal's menu can do: set its amount, pause it, or take it away.
private enum GoalChoice: Hashable {
    case amount(TimeInterval)
    case pause, resume, remove
}

/// What the Add Goal menu can add. `none` is the resting label.
private enum AddChoice: Hashable {
    case none
    case category(String)
    case activityLimit(String)
    case appLimit
}

/// The goals beside the day's goal: a category to aim for, an app to keep
/// under. Each goal is one row with one menu, so the page keeps its single
/// column of controls; Today's goals shows how each is going.
extension SettingsGroups {
    var dailyGoalsPanel: some View {
        SurfacePanel(title: "Daily goals", layout: layout) {
            let items = model.dailyGoalItems
            ForEach(items) { item in
                goalRow(item)
                rowDivider
            }
            addGoalRow(items)
        }
    }

    private func goalRow(_ item: DailyGoalItem) -> some View {
        let kind = item.kind == .limit ? "App limit" : "Category goal"
        return preferenceRow(goalName(item), detail: item.isPaused ? "\(kind), paused" : kind) {
            RowMenu("Amount for \(goalName(item))",
                    selection: Binding(get: { GoalChoice.amount(item.seconds) },
                                       set: { applyGoalChoice($0, to: item) }),
                    items: goalAmounts(including: item.seconds).map { .option(.amount($0), Tokens.duration($0)) }
                        + [.option(item.isPaused ? .resume : .pause, item.isPaused ? "Resume" : "Pause"),
                           .option(.remove, "Remove goal")])
        }
    }

    private func applyGoalChoice(_ choice: GoalChoice, to item: DailyGoalItem) {
        switch choice {
        case .amount(let seconds): model.setGoalSeconds(item.id, seconds)
        case .pause: model.setGoalPaused(item.id, true)
        case .resume: model.setGoalPaused(item.id, false)
        case .remove: model.removeGoal(item.id)
        }
    }

    private func addGoalRow(_ items: [DailyGoalItem]) -> some View {
        let free = WorkType.startable.filter { type in
            !items.contains { $0.target == .category(type.rawValue) }
        }
        let freeActivities = DailyGoalList.limitablePurposes.filter { purpose in
            !items.contains { $0.target == .activity(purpose.rawValue) }
        }
        let full = items.count >= DailyGoalList.maximum
        return preferenceRow("Add Goal", detail: full ? "You can keep up to \(DailyGoalList.maximum) goals."
                             : "Limits on a kind of site, such as video, are not available yet.") {
            RowMenu("Add Goal",
                    selection: Binding(get: { AddChoice.none }, set: { choice in
                        switch choice {
                        case .none: break
                        case .category(let id):
                            model.addGoal(DailyGoalItem(target: .category(id), kind: .target, seconds: 2 * 3_600))
                        case .activityLimit(let raw):
                            model.addGoal(DailyGoalItem(target: .activity(raw), kind: .limit, seconds: 2 * 3_600))
                        case .appLimit: choosingGoalApp = true
                        }
                    }),
                    items: full ? [.option(.none, "Full")]
                        : [.option(.none, "Choose")]
                        + free.map { .option(.category($0.rawValue), "\($0.displayName) goal") }
                        + freeActivities.map { .option(.activityLimit($0.rawValue), "\($0.displayName) limit") }
                        + [.option(.appLimit, "App limit")])
        }
        .popover(isPresented: $choosingGoalApp, arrowEdge: .bottom) { goalAppChooser(items) }
    }

    /// The apps open now, less those already limited: the apps a person is most
    /// likely to want to limit are the ones they are using.
    private func goalAppChooser(_ items: [DailyGoalItem]) -> some View {
        let limited = Set(items.compactMap { item -> String? in
            if case .app(let id) = item.target { return id }
            return nil
        })
        let apps = Self.openApps().filter { !limited.contains($0.id) }
        return ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                if apps.isEmpty {
                    Text("Open the app you want to limit, then choose it here.")
                        .font(Tokens.Typography.body)
                        .foregroundStyle(StoryStyle.supportingInk)
                }
                ForEach(apps, id: \.id) { app in
                    Button {
                        model.addGoal(DailyGoalItem(target: .app(app.id), kind: .limit, seconds: 3_600))
                        choosingGoalApp = false
                    } label: {
                        HStack(spacing: Tokens.Space.s) {
                            AppIcon(bundleID: app.id, size: 20.zoomed, appName: app.name)
                            Text(app.name).font(Tokens.Typography.body)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Tokens.Space.m)
        }
        .frame(width: 260.zoomed, height: 280.zoomed)
    }

    private func goalName(_ item: DailyGoalItem) -> String {
        switch item.target {
        case .category(let id): return WorkType(rawValue: id).displayName
        case .app(let id): return Self.goalAppName(id)
        case .site(let value): return DailyGoalList.siteGoalName(value)
        case .activity(let value): return AppPurpose(rawValue: value)?.displayName ?? value
        case .unknown(_, let value): return value
        }
    }

    /// The presets, plus the stored amount if it is not one of them.
    private func goalAmounts(including current: TimeInterval) -> [TimeInterval] {
        let presets = WorkTypeDefinition.goalOptions
        return presets.contains(current) ? presets : (presets + [current]).sorted()
    }

    private static func goalAppName(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return DailyGoalList.fallbackAppName(bundleID)
    }

    private static func openApps() -> [(id: String, name: String)] {
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (id: String, name: String)? in
                guard let id = app.bundleIdentifier, id != own, seen.insert(id).inserted else { return nil }
                return (id, app.localizedName ?? goalAppName(id))
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
