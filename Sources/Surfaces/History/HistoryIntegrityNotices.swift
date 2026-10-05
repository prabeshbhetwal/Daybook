import SwiftUI

/// What History's rows leave out or cannot vouch for, such as legacy app use
/// or records too long to place on days. Nothing is drawn when there is none.
struct HistoryIntegrityNotices: View {
    let notices: [String]
    let insets: EdgeInsets

    var body: some View {
        if !notices.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                ForEach(notices, id: \.self) { IntegrityNotice($0) }
            }
            .padding(EdgeInsets(top: insets.top, leading: insets.leading, bottom: 0, trailing: insets.trailing))
            .storyRenderEvidence(.historyIntegrityNotice)
        }
    }
}
