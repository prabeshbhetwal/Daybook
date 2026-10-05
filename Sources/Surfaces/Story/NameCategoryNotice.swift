import SwiftUI

/// Under the category goals: sessions and rules whose name spells a category
/// they are not filed under, so the goal that name suggests never sees them.
/// One Move files them under it, with Undo; Keep as is stops the offer until
/// a new session or rule joins.
struct NameCategoryNotice: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: SettingsModel
    @State private var moved: (tidy: NameCategoryTidy, undo: NameCategoryTidyUndo)?

    private var offered: NameCategoryTidy? {
        store.nameCategoryTidies(rules: settings.activityRules, on: store.now())
            .first { $0.signature != store.engine.store.nameCategoryKept }
    }

    var body: some View {
        if let moved {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                Text(Self.movedSentence(moved.tidy))
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Undo") { undo(moved.undo) }
                    .buttonStyle(StoryLinkStyle())
            }
            .accessibilityElement(children: .contain)
        } else if let tidy = offered {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Label {
                    Text(tidy.sentence)
                        .font(Tokens.Typography.metadata)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(Tokens.Palette.workType(tidy.target))
                }
                HStack(spacing: Tokens.Space.s) {
                    Button("Move to \(tidy.target.displayName)") { move(tidy) }
                        .buttonStyle(StoryActionStyle(tint: Tokens.Palette.workType(tidy.target)))
                        .accessibilityHint("Files them under \(tidy.target.displayName). Undo puts them back.")
                    Button("Keep as is") { store.engine.store.nameCategoryKept = tidy.signature; store.refresh() }
                        .buttonStyle(StoryLinkStyle(tint: .secondary))
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    /// "Moved 2 sessions and the rule to Coding."
    static func movedSentence(_ tidy: NameCategoryTidy) -> String {
        var things: [String] = []
        if !tidy.threads.isEmpty { things.append(tidy.threads.count == 1 ? "1 session" : "\(tidy.threads.count) sessions") }
        if !tidy.rules.isEmpty { things.append(tidy.rules.count == 1 ? "the rule" : "\(tidy.rules.count) rules") }
        return "Moved \(things.joined(separator: " and ")) to \(tidy.target.displayName)."
    }

    private func move(_ tidy: NameCategoryTidy) {
        let corrections = store.fileSessionsUnderTheirNamedCategory(tidy)
        for var rule in tidy.rules {
            rule.workType = tidy.target
            settings.saveActivityRule(rule)
        }
        moved = (tidy, NameCategoryTidyUndo(corrections: corrections, rules: tidy.rules))
    }

    private func undo(_ undo: NameCategoryTidyUndo) {
        store.undoNameCategoryTidy(undo.corrections)
        for rule in undo.rules { settings.saveActivityRule(rule) }
        moved = nil
    }
}
