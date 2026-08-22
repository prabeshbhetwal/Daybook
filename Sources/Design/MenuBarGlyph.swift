import SwiftUI
import AppKit

/// The status item's ring: the day's goal progress, drawn as a 16pt template
/// image so it takes the menu bar's own tint. Rasterised on demand inside the
/// existing tick — the label view re-evaluates whenever `elapsed` or `goal`
/// publishes, which is what drives this — so there is no timer here.
enum MenuBarGlyph {

    private struct Ring: View {
        let progress: Double
        let paused: Bool
        let attention: Bool
        let isMet: Bool

        var body: some View {
            ZStack {
                Circle().stroke(Color.black.opacity(0.28), lineWidth: 2.2)
                Circle()
                    .trim(from: 0, to: min(1, max(0, progress)))
                    .stroke(Color.black, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if isMet {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.black)
                } else if paused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 6.5, weight: .heavy))
                        .foregroundStyle(.black)
                }
                if attention {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 5, height: 5)
                        .offset(x: 5.5, y: -5.5)
                }
            }
            .frame(width: 16, height: 16)
            .padding(1)
        }
    }

    @MainActor
    static func image(progress: Double, paused: Bool, attention: Bool,
                      isMet: Bool) -> NSImage? {
        let renderer = ImageRenderer(content: Ring(progress: progress, paused: paused,
                                                   attention: attention, isMet: isMet))
        renderer.scale = 2
        guard let image = renderer.nsImage else { return nil }
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }
}
