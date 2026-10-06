import SwiftUI

/// Where the picked app was in front along one session: the session as a
/// well, the app's moments marked on it. The card and the rail draw the same
/// bar from the same figures.
struct HistoryAppMomentsBar: View {
    let use: HistoryAppLens.SessionUse

    var body: some View {
        let length = max(use.span.duration, 1)
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(StoryStyle.well)
                ForEach(Array(use.moments.enumerated()), id: \.offset) { _, moment in
                    Rectangle()
                        .fill(Tokens.Palette.app(rank: 1))
                        .frame(width: max(2, geometry.size.width * moment.duration / length))
                        .offset(x: geometry.size.width * moment.start.timeIntervalSince(use.span.start) / length)
                }
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}
