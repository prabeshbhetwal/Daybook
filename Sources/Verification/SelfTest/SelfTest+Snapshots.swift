import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    static func testCompactFocusSnapshotStructure() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []

            let light = Snapshotter.narrowFocusSnapshot(scheme: .light)
            let lightRenderer = ImageRenderer(content: light)
            lightRenderer.scale = 1

            let dark = Snapshotter.narrowFocusSnapshot(scheme: .dark)
            let darkRenderer = ImageRenderer(content: dark)
            darkRenderer.scale = 1

            let blankRenderer = ImageRenderer(
                content: Color.white.frame(width: 1_160, height: 780))
            blankRenderer.scale = 1

            expect(snapshotHasTitleStatusBand(lightRenderer.nsImage),
                   "compact light snapshot root contains title and status evidence", &problems)
            expect(snapshotHasTitleStatusBand(darkRenderer.nsImage),
                   "compact dark snapshot root contains title and status evidence", &problems)
            expect(snapshotHasAppMarkAndTabs(lightRenderer.nsImage),
                   "narrow Focus snapshot keeps the app mark and tab labels together",
                   &problems)
            expect(snapshotHasAppMarkAndTabs(darkRenderer.nsImage),
                   "narrow dark Focus snapshot keeps the app mark and tab labels together",
                   &problems)
            expect(!snapshotHasTitleStatusBand(blankRenderer.nsImage),
                   "the structural probe rejects a root with no title/status band", &problems)
            return problems
        }
    }

    /// Task 11 — the gallery and PNG harness share one explicit product-surface
    /// matrix. This catches a return to fixture-centric output, a missing
    /// Settings group, an appearance omission or a dropped responsive shell.
    static func testSnapshotMatrixCoversEveryMaterialSurface() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let required: [SnapshotScenario] = [
                .focusFirstRun, .focusRunning, .focusPaused, .focusAwaitingDecision,
                .focusSaveFailure,
                .todayHistory, .todayHistoryExpanded,
                .reviewHistorySelection, .historySession, .historySearch, .historyApp, .historySparse,
                .insightsEnough, .insightsEmpty,
                .awardsEarned, .awardsEmpty,
                .storyDay, .storyDayEntry,
                .storyShape, .storyMeeting, .storyLive, .storyDecision, .storyReport,
                .welcomeOpening, .welcomeStep,
                .settingsGeneral, .settingsFocus, .settingsCategories, .settingsAway, .settingsAutomatic,
                .settingsActivityRules, .settingsTracking, .settingsAppearance, .settingsData,
                .settingsUpdates, .settingsAdvanced,
                .activityRuleAmbiguity, .activityRuleAutomatic,
                .awayQuick, .awayFull, .awayQuickFailure, .awayFullFailure, .rewardEarned
            ]

            expect(SnapshotScenario.allCases == required,
                   "snapshot scenarios must equal the approved global surface order",
                   &problems)

            let settingsScenarios = SnapshotScenario.allCases.compactMap(\.settingsSection)
            expect(settingsScenarios == SettingsSection.allCases,
                   "snapshot Settings scenarios must equal every persisted Settings group",
                   &problems)

            let matrix = Set(Snapshotter.matrix)
            let appearances = SnapshotAppearance.allCases
            for scenario in required {
                for appearance in appearances {
                    expect(matrix.contains(where: {
                        $0.scenario == scenario && $0.appearance == appearance
                    }), "\(scenario.rawValue) must render in \(appearance.rawValue)",
                    &problems)
                }
            }

            // Every global tab must own at least one rendered surface, or a
            // whole product area could regress unseen.
            for tab in AppTab.allCases {
                expect(required.contains { $0.tab == tab },
                       "\(tab.rawValue) must have a snapshot scenario", &problems)
            }

            // History's selected-day detail must stay in the visual matrix.
            for scenario in [SnapshotScenario.reviewHistorySelection] {
                expect(required.contains(scenario),
                       "\(scenario.rawValue) must stay in the visual matrix", &problems)
                expect(scenario.tab == .review,
                       "\(scenario.rawValue) must render inside Review", &problems)
            }

            let compactScenarios: Set<SnapshotScenario> = [
                .awayQuick, .awayFull, .awayQuickFailure, .awayFullFailure, .rewardEarned
            ]
            let shellScenarios = required.filter { !compactScenarios.contains($0) }
            for scenario in shellScenarios {
                for appearance in appearances {
                    for presentation in [SnapshotPresentation.minimum,
                                         SnapshotPresentation.comfortable] {
                        expect(matrix.contains(SnapshotRender(
                            scenario: scenario,
                            appearance: appearance,
                            presentation: presentation)),
                        "\(scenario.rawValue) must retain the \(presentation.rawValue) shell",
                        &problems)
                    }
                }
            }

            let focusScenarios = required.filter { $0.tab == .focus }
            for scenario in focusScenarios {
                for appearance in appearances {
                    expect(matrix.contains(SnapshotRender(
                        scenario: scenario,
                        appearance: appearance,
                        presentation: .popover)),
                    "\(scenario.rawValue) must retain the compact popover",
                    &problems)
                }
            }

            for scenario in compactScenarios {
                for appearance in appearances {
                    expect(matrix.contains(SnapshotRender(
                        scenario: scenario,
                        appearance: appearance,
                        presentation: .compact)),
                    "\(scenario.rawValue) must retain its compact production surface",
                    &problems)
                }
            }

            return problems
        }
    }

    /// Gallery cards stay alive together. Constructing a second root must not
    /// rewrite the first root's computed SettingsModel preferences through a
    /// shared UserDefaults domain, before or during a simultaneous render.
    static func testSimultaneousSnapshotsKeepIsolatedPreferences() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let minimum = Snapshotter.view(for: SnapshotRender(
                scenario: .settingsAppearance,
                appearance: .light,
                presentation: .minimum))
            let comfortable = Snapshotter.view(for: SnapshotRender(
                scenario: .settingsAppearance,
                appearance: .dark,
                presentation: .comfortable))

            expect(minimum.settings?.appearancePreference == .light,
                   "the first live Gallery card retains its light preference",
                   &problems)
            expect(minimum.settings?.interfaceDensity == .compact,
                   "the first live Gallery card retains Compact density",
                   &problems)
            expect(comfortable.settings?.appearancePreference == .dark,
                   "the second live Gallery card retains its dark preference",
                   &problems)
            expect(comfortable.settings?.interfaceDensity == .comfortable,
                   "the second live Gallery card retains Comfortable density",
                   &problems)

            let renderer = ImageRenderer(content: HStack(spacing: 0) {
                minimum
                comfortable
            })
            renderer.scale = 1
            expect(renderer.nsImage != nil,
                   "the independently configured Gallery cards render simultaneously",
                   &problems)
            expect(minimum.settings?.appearancePreference == .light
                   && minimum.settings?.interfaceDensity == .compact,
                   "simultaneous rendering cannot overwrite the first card's settings",
                   &problems)
            expect(comfortable.settings?.appearancePreference == .dark
                   && comfortable.settings?.interfaceDensity == .comfortable,
                   "simultaneous rendering cannot overwrite the second card's settings",
                   &problems)
            return problems
        }
    }
}
