import Foundation
import SwiftUI
import AppKit

extension ActivityRuleChecks {
    /// Both compact surfaces must render the quiet choice when one is pending
    /// and omit it otherwise. The proof is the production branch's own render
    /// evidence: SwiftUI-only elements never appear to an in-process
    /// accessibility walk (an NSHostingView reports zero AX children), so a
    /// label search cannot observe this content either way.
    static func quietChoiceConsumers() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.activityRuleStore(ambiguous: true)
            defer { FixtureFactory.cleanUp() }
            guard let pending = store.pendingActivityChoice else {
                return ["Ambiguous fixture did not present a quiet activity choice"]
            }
            let settings = SettingsModel(store: store.engine.store, isTrackingEnabled: true,
                onChange: {}, onTrackingChanged: { _ in },
                installedAppCatalog: FixtureFactory.installedAppCatalog())
            var failures: [String] = []

            func surfaces() -> [(String, AnyView, CGFloat)] {
                [("The line under the chrome",
                  AnyView(SessionUnderline(store: store)), 900),
                 ("Menu panel",
                  AnyView(PopoverView(store: store, settings: settings,
                      metricsOverride: PopoverMetrics.fitting(CGSize(width: 1_000, height: 680)),
                      scrolls: false)), 380)]
            }

            for (label, view, width) in surfaces() {
                let evidence = renderEvidence(view, width: width, height: 720)
                if !evidence.contains(.activityQuietChoice) {
                    failures.append("\(label) omitted the quiet activity choice")
                }
            }

            store.presentActivityChoice(nil)
            for (label, view, width) in surfaces() {
                let evidence = renderEvidence(view, width: width, height: 720)
                if evidence.contains(.activityQuietChoice) {
                    failures.append("\(label) rendered a quiet choice with none pending")
                }
            }
            store.presentActivityChoice(pending)
            return failures
        }
    }

    /// Renders offscreen and returns the production evidence preferences the
    /// tree reported. Mirrors the Story workspace proof so the two suites
    /// prove content the same way.
    @MainActor static func renderEvidence(_ view: AnyView, width: CGFloat,
                                                  height: CGFloat) -> Set<StoryRenderEvidence> {
        final class Box { var values: Set<StoryRenderEvidence> = [] }
        let box = Box()
        let framed = view.frame(width: width, height: height, alignment: .topLeading)
            .background(Tokens.Colour.ground)
            .onPreferenceChange(StoryRenderEvidenceKey.self) { box.values = $0 }
        let host = NSHostingView(rootView: framed)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        host.displayIfNeeded()
        window.orderOut(nil)
        window.close()
        return box.values
    }

    static func editorConsumer() -> [String] {
        MainActor.assumeIsolated {
            let state = ActivityRuleEditorState()
            state.beginNew(); state.name = "Coding"; state.bundleIDs = ["com.example.code"]
            state.dwell = -1; state.customDwell = "30.5"
            var failures: [String] = []
            if state.ruleForSaving() != nil || state.validationMessage == nil {
                failures.append("Editor accepted a fractional custom dwell without a visible error")
            }
            let suite = "com.prabesh.daybook.rule-editor.\(UUID().uuidString)"
            let defaults = MemoryDefaults.suite(named: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let persistence = PersistenceStore(defaults: defaults)
            persistence.removeAll()
            persistence.activityRules = [rule(codingID, "Coding", 180, ["com.example.code"])]
            var discoveries = 0
            let catalog = InstalledAppCatalog(discoverStandard: {
                discoveries += 1
                return (0..<40).map { InstalledApplication(
                    bundleID: "com.example.app\($0)", name: "Application \($0)", url: nil) }
            }, discoverSpotlight: { discoveries += 1; return [] },
               observed: { discoveries += 1; return [] })
            let model = SettingsModel(store: persistence, isTrackingEnabled: true,
                onChange: {}, onTrackingChanged: { _ in }, installedAppCatalog: catalog)
            let host = NSHostingView(rootView: ActivityRulesView(model: model)
                .frame(width: 680, height: 500))
            host.frame = NSRect(x: 0, y: 0, width: 680, height: 500)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            host.layoutSubtreeIfNeeded()
            // Nothing under the list until a rule is chosen: the form's app
            // picker is the page's only scroll region, so its absence says the
            // form stayed closed on arrival.
            if descendantCount(NSScrollView.self, in: host) != 0 {
                failures.append("The rule form opened on arrival, before any rule was chosen")
            }
            if discoveries != 3 {
                failures.append("Fixture editor did not use only its three injected discovery sources")
            }
            let opened = ActivityRuleEditorState()
            opened.edit(persistence.activityRules[0])
            let form = NSHostingView(rootView: ActivityRuleForm(model: model, editor: opened)
                .frame(width: 680, height: 500))
            form.frame = NSRect(x: 0, y: 0, width: 680, height: 500)
            form.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            form.layoutSubtreeIfNeeded()
            if descendantCount(NSScrollView.self, in: form) < 1 {
                failures.append("Long installed-app picker did not render a genuine scroll region")
            }
            return failures
        }
    }

    @MainActor static func descendantCount<T: NSView>(_ type: T.Type,
                                                               in view: NSView) -> Int {
        (view is T ? 1 : 0) + view.subviews.reduce(0) { $0 + descendantCount(type, in: $1) }
    }
}
