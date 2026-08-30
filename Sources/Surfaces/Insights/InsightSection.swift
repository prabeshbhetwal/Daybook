import SwiftUI

/// One plain statement with its provenance immediately underneath. The card
/// never owns a fallback value: only a present `Insight` reaches this view.
struct InsightSection: View {
    let title: String
    let insight: Insight

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
                    Text(title)
                        .font(Tokens.Typography.sectionTitle)
                }

                Text(insight.headline)
                    .font(Tokens.Typography.metricValue)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text("How this is calculated")
                        .font(Tokens.Typography.metadata.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(insight.detail)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(insight.headline). \(insight.detail)")
    }
}
