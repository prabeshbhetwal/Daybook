import SwiftUI

/// One place on History's path: what it is called, the row it scrolls to,
/// and where the keyboard lands when it is clicked.
struct HistoryCrumb: Equatable, Identifiable {
    let title: String
    let target: String
    let focus: HistoryFocus?
    var id: String { target }
}

/// Where the reader is in History, the way a file browser's path bar says
/// which folder is open: the top period, each open row, and the picked
/// session. Read from what is open rather than from the scroll position, so
/// it holds still while the reader scrolls through a day.
enum HistoryPath {
    /// The headline's scroll id: the top period is not a row of its own.
    static let topID = "history-top"

    static func crumbs(top: HistoryTop, open: [HistoryPlace],
                       session: (thread: UUID, day: Date, title: String)?,
                       today: Date, calendar: Calendar) -> [HistoryCrumb] {
        var crumbs: [HistoryCrumb] = []
        if let place = top.place {
            // A month on top has no year above it to say which one it is.
            let title = place.level == .month
                ? DateFormats.australian("MMMM yyyy", in: calendar.timeZone).string(from: place.start)
                : HistoryRowText.title(place, today: today, calendar: calendar)
            crumbs.append(HistoryCrumb(title: title, target: topID, focus: nil))
        }
        for place in open {
            crumbs.append(HistoryCrumb(title: HistoryRowText.title(place, today: today, calendar: calendar),
                                       target: place.id, focus: .row(place)))
        }
        if let session {
            crumbs.append(HistoryCrumb(title: session.title, target: "session-\(session.thread.uuidString)",
                                       focus: .session(thread: session.thread, day: session.day)))
        }
        return crumbs
    }
}

/// The path drawn: earlier places in grey, the current one in full ink. A
/// place clicked is gone to, and everything under it folds.
struct HistoryPathBar: View {
    let crumbs: [HistoryCrumb]
    let onSelect: (HistoryCrumb) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(crumbs.enumerated()), id: \.element.id) { index, crumb in
                let isCurrent = index == crumbs.count - 1
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                Button(crumb.title) { onSelect(crumb) }
                    .buttonStyle(StoryLinkStyle(tint: isCurrent ? .primary : .secondary))
                    .help("Go to \(crumb.title)")
                    .accessibilityLabel(isCurrent ? "\(crumb.title), current place" : "Go to \(crumb.title)")
            }
        }
        // The first link's padding would push the path off the search field's edge.
        .padding(.leading, -Tokens.Space.s)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Where you are in History")
    }
}
