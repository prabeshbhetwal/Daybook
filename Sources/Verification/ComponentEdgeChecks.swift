import AppKit
import Foundation
import SwiftUI

/// Shared pieces end where their frame ends, so they line up with the text
/// and cards beside them. These break if the goal ring's stroke spills out of
/// its diameter again, a category bar's gaps push it past its width, or a
/// text link pads its words in from the edge it is placed at.
enum ComponentEdgeChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The goal ring is drawn inside its diameter", ringInsideDiameter),
        ("A category bar's gaps fit inside its width", shareBarFits),
        ("A text link's words start where it is placed", linkStartsAtItsEdge),
    ]

    /// Every view is placed this far in from the canvas's top-left corner.
    private static let margin: CGFloat = 20

    private static func ringInsideDiameter() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let diameter: CGFloat = 60
            guard let box = drawnBox(GoalRing(progress: 1, diameter: diameter, lineWidth: 8),
                                     width: 120, height: 120) else { return ["the ring drew nothing"] }
            expect(box.minX >= margin - 1 && box.width <= diameter + 1 && box.height <= diameter + 1,
                   "the ring fits its \(Int(diameter))pt square, drew \(box)", &problems)
            return problems
        }
    }

    private static func shareBarFits() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let width: CGFloat = 300
            let shares = WorkTypeShare.shares(from: [.deepWork: 4, .meetings: 3, .admin: 2, .learning: 1])
            guard let box = drawnBox(CategoryShareBar(shares: shares).frame(width: width),
                                     width: 400, height: 120) else { return ["the bar drew nothing"] }
            expect(box.maxX <= margin + width + 1,
                   "the bar ends within its \(Int(width))pt, drew to \(box.maxX - margin)", &problems)
            return problems
        }
    }

    private static func linkStartsAtItsEdge() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let words = drawnBox(Text("Retry saving").font(Tokens.Typography.label), width: 300, height: 100),
                  let link = drawnBox(Button("Retry saving") {}.buttonStyle(StoryLinkStyle()), width: 300, height: 100)
            else { return ["the link drew nothing"] }
            expect(abs(link.minX - words.minX) <= 1,
                   "the link's words start where plain words do, at \(link.minX) against \(words.minX)", &problems)
            return problems
        }
    }

    /// The rectangle, in points, of everything the view drew, placed
    /// `margin` in from the corner of a canvas of the window's ground colour.
    @MainActor private static func drawnBox<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> CGRect? {
        guard let bitmap = StoryWorkspaceChecks.renderFrame(view.padding(margin), width: width,
                                                            height: height).bitmap,
              let ground = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB) else { return nil }
        let scale = CGFloat(bitmap.pixelsWide) / width
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      abs(colour.redComponent - ground.redComponent) > 0.04
                        || abs(colour.greenComponent - ground.greenComponent) > 0.04
                        || abs(colour.blueComponent - ground.blueComponent) > 0.04 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                      width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }
}
