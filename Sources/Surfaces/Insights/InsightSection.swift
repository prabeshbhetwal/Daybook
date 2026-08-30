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

/// One plain statement, with its method behind a disclosure so the conclusion
/// is what the reader meets first. The card never owns a fallback value: only a
/// present `Insight` reaches this view.
struct InsightSection: View {
    let title: String
    let insight: Insight
    @StateObject private var expanded = BoolBox()

    private var presentation: InsightPresentation {
        InsightPresentation(title: title, insight: insight)
    }

    var body: some View {
        SurfacePanel(showsHeader: false) {
            VStack(alignment: .leading, spacing: Tokens.Space.m) {
                HStack(spacing: Tokens.Space.s) {
                    Image(systemName: insight.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Tokens.Colour.focus)
                        .frame(width: 24, height: 24)
                        .background(Tokens.Colour.elevated, in: Circle())
                        .accessibilityHidden(true)
                    Text(presentation.title)
                        .font(Tokens.Typography.sectionTitle)
                }

                Text(presentation.headline)
                    .font(Tokens.Typography.metricValue)
                    .fixedSize(horizontal: false, vertical: true)

                // Collapsed by default: the method is available on demand
                // instead of permanently consuming half the card.
                DisclosureGroup(isExpanded: Binding(get: { expanded.value },
                                                    set: { expanded.value = $0 })) {
                    Text(presentation.provenance)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Tokens.Space.xs)
                } label: {
                    Text(presentation.disclosureLabel)
                        .font(Tokens.Typography.metadata.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(presentation.title). \(presentation.headline). "
                            + presentation.provenance)
    }
}
