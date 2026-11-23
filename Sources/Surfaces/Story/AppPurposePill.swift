import SwiftUI

/// A category's mark: its symbol in the category's ink, then its name.
/// Colour is never the only cue.
struct AppPurposeLabel: View {
    let purpose: AppPurpose

    var body: some View {
        HStack(spacing: 5.zoomed) {
            Image(systemName: purpose.symbolName)
                .font(Tokens.Typography.caption)
                .foregroundStyle(StoryStyle.ink(purpose.hue))
                .accessibilityHidden(true)
            Text(purpose.displayName).lineLimit(1)
        }
    }
}

/// The last category change made in one place, kept so it can be undone there.
final class PurposeChangeBox: ObservableObject {
    struct Change: Equatable {
        let bundleID: String
        let appName: String
        let previous: AppPurpose?
        let now: AppPurpose?
        /// What the app shows after the change, for the confirmation.
        let shown: AppPurpose
    }
    @Published var last: Change?
}

/// An app's category as a pill. Clicking it opens the choices; a choice
/// changes the app everywhere, past days included.
struct AppPurposePill: View {
    let bundleID: String
    let appName: String
    let purpose: AppPurpose
    let source: PurposeSource
    /// Symbol only, where a heading beside it already names the category.
    var compact = false
    let onChoose: (AppPurpose?) -> Void
    @StateObject private var open = BoolBox()

    var body: some View {
        Button { open.value = true } label: {
            HStack(spacing: Tokens.Space.xs) {
                if compact {
                    Image(systemName: purpose.symbolName)
                        .foregroundStyle(StoryStyle.ink(purpose.hue))
                        .accessibilityHidden(true)
                } else {
                    AppPurposeLabel(purpose: purpose)
                }
                Image(systemName: "chevron.down")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(StoryStyle.supportingInk)
                    .accessibilityHidden(true)
            }
            .font(Tokens.Typography.caption)
            .foregroundStyle(.primary)
            .padding(.horizontal, 8.zoomed)
            .padding(.vertical, 3.zoomed)
            .background(Tokens.Palette.purpose(purpose).opacity(0.14), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Change the category for \(appName)")
        .accessibilityLabel("\(appName) category: \(purpose.displayName)")
        .accessibilityHint("Changes this app's category here and in past days")
        .popover(isPresented: $open.value, arrowEdge: .bottom) {
            AppPurposePicker(appName: appName, current: purpose, isYours: source == .yours,
                             isBrowser: source == .behaviour) { choice in
                open.value = false
                onChoose(choice)
            }
        }
    }
}

/// The seven categories, each with examples so the words need no glossary.
struct AppPurposePicker: View {
    let appName: String
    let current: AppPurpose
    let isYours: Bool
    let isBrowser: Bool
    let onChoose: (AppPurpose?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2.zoomed) {
            Text("Category for \(appName)")
                .font(Tokens.Typography.label)
                .foregroundStyle(StoryStyle.supportingInk)
                .padding(.horizontal, Tokens.Space.s)
                .padding(.bottom, Tokens.Space.xs)
                .accessibilityAddTraits(.isHeader)
            ForEach(AppPurpose.allCases, id: \.self) { purpose in
                choiceRow(purpose)
            }
            if isYours {
                Divider().padding(.vertical, Tokens.Space.xs)
                Button { onChoose(nil) } label: {
                    Text("Use Daybook's choice")
                        .font(Tokens.Typography.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Tokens.Space.s)
                        .padding(.vertical, 5.zoomed)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text(isBrowser && !isYours
                 ? "A browser follows what you do in it. Choosing one makes it always count this way."
                 : "Changes \(appName) here and in past days.")
                .font(Tokens.Typography.caption)
                .foregroundStyle(StoryStyle.supportingInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Tokens.Space.s)
                .padding(.top, Tokens.Space.xs)
        }
        .padding(Tokens.Space.s)
        .frame(width: 270.zoomed)
    }

    private func choiceRow(_ purpose: AppPurpose) -> some View {
        let selected = purpose == current
        return Button { if !selected { onChoose(purpose) } } label: {
            HStack(spacing: Tokens.Space.s) {
                Image(systemName: purpose.symbolName)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(.white)
                    .frame(width: 22.zoomed, height: 22.zoomed)
                    .background(Tokens.Palette.purpose(purpose),
                                in: RoundedRectangle(cornerRadius: Tokens.Radius.mark))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1.zoomed) {
                    Text(purpose.displayName).font(Tokens.Typography.body)
                    Text(purpose.examples).font(Tokens.Typography.caption)
                        .foregroundStyle(StoryStyle.supportingInk)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(Tokens.Typography.label)
                        .foregroundStyle(Tokens.Colour.focus)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Tokens.Space.s)
            .padding(.vertical, 4.zoomed)
            .background(selected ? Tokens.Colour.hover : .clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.mark))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(purpose.displayName), for example \(purpose.examples)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// "Claude is now Coding, here and in past days. Undo", where the change was made.
struct PurposeChangeNotice: View {
    let change: PurposeChangeBox.Change
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Tokens.Colour.progress)
                .accessibilityHidden(true)
            Text(change.now == nil
                 ? "\(change.appName) is back to Daybook's choice, \(change.shown.displayName)."
                 : "\(change.appName) is now \(change.shown.displayName), here and in past days.")
                .font(Tokens.Typography.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Undo", action: onUndo)
                .buttonStyle(StoryLinkStyle())
                .accessibilityLabel("Undo the category change for \(change.appName)")
        }
        .padding(.horizontal, 10.zoomed)
        .padding(.vertical, 6.zoomed)
        .background(Tokens.Colour.progress.opacity(0.1), in: RoundedRectangle(cornerRadius: Tokens.Radius.nested))
        .accessibilityElement(children: .combine)
    }
}
