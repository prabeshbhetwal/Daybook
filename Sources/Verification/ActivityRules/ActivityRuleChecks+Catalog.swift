import Foundation
import SwiftUI
import AppKit

extension ActivityRuleChecks {
    /// One mutable value shared across the worker boundary. The semaphore
    /// below orders every write before the read.
    final class Box {
        var flag = false
        var failures: [String] = []
    }

    /// The catalogue's Spotlight supplement is delivered through the run loop
    /// of whichever thread starts it — a GCD worker in production, which owns
    /// a run loop but never runs it. This proves the wait actually turns that
    /// loop, which a blocking wait cannot do, and that an unmet wait still
    /// honours its budget. It uses a synthetic run-loop delivery; no live
    /// Spotlight query is started and the user's applications are never
    /// enumerated.
    static func catalogRunLoopWait() -> [String] {
        let box = Box()
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue(label: "fc.catalog.runloop.check").async {
            // Only a turning run loop can ever execute this block.
            RunLoop.current.perform { box.flag = true }
            let satisfied = InstalledAppCatalog.turnRunLoop(until: { box.flag }, timeout: 2)
            if !satisfied || !box.flag {
                box.failures.append("A run-loop delivery never arrived on a worker thread")
            }

            let start = Date()
            let unmet = InstalledAppCatalog.turnRunLoop(until: { false }, timeout: 0.2)
            let elapsed = Date().timeIntervalSince(start)
            if unmet {
                box.failures.append("An unmet condition reported success")
            }
            if elapsed > 1.5 {
                box.failures.append("An unmet wait overran its budget by \(elapsed - 0.2)s")
            }
            finished.signal()
        }
        guard finished.wait(timeout: .now() + 15) == .success else {
            return ["The run-loop wait never returned"]
        }
        return box.failures
    }

    final class CountBox { var value = 0 }

    /// The picker's rows are SwiftUI-only, so no NSView walk can see them —
    /// counting `NSButton` descendants returns zero however many applications
    /// are published. The production row-count preference is read instead, which
    /// proves a row exists for each application rather than only that a scroll
    /// region appeared. The catalogue is injected; no application is enumerated.
    static func pickerRows() -> [String] {
        MainActor.assumeIsolated {
            @MainActor func render(_ count: Int, query: String = "") -> Int {
                let apps = (0..<count).map {
                    InstalledApplication(bundleID: "com.example.app\($0)",
                                         name: "Application \($0)", url: nil)
                }
                let catalog = InstalledAppCatalog(discoverStandard: { apps },
                                                  discoverSpotlight: { [] }, observed: { [] })
                catalog.refresh()
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                let queryBox = TextBox(); queryBox.text = query
                let rows = CountBox()
                let view = InstalledAppPicker(
                    catalog: catalog,
                    query: Binding(get: { queryBox.text }, set: { queryBox.text = $0 }),
                    selection: Binding(get: { Set<String>() }, set: { _ in }))
                    .frame(width: 520, height: 400)
                    .onPreferenceChange(InstalledAppRowCountKey.self) { rows.value = $0 }
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(x: 0, y: 0, width: 520, height: 400)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                                      backing: .buffered, defer: false)
                window.contentView = host
                window.makeKeyAndOrderFront(nil)
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                host.layoutSubtreeIfNeeded()
                window.orderOut(nil); window.contentView = nil
                return rows.value
            }
            var failures: [String] = []
            let empty = render(0)
            if empty != 0 {
                failures.append("An empty catalogue still rendered \(empty) picker rows")
            }
            // Four rows fit the picker's own 220-point viewport, so every
            // published application must appear.
            let four = render(4)
            if four != 4 {
                failures.append("Four published applications rendered \(four) rows")
            }
            // Eight exceed the viewport. The list is lazy by design, so more
            // rows must appear than for four, and never more than were published.
            let eight = render(8)
            if eight <= four || eight > 8 {
                failures.append("Eight published applications rendered \(eight) rows, "
                    + "outside the expected \(four + 1)...8")
            }
            let filtered = render(8, query: "Application 3")
            if filtered != 1 {
                failures.append("Searching one application name rendered \(filtered) rows")
            }
            return failures
        }
    }

    static func catalogDiscovery() -> [String] {
        let duplicateA = InstalledApplication(bundleID: "COM.Example.Code", name: "Code", url: nil)
        let duplicateB = InstalledApplication(bundleID: "com.example.code", name: "Visual Studio Code", url: nil)
        let missing = InstalledApplication(bundleID: "com.example.missing", name: "Old App", url: nil,
                                           isInstalled: false)
        let catalog = InstalledAppCatalog(discoverStandard: { [duplicateA] },
                                          discoverSpotlight: { [duplicateB] },
                                          observed: { [missing] })
        let result = catalog.discoverSynchronouslyForVerification()
        var failures: [String] = []
        if result.map(\.bundleID) != ["com.example.code", "com.example.missing"] {
            failures.append("Injected catalog sources were not stably deduplicated")
        }
        if result.last?.displayName != "Old App — Missing" {
            failures.append("Missing observed application lacked an honest label")
        }
        return failures
    }
}
