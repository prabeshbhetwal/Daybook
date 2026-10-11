import SwiftUI

/// What History's search understood, one chip per phrase in the order typed.
/// The × takes the phrase out of the field. A phrase the on-device model
/// supplied leads with the sparkles. Reads only published values: the parsing
/// happened when the text changed.
struct HistorySearchChips: View {
    @ObservedObject var store: SessionStore
    /// Texts the on-device model supplied.
    let rescued: Set<String>

    private static let rescuedSuffix = ", suggested by on-device AI"

    var body: some View {
        let search = store.historyParsedSearch
        let text = store.historySearchText
        if !search.phrases.isEmpty {
            ChipFlow(spacing: Tokens.Space.xs) {
                ForEach(Array(search.phrases.enumerated()), id: \.offset) { _, phrase in
                    // The ranges belong to the text they were read from; one
                    // that no longer fits it is not drawn.
                    let fits = phrase.range.upperBound <= text.endIndex
                    chip(phrase, search, fromModel: fits && rescued.contains(String(text[phrase.range])))
                }
                if search.noOverlap {
                    Text("No overlap")
                        .font(Tokens.Typography.body)
                        .foregroundStyle(StoryStyle.supportingInk)
                        .padding(.horizontal, Tokens.Space.xs)
                        .frame(height: Self.height)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static var height: CGFloat { 28.zoomed }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous) }

    private func chip(_ phrase: SearchPhrase, _ search: ParsedSearch, fromModel: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: Tokens.Space.xs) {
                lead(phrase, search, fromModel: fromModel)
                Text(phrase.label)
                    .font(Tokens.Typography.control)
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
            .padding(.leading, Tokens.Space.s)
            Button { store.removeHistoryPhrase(phrase) } label: {
                Image(systemName: "xmark")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(StoryStyle.supportingInk)
                    .frame(width: AccessibilityMetrics.minimumTargetSize, height: Self.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(StoryPressStyle())
            .help("Remove \(phrase.label)")
            .accessibilityLabel("Remove \(phrase.label)")
        }
        .background(Tokens.Colour.elevated, in: shape)
        .overlay(shape.strokeBorder(Tokens.Colour.line))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(phrase.label + (fromModel ? Self.rescuedSuffix : ""))
    }

    @ViewBuilder private func lead(_ phrase: SearchPhrase, _ search: ParsedSearch, fromModel: Bool) -> some View {
        Group {
            if fromModel {
                Image(systemName: "sparkles")
                    .foregroundStyle(StoryStyle.supportingInk)
            } else if phrase.kind == .app, let bundleID = search.appBundleID {
                AppIcon(bundleID: bundleID, size: 16.zoomed, appName: phrase.label)
            } else if phrase.kind == .category, let type = search.workType {
                Circle().fill(Tokens.Palette.workType(type)).frame(width: 8.zoomed, height: 8.zoomed)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The chips with the rescue's published marks, or without when there is no rescue.
struct HistorySearchChipRow: View {
    @ObservedObject var store: SessionStore
    let rescue: SearchRescue?

    var body: some View {
        if let rescue {
            Marked(store: store, rescue: rescue)
        } else {
            HistorySearchChips(store: store, rescued: [])
        }
    }

    private struct Marked: View {
        @ObservedObject var store: SessionStore
        @ObservedObject var rescue: SearchRescue
        var body: some View { HistorySearchChips(store: store, rescued: rescue.rescuedTexts) }
    }
}

/// A small spinner at the field's trailing edge while the model reads.
struct HistoryRescueSpinner: View {
    @ObservedObject var rescue: SearchRescue

    var body: some View {
        if rescue.isRescuing {
            ProgressView()
                .controlSize(.small)
                .frame(width: 16.zoomed, height: 16.zoomed)
                .accessibilityLabel("Reading your search")
                .transition(.opacity)
        }
    }
}
