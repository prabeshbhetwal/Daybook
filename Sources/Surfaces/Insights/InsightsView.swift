import SwiftUI

/// A deliberately sparse canvas. Every section corresponds to one optional in
/// `InsightSurface`; missing facts do not leave empty cards or zero labels.
struct InsightsView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scrolls = true

    private var surface: InsightSurface {
        store.insightSurface(for: navigation.insightRange)
    }

    var body: some View {
        Group {
            if scrolls {
                ScrollView { content }
            } else {
                content.frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Tokens.Colour.ground)
        .onAppear {
            store.setInsightsVisible(true)
            if !store.insightWeekSurface.hasRangeEvidence,
               store.insightMonthSurface.hasRangeEvidence {
                navigation.insightRange = .month
            }
        }
        .onDisappear { store.setInsightsVisible(false) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            header
            if surface.hasEvidence {
                sections
            } else {
                SurfacePanel(showsHeader: false) {
                    EmptyState(InsightSurface.insufficientEvidenceCopy,
                               icon: "sparkles")
                }
                .frame(maxWidth: 620)
            }
        }
        .padding(Tokens.Space.xxl)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Tokens.Space.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Insights")
                    .font(Tokens.Typography.title)
                Text("Only patterns supported by your local record appear here.")
                    .font(Tokens.Typography.detail)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Tokens.Space.l)
            if store.insightsShowsRangeSelector {
                InsightRangePills(selection: $navigation.insightRange)
            }
        }
    }

    private var sections: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 380),
                                      spacing: Tokens.Space.l,
                                      alignment: .top)],
                  alignment: .leading,
                  spacing: Tokens.Space.l) {
            if let pace = surface.pace {
                InsightSection(title: "Pace", insight: pace)
            }
            if let rhythm = surface.rhythm {
                InsightSection(title: "Rhythm", insight: rhythm)
            }
            if let quality = surface.quality {
                InsightSection(title: "Focus quality", insight: quality)
            }
            if let continuity = surface.continuity {
                InsightSection(title: "Continuity", insight: continuity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18),
                   value: navigation.insightRange)
    }
}

private struct InsightRangePills: View {
    @Binding var selection: InsightRange

    var body: some View {
        HStack(spacing: 2) {
            ForEach(InsightRange.allCases, id: \.rawValue) { range in
                Button {
                    selection = range
                } label: {
                    Text(range.title)
                        .font(Tokens.Typography.metadata.weight(.semibold))
                        .padding(.horizontal, Tokens.Space.m)
                        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                        .background(selection == range
                                    ? Tokens.Colour.focus
                                    : Color.clear,
                                    in: Capsule())
                        .foregroundStyle(selection == range
                                         ? Tokens.Colour.onFocus
                                         : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(range.title), "
                                    + (selection == range ? "selected" : "not selected"))
                .accessibilityAddTraits(selection == range ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Tokens.Colour.elevated, in: Capsule())
        .overlay(Capsule().strokeBorder(Tokens.Colour.line))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Insights range")
    }
}

private extension InsightRange {
    var title: String {
        switch self {
        case .week: return "This week"
        case .month: return "This month"
        }
    }
}
