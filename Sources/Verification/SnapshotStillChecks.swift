import SwiftUI
import AppKit

/// A snapshot is the same image however many times it is taken: nothing in it
/// depends on the moment the still was taken, how quickly the view settled,
/// whether a field had taken focus, a list still loading, the scroller style
/// or a scratch folder's random name.
enum SnapshotStillChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A still of History's search field reads the same whenever it is taken",
         findFieldHoldsStill),
        ("A still waits for a change that lands just after the view appears",
         stillWaitsForLateChange),
        ("Every settings snapshot names the same data folder", settingsFolderIsStable),
        ("A settings snapshot names a rule's apps from its first frame", settingsAppsAreNamed),
        ("A still never shows a text field taking focus", stillRefusesTextFocus),
        ("Stills ask AppKit for overlay scrollers whatever is attached", stillScrollersAreOverlay),
        ("The welcome's ring holds its first breath in a still that settles slowly", coachRingHoldsStill),
        ("Taking stills does not keep the frames drawn while they settle", stillsReleaseFrames),
        ("A rendered still never asks the live model for a review note", stillNotesSkipModel),
    ]

    private static func findFieldHoldsStill() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            // Names and apps, so the field has examples to rotate through.
            let store = FixtureFactory.insightsStore(withEvidence: true)
            defer { FixtureFactory.cleanUp() }
            let bar = HistoryFindBar(store: store, focusRequest: 0).frame(width: 640)
            let first = Snapshotter.stillPNG(of: bar, appearance: .light)
            // Past the next example's turn, so a rotating field shows another.
            let period = HistoryFindBar.exampleSeconds
            let now = Date().timeIntervalSinceReferenceDate
            let turn = (now / period).rounded(.down) * period + period
            RunLoop.current.run(until: Date(timeIntervalSinceReferenceDate: turn + 0.2))
            let second = Snapshotter.stillPNG(of: bar, appearance: .light)
            expect(first != nil && first == second,
                   "two stills of the search field, \(period) s apart, differ "
                       + "(\(first?.count ?? 0) vs \(second?.count ?? 0) bytes)", &problems)
            return problems
        }
    }

    private static func stillWaitsForLateChange() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let late = Snapshotter.stillPNG(of: LateChange(), appearance: .light)
            let settled = Snapshotter.stillPNG(of: LateChange.after.frame(width: 20, height: 20),
                                               appearance: .light)
            expect(late != nil && late == settled,
                   "a still taken as the view appeared missed its change 80 ms later", &problems)
            return problems
        }
    }

    private static func settingsFolderIsStable() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            defer { FixtureFactory.cleanUp() }
            let item = SnapshotRender(scenario: .settingsData, appearance: .light, presentation: .minimum)
            let first = Snapshotter.view(for: item).settings?.dataDirectoryURL
            let second = Snapshotter.view(for: item).settings?.dataDirectoryURL
            expect(first != nil && first == second,
                   "two settings snapshots named \(first?.path ?? "none") and \(second?.path ?? "none")",
                   &problems)
            return problems
        }
    }

    private static func settingsAppsAreNamed() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            defer { FixtureFactory.cleanUp() }
            let item = SnapshotRender(scenario: .settingsActivityRules, appearance: .light,
                                      presentation: .minimum)
            let names = Snapshotter.view(for: item).settings?.installedAppCatalog.applications.map(\.name) ?? []
            expect(names.contains("Example Code"),
                   "the settings card's app list was not loaded before drawing (names \(names))", &problems)
            return problems
        }
    }

    private static func stillRefusesTextFocus() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let asked = Snapshotter.stillPNG(of: FocusRequest(asks: true), appearance: .light)
            let unasked = Snapshotter.stillPNG(of: FocusRequest(asks: false), appearance: .light)
            expect(asked != nil && asked == unasked,
                   "a field that asked for focus as it appeared was drawn focused", &problems)
            return problems
        }
    }

    private static func stillScrollersAreOverlay() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let saved = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            defer { UserDefaults.standard.setVolatileDomain(saved, forName: UserDefaults.argumentDomain) }
            // AppKit reads the setting once, as it starts (probed 11 October
            // 2026), so a process already drawing can only check what is read.
            Snapshotter.pinStillScrollers()
            let shown = UserDefaults.standard.string(forKey: "AppleShowScrollBars")
            expect(shown == "WhenScrolling",
                   "stills left AppKit to choose its scrollers (AppleShowScrollBars \(shown ?? "unset"))",
                   &problems)
            return problems
        }
    }

    private static func coachRingHoldsStill() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let breathing = Snapshotter.stillPNG(of: SlowCoachRing(animated: true), appearance: .light)
            let still = Snapshotter.stillPNG(of: SlowCoachRing(animated: false), appearance: .light)
            expect(breathing != nil && breathing == still,
                   "a still taken after the ring's breath was due drew it mid-breath", &problems)
            return problems
        }
    }

    private static func stillsReleaseFrames() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            _ = Snapshotter.stillPNG(of: Shifting(), appearance: .light)
            let before = footprint()
            for _ in 0..<3 { _ = Snapshotter.stillPNG(of: Shifting(), appearance: .light) }
            let grown = (footprint() - before) / 1_048_576
            // About 25 frames of 4 MB a still: kept, three stills hold 300 MB.
            expect(grown < 64, "three stills kept \(grown) MB after they were taken", &problems)
            return problems
        }
    }

    private static func stillNotesSkipModel() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            Snapshotter.rendersStills = true
            defer { Snapshotter.rendersStills = false; FixtureFactory.cleanUp() }
            let store = Snapshotter.store(for: .focusPaused)
            let navigation = Snapshotter.navigation(for: .focusPaused, store: store)
            expect(navigation.notes?.responder != nil,
                   "a rendered still left its review notes to the live model", &problems)
            return problems
        }
    }

    private static func footprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }
}

