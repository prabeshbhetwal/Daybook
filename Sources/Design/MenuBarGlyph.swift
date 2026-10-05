import SwiftUI
import AppKit

/// The status item's ring: the day's goal progress, drawn as a 16pt template
/// image so it takes the menu bar's own tint. Rasterised on demand when the
/// label's `MenuBarDisplay` changes — there is no timer here — and kept, so a
/// state already drawn is never drawn twice.
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
                        .font(Tokens.Typography.fitted(7, weight: .heavy))
                        .foregroundStyle(.black)
                } else if paused {
                    Image(systemName: "pause.fill")
                        .font(Tokens.Typography.fitted(6.5, weight: .heavy))
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

    private struct Key: Hashable {
        let progress: Double
        let paused: Bool
        let attention: Bool
        let isMet: Bool
    }

    /// Rendered rings by exact input. The status item hands the same image
    /// back while nothing it shows has changed, so AppKit has nothing to
    /// redraw; a handful of entries covers every state a day passes through.
    @MainActor private static var cache: [Key: NSImage] = [:]
    private static let cacheLimit = 32

    @MainActor
    static func image(progress: Double, paused: Bool, attention: Bool,
                      isMet: Bool) -> NSImage? {
        let key = Key(progress: progress, paused: paused, attention: attention, isMet: isMet)
        if let cached = cache[key] { return cached }
        guard let image = render(progress: progress, paused: paused,
                                 attention: attention, isMet: isMet) else { return nil }
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[key] = image
        return image
    }

    @MainActor
    private static func render(progress: Double, paused: Bool, attention: Bool,
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
