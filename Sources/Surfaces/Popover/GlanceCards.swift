import SwiftUI

/// The scrolling middle of the popover: today's timeline, then top apps and
/// continue-today side by side when the panel is wide, stacked when narrow.
struct GlanceCards: View {
    @ObservedObject var store: SessionStore
    let metrics: PopoverMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.stackSpacing) {
            timelineCard
            if metrics.twoColumn {
                HStack(alignment: .top, spacing: metrics.stackSpacing) {
                    topAppsCard.frame(maxWidth: .infinity, alignment: .topLeading)
                    continueCard.frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                topAppsCard
                continueCard
            }
        }
    }

    private var cardPadding: CGFloat { metrics.dense ? Tokens.Space.m : Tokens.Space.l }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            SectionHeader(title: "Today")
            DayTimelineView(store: store, compact: true, layoutOverride: store.glanceLayout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: cardPadding)
        .explains("timeline", "Your day, left to right",
                  "Each coloured block is a stretch in one app, in the order it "
                  + "happened. Colours match the app list. Empty space is time away "
                  + "from the Mac. A wide block means a long unbroken stretch; lots of "
                  + "thin stripes means you were switching often.")
    }

    private var topAppsCard: some View {
        Group {
            if store.glanceApps.isEmpty {
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    SectionHeader(title: "Top apps")
                    Text("Tracking starts when you switch apps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                TopAppsList(apps: Array(store.glanceApps.prefix(metrics.topAppCount)),
                            sessionsToday: store.sessionsToday,
                            compact: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: cardPadding)
        .explains("topApps", "Where your time went",
                  "Each row is one app: how long it was the window in front today, and "
                  + "what share of your app time that was. Leaving an app and coming "
                  + "back adds to the same row. The share is out of your tracked app "
                  + "time, not out of the whole day.")
    }

    private var continueCard: some View {
        ContinueTodaySection(store: store, limit: store.menuSessionCount)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: cardPadding)
            .explains("continue", "Pick up where you left off",
                      "Work you were doing in the last few hours. Choosing one carries on "
                      + "with that same piece of work instead of beginning a new one, so "
                      + "an afternoon split by lunch still reads as one job.")
    }
}
