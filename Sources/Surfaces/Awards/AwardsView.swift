import SwiftUI

/// One award: a badge, what it is, and the evidence that earned it. The method
/// sits behind a disclosure, so the card reads in a glance and still answers a
/// reader who wants to know exactly what was measured.
struct AwardCard: View {
    let award: Award
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var expanded = BoolBox()

    private var tint: Color { Tokens.Palette.app(rank: award.paletteRank) }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HStack(spacing: Tokens.Space.m) {
                badge
                VStack(alignment: .leading, spacing: 2) {
                    Text(award.title)
                        .font(Tokens.Typography.rowTitle)
                        .foregroundStyle(award.isEarned ? AnyShapeStyle(.primary)
                                                        : AnyShapeStyle(.secondary))
                    // In words as well as in the badge's fill, which is the
                    // only difference someone who cannot tell the colours
                    // apart would otherwise have.
                    Text(award.isEarned ? "Earned" : "Not yet")
                        .font(Tokens.Typography.metadata.weight(.semibold))
                        .foregroundStyle(award.isEarned ? AnyShapeStyle(StoryStyle.successInk)
                                                        : AnyShapeStyle(.secondary))
                        // The card's own label already says it.
                        .accessibilityHidden(true)
                    Text(award.detail)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            DisclosureGroup(isExpanded: Binding(get: { expanded.value },
                                                set: { expanded.value = $0 })) {
                Text(award.method)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Tokens.Space.xs)
            } label: {
                Text("How this is measured")
                    .font(Tokens.Typography.metadata.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .animation(Tokens.Motion.animation(Tokens.Motion.rise, reduceMotion: reduceMotion),
                       value: expanded.value)
        }
        .padding(Tokens.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Colour.surface,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous)
            .strokeBorder(Tokens.Colour.line))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(award.title), "
                            + (award.isEarned ? "earned" : "not earned yet")
                            + ", \(award.detail)")
    }

    /// Earned badges carry their identity colour; an unearned one stays a quiet
    /// well, so the difference is visible without reading a word.
    @ViewBuilder private var badge: some View {
        ZStack {
            Circle()
                .fill(award.isEarned
                      ? AnyShapeStyle(LinearGradient(
                            colors: [tint, tint.opacity(0.72)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                      : AnyShapeStyle(Tokens.Colour.elevated))
            Image(systemName: award.isEarned ? award.symbolName : "circle.dotted")
                .font(Tokens.Typography.sectionTitle)
                .foregroundStyle(award.isEarned ? AnyShapeStyle(.white)
                                                : AnyShapeStyle(.secondary))
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

/// Awards and the streak, in one quiet canvas. Nothing here interrupts a
/// session: it is somewhere the user comes and finds, and every figure is a
/// fact the local record already holds.
struct AwardsView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// `ImageRenderer` gives a `ScrollView` no intrinsic content.
    var scrolls = true

    var body: some View {
        Group {
            if scrolls {
                ScrollView { content }
            } else {
                content.frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Tokens.Colour.ground)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            header
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 236),
                                         spacing: Tokens.Space.l,
                                         alignment: .top)],
                      alignment: .leading,
                      spacing: Tokens.Space.l) {
                ForEach(store.awards) { award in
                    AwardCard(award: award)
                }
            }
            streakPanel
        }
        .padding(Tokens.Space.xxl)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Awards")
                .font(Tokens.Typography.pageTitle)
            Text("Earned quietly, never announced. Nothing here interrupts a session.")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    private var streakPanel: some View {
        let days = store.streakDays()
        return SurfacePanel(showsHeader: false) {
            SectionHeader(title: "Streak",
                          trailing: store.streakBest > 0 ? "best \(store.streakBest) days" : nil)
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.m) {
                Text("\(store.streak)")
                    .font(Tokens.Typography.metricValue.monospacedDigit())
                Text("days with at least "
                     + "\(Tokens.preciseDuration(store.engine.store.streakMinimum)) of focus")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                HStack(spacing: 4) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, entry in
                        RoundedRectangle(cornerRadius: Tokens.Radius.bar, style: .continuous)
                            .fill(entry.met ? Tokens.Colour.focus : Tokens.Colour.elevated)
                            .frame(height: 8)
                    }
                }
                // The count the bars show by colour alone.
                Text("\(days.filter(\.met).count) of the last \(days.count) days")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(streakSummary(days))
        }
    }

    private func streakSummary(_ days: [(day: Date, met: Bool)]) -> String {
        let met = days.filter(\.met).count
        return "Last \(days.count) days, \(met) reached the streak minimum"
    }
}