/// A large view whose shade changes every 50 ms for 1.2 s, so a still of it
/// draws some 25 frames before it settles.
private struct Shifting: View {
    @State private var step = 0

    var body: some View {
        Color(white: Double(step) / 24)
            .frame(width: 1_200, height: 900)
            .onAppear {
                for next in 1...24 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(next)) { step = next }
                }
            }
    }
}

/// The welcome's ring beside a mark that changes every 0.1 s for 0.6 s. A
/// still settles after 0.15 s without change, so this one is taken after the
/// ring's first breath (0.4 s) was due.
private struct SlowCoachRing: View {
    let animated: Bool
    @State private var step = 0

    var body: some View {
        HStack {
            CoachRing(rect: CGRect(x: 30, y: 30, width: 60, height: 30),
                      bounds: CGRect(x: 0, y: 0, width: 120, height: 90), animated: animated)
                .frame(width: 120, height: 90)
            Color(white: Double(step) / 6)
                .frame(width: 20, height: 20)
        }
        .onAppear {
            for next in 1...6 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 * Double(next)) { step = next }
            }
        }
    }
}

/// A field that asks for focus a turn after it appears, the way Ask's does,
/// beside a mark that shows whether it got it.
private struct FocusRequest: View {
    let asks: Bool
    @FocusState private var focused: Bool
    @State private var text = ""

    var body: some View {
        HStack {
            TextField("Question", text: $text)
                .focused($focused)
                .frame(width: 120)
            (focused ? Color(red: 0, green: 1, blue: 0) : Color(red: 1, green: 0, blue: 0))
                .frame(width: 20, height: 20)
        }
        .padding(8)
        .onAppear {
            guard asks else { return }
            DispatchQueue.main.async { focused = true }
        }
    }
}

/// Red as it appears, green 80 ms later: longer than the fixed wait a still
/// once took, shorter than the wait for the image to stop changing.
private struct LateChange: View {
    static let after = Color(red: 0, green: 1, blue: 0)
    @State private var changed = false

    var body: some View {
        (changed ? Self.after : Color(red: 1, green: 0, blue: 0))
            .frame(width: 20, height: 20)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { changed = true }
            }
    }
}
