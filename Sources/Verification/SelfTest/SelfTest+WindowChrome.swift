import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// The official Away cases must exercise the hosted production wrappers,
    /// not an answer grid restyled inside Snapshotter. The quick pointer and
    /// full-screen click-catcher/Later row are observable raster structure.
    static func testAwaySnapshotsRetainProductionPromptChrome() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let quickRenderer = ImageRenderer(content: Snapshotter.view(for: SnapshotRender(
                scenario: .awayQuick,
                appearance: .light,
                presentation: .compact)))
            quickRenderer.scale = 1
            let fullRenderer = ImageRenderer(content: Snapshotter.view(for: SnapshotRender(
                scenario: .awayFull,
                appearance: .light,
                presentation: .compact)))
            fullRenderer.scale = 1

            guard let quick = snapshotBitmap(quickRenderer.nsImage),
                  let full = snapshotBitmap(fullRenderer.nsImage) else {
                return ["Away production roots did not render"]
            }

            expect(quick.pixelsWide == 300 && (218...224).contains(quick.pixelsHigh),
                   "quick Away includes its 9pt pointer above the 300pt card; got "
                   + "\(quick.pixelsWide)x\(quick.pixelsHigh)", &problems)
            expect(snapshotOpaqueColumns(quick, row: 0) <= 24,
                   "quick Away begins with the narrow production pointer",
                   &problems)

            expect(full.pixelsWide == 760 && full.pixelsHigh == 620,
                   "full Away uses its safe full-prompt host; got "
                   + "\(full.pixelsWide)x\(full.pixelsHigh)", &problems)
            expect((0.10...0.30).contains(snapshotAlpha(full, x: 4, y: 4)),
                   "full Away retains the dimmed outside click-catcher",
                   &problems)
            expect(snapshotContrast(full, x: 570..<620, y: 425..<455) > 0.05,
                   "full Away retains visible trailing Later/Escape chrome",
                   &problems)
            return problems
        }
    }

    @MainActor static func snapshotBitmap(_ image: NSImage?) -> NSBitmapImageRep? {
        guard let image, let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }

    @MainActor static func snapshotAlpha(
        _ bitmap: NSBitmapImageRep,
        x: Int,
        y: Int
    ) -> Double {
        guard x >= 0, x < bitmap.pixelsWide, y >= 0, y < bitmap.pixelsHigh,
              let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
            return 0
        }
        return Double(colour.alphaComponent)
    }

    @MainActor static func snapshotOpaqueColumns(
        _ bitmap: NSBitmapImageRep,
        row: Int
    ) -> Int {
        (0..<bitmap.pixelsWide).reduce(into: 0) { count, column in
            if snapshotAlpha(bitmap, x: column, y: row) > 0.05 { count += 1 }
        }
    }

    @MainActor static func snapshotContrast(
        _ bitmap: NSBitmapImageRep,
        x: Range<Int>,
        y: Range<Int>
    ) -> Double {
        var low = 1.0
        var high = 0.0
        for row in y where row >= 0 && row < bitmap.pixelsHigh {
            for column in x where column >= 0 && column < bitmap.pixelsWide {
                guard let colour = bitmap.colorAt(x: column, y: row)?
                    .usingColorSpace(.sRGB) else { continue }
                let luminance = 0.2126 * Double(colour.redComponent)
                    + 0.7152 * Double(colour.greenComponent)
                    + 0.0722 * Double(colour.blueComponent)
                low = min(low, luminance)
                high = max(high, luminance)
            }
        }
        return high - low
    }

    @MainActor static func snapshotHasTitleStatusBand(_ image: NSImage?) -> Bool {
        guard let image, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              bitmap.pixelsWide >= 720, bitmap.pixelsHigh >= 120 else { return false }

        func contrast(x: Range<Int>, y: Range<Int>) -> Double {
            var low = 1.0
            var high = 0.0
            for row in stride(from: y.lowerBound, to: y.upperBound, by: 2) {
                for column in stride(from: x.lowerBound, to: x.upperBound, by: 2) {
                    guard let colour = bitmap.colorAt(x: column, y: row)?
                        .usingColorSpace(.sRGB) else { continue }
                    let luminance = 0.2126 * Double(colour.redComponent)
                        + 0.7152 * Double(colour.greenComponent)
                        + 0.0722 * Double(colour.blueComponent)
                    low = min(low, luminance)
                    high = max(high, luminance)
                }
            }
            return high - low
        }

        // NSBitmapImageRep's row zero is the rendered top. These disjoint
        // regions cover the left title/app mark and right live-status text;
        // the tab rail is centred lower down and cannot satisfy either probe.
        let bandHeight = min(60, bitmap.pixelsHigh)
        let sideWidth = min(360, bitmap.pixelsWide / 2)
        // The story's chrome leads with its date control, centred; whatever
        // stands left of the status region must carry the title evidence.
        let titleContrast = contrast(x: 10..<(bitmap.pixelsWide - sideWidth), y: 0..<bandHeight)
        let statusContrast = contrast(
            x: (bitmap.pixelsWide - sideWidth)..<(bitmap.pixelsWide - 10),
            y: 0..<bandHeight)
        return titleContrast > 0.2 && statusContrast > 0.08
    }

    @MainActor static func snapshotHasAppMarkAndTabs(_ image: NSImage?) -> Bool {
        guard let image, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              bitmap.pixelsWide == 980, bitmap.pixelsHigh >= 680 else { return false }

        func contrast(x: Range<Int>, y: Range<Int>) -> Double {
            var low = 1.0
            var high = 0.0
            for row in stride(from: y.lowerBound, to: y.upperBound, by: 2) {
                for column in stride(from: x.lowerBound, to: x.upperBound, by: 2) {
                    guard let colour = bitmap.colorAt(x: column, y: row)?
                        .usingColorSpace(.sRGB) else { continue }
                    let luminance = 0.2126 * Double(colour.redComponent)
                        + 0.7152 * Double(colour.greenComponent)
                        + 0.0722 * Double(colour.blueComponent)
                    low = min(low, luminance)
                    high = max(high, luminance)
                }
            }
            return high - low
        }

        // The story's chrome is its date control, centred in the 60pt band at
        // the production minimum, with History and the session control to its
        // right; the story has no scope row to the left any more.
        return contrast(x: 300..<700, y: 0..<60) > 0.08
            && contrast(x: 700..<970, y: 0..<60) > 0.08
    }

    /// The visual foundation keeps Compact practical rather than cramped and
    /// resolves semantic signals independently of the current system appearance.
    static func testWarmPrecisionDesignTokensAndDensity() -> [String] {
        var problems: [String] = []
        expect(InterfaceDensity.compact.layout.rowHeight >= 28,
               "compact targets remain practical", &problems)
        expect(InterfaceDensity.compact.layout.rowHeight < InterfaceDensity.comfortable.layout.rowHeight,
               "compact density is observably denser", &problems)
        expect(Tokens.Colour.resolved(.focus, dark: false).hex == 0x007AFF,
               "light focus token is Apple's system blue", &problems)
        expect(Tokens.Colour.resolved(.focus, dark: true).hex == 0x0A84FF,
               "dark focus token is the dark system blue", &problems)
        expect(Tokens.Colour.resolved(.attention, dark: true).hex == 0xFF9F0A,
               "dark attention token remains semantic amber", &problems)
        let lightOnFocus = Tokens.Colour.resolved(.onFocus, dark: false).hex
        let darkOnFocus = Tokens.Colour.resolved(.onFocus, dark: true).hex
        expect(lightOnFocus == 0x0F1115 && darkOnFocus == 0x0F1115,
               "on-focus foreground remains near-black in both appearances", &problems)
        let lightContrast = contrastRatio(lightOnFocus, 0x007AFF)
        expect(lightContrast >= 4.5,
               "on-focus foreground has at least 4.5:1 contrast on light focus; got "
               + String(format: "%.2f:1", lightContrast), &problems)
        return problems
    }

    /// Deep links and commands share one navigation model. A wrong branch here
    /// would leave what is showing and the requested day disagreeing.
    static func testMainWindowRoutesAndCommands() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let navigation = MainWindowModel()
            let calendar = Calendar.current
            let yesterday = base.addingTimeInterval(-24 * 3_600)

            navigation.open(tab: .review)
            expect(navigation.workspace == .history && navigation.sheet == nil,
                   "review route shows History", &problems)
            navigation.openToday(date: yesterday)
            expect(navigation.workspace == .story && navigation.requestedDate == yesterday,
                   "day links route into the day's story", &problems)
            navigation.openSettings()
            expect(navigation.sheet == .settings,
                   "command-comma routes to Settings", &problems)

            // Selecting a day in Review is inspection, not navigation: only the
            // explicit action may move the user to another tab.
            let reviewNavigation = MainWindowModel(opening: .review)
            reviewNavigation.openHistory(day: yesterday)
            expect(reviewNavigation.workspace == .history,
                   "selecting a Review day keeps History showing", &problems)
            expect(calendar.isDate(reviewNavigation.reviewSelectedDate ?? base,
                                   inSameDayAs: yesterday),
                   "Review stores the literal selected local day", &problems)
            expect(reviewNavigation.requestedDate == nil,
                   "Review selection does not change Today scope", &problems)
            reviewNavigation.foldDeepestHistory()
            expect(reviewNavigation.reviewSelectedDate == nil,
                   "closing the Review detail clears its selected day", &problems)
            return problems
        }
    }

    /// The unified chrome is a pure layout contract: contextual title/status
    /// share the tab row, native traffic lights have reserved space, and the
    /// rail does not rely on AppKit's conspicuous focus outline.
    static func testUnifiedWindowChrome() -> [String] {
        var problems: [String] = []
        let context = MainWindowChrome.context(
            tab: .today,
            state: .running,
            threadElapsed: 21 * 60,
            todayTotal: 2 * 3_600
        )

        expect(context.title == "Today", "chrome exposes the selected tab title", &problems)
        expect(context.subtitle == "Daybook",
               "chrome keeps the app name beside the tabs", &problems)
        expect(context.status == "Focus active · 21m",
               "chrome keeps the literal live status beside the tabs", &problems)
        expect(MainWindowChrome.trafficLightClearance >= 68,
               "chrome reserves room for native traffic lights", &problems)
        return problems
    }
}
