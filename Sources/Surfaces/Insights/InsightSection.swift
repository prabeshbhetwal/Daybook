import SwiftUI

/// What a card says, separated from how it looks. It wraps an `Insight` that
/// already exists and never manufactures a fact: a missing finding removes the
/// card rather than producing a zero-valued one.
struct InsightPresentation: Equatable {
    let title: String
    let headline: String
    let provenance: String

    var disclosureLabel: String { "How this is calculated" }

    init(title: String, insight: Insight) {
        self.title = title
        self.headline = insight.headline
        self.provenance = insight.detail
    }
}

/// One finding as a rail tile: the title the rail uses, a chart where the
/// finding has one, the sentence, and the method behind a disclosure. The
/// tile never owns a fallback value: only a present `Insight` reaches it.
struct InsightSection: View {
    let title: String
    let insight: Insight
    /// Hour bars, for Rhythm.
    var rhythm: [RhythmHour]? = nil
    /// Category shares, for Focus quality and By category.
    var shares: [WorkTypeShare]? = nil
    @StateObject private var expanded = BoolBox()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presentation: InsightPresentation {
        InsightPresentation(title: title, insight: insight)
    }

    var body: some View {
        StoryTile(title: presentation.title, trailing: nil) {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                if let rhythm, rhythm.contains(where: { $0.seconds > 0 }) {
                    RhythmChart(hours: rhythm, height: 44.zoomed, compactLabels: true)
                }
                if let shares, !shares.isEmpty {
                    CategoryShareBar(shares: shares)
                }
                Text(presentation.headline)
                    .font(Tokens.Typography.heading)
                    .fixedSize(horizontal: false, vertical: true)
                if expanded.value {
                    Text(presentation.provenance)
                        .font(Tokens.Typography.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(Tokens.Motion.transition(Tokens.Motion.unfold, reduceMotion: reduceMotion))
                }
            }
        }
        // The method sits on the title's line, at the tile's corner: one quiet
        // mark where a sentence-long link used to take a row of every tile.
        .overlay(alignment: .topTrailing) { methodButton }
        .accessibilityElement(children: .contain)
    }

    private var methodButton: some View {
        Button {
            withAnimation(Tokens.Motion.animation(
                expanded.value ? Tokens.Motion.dismiss : Tokens.Motion.reveal,
                reduceMotion: reduceMotion)) { expanded.value.toggle() }
        } label: {
            Image(systemName: expanded.value ? "info.circle.fill" : "info.circle")
                .font(Tokens.Typography.control)
                .foregroundStyle(expanded.value ? AnyShapeStyle(StoryStyle.action)
                                                : AnyShapeStyle(.tertiary))
                .frame(width: AccessibilityMetrics.minimumTargetSize,
                       height: AccessibilityMetrics.minimumTargetSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle())
        .padding(.top, Tokens.Space.xs)
        .padding(.trailing, Tokens.Space.xs)
        .help(expanded.value ? "Hide how this is calculated" : presentation.disclosureLabel)
        .accessibilityLabel(expanded.value ? "Hide how \(presentation.title) is calculated"
                                           : "\(presentation.disclosureLabel): \(presentation.title)")
    }
}

/// One bar split by category, with the legend the week chart uses.
struct CategoryShareBar: View {
    let shares: [WorkTypeShare]

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            GeometryReader { geometry in
                // The gaps come out of the width first, or the bar overran
                // its card by one gap per category after the first.
                let gap = 2.zoomed
                let width = max(0, geometry.size.width - gap * CGFloat(max(0, shares.count - 1)))
                HStack(spacing: gap) {
                    ForEach(shares) { share in
                        RoundedRectangle(cornerRadius: 2.zoomed, style: .continuous)
                            .fill(Tokens.Palette.workType(share.workType))
                            .frame(width: max(2.zoomed, width * share.share))
                    }
                }
            }
            .frame(height: 8.zoomed)
            .accessibilityHidden(true)
            ChipFlow(spacing: Tokens.Space.m) {
                ForEach(shares) { share in
                    HStack(spacing: Tokens.Space.xs) {
                        Circle().fill(Tokens.Palette.workType(share.workType))
                            .frame(width: 8.zoomed, height: 8.zoomed)
                        Text("\(share.workType.displayName) \(DurationText.percent(share.share))")
                            .font(Tokens.Typography.body)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
