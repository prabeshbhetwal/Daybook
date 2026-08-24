import SwiftUI

/// Four tabs of grouped forms. The explanatory copy that used to crowd the
/// popover lives here as footers, where it has room to be read.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            goal.tabItem { Label("Goal", systemImage: "target") }
            away.tabItem { Label("Away and breaks", systemImage: "moon.zzz") }
            automatic.tabItem { Label("Automatic", systemImage: "wand.and.stars") }
            display.tabItem { Label("Display", systemImage: "macwindow") }
        }
        .frame(width: 480)
        .frame(minHeight: 300)
    }

    private var goal: some View {
        Form {
            Section {
                Picker("Daily goal", selection: $model.dailyGoal) {
                    ForEach(FocusConstants.dailyGoalOptions, id: \.self) {
                        Text(Tokens.duration($0)).tag($0)
                    }
                }
            } footer: {
                Text("Counts only focus sessions while you were actually using the Mac. "
                     + "Your usual pace compares today with the same hour on your last "
                     + "\(FocusConstants.goalMedianWindowDays) working days.")
            }
        }
        .formStyle(.grouped)
    }

    private var away: some View {
        Form {
            Section {
                Picker("Ask me after", selection: $model.breakThreshold) {
                    ForEach(FocusConstants.thresholdOptions, id: \.self) {
                        Text(Tokens.duration($0)).tag($0)
                    }
                }
                Picker("End session after", selection: $model.longAwayCap) {
                    ForEach(FocusConstants.longAwayCapOptions, id: \.self) {
                        Text(Tokens.duration($0)).tag($0)
                    }
                }
                Picker("Full-screen prompt after", selection: $model.fullPromptAfter) {
                    ForEach(FocusConstants.fullPromptAfterOptions, id: \.self) {
                        Text(Tokens.duration($0)).tag($0)
                    }
                    Text("Never").tag(0.0)
                }
            } header: {
                Text("Stepping away")
            } footer: {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text("Under 5 seconds is ignored. Up to "
                         + "\(Tokens.duration(model.breakThreshold)) is left out of the session "
                         + "without interrupting you. Up to \(Tokens.duration(model.longAwayCap)) "
                         + "you are asked what it was, whether the screen locked or you simply "
                         + "stopped. Past that the session ends where you left.")
                    Text(model.fullPromptAfter > 0
                         ? "Shorter absences are asked about from the menu bar; from "
                           + "\(Tokens.duration(model.fullPromptAfter)) the question fills the screen."
                         : "Every absence is asked about from the menu bar.")
                    Text("Pressing Away is never asked about. Back within "
                         + "\(Tokens.duration(model.breakThreshold)) the same stretch carries on; "
                         + "back later, the stretch ended where you left, the gap is written "
                         + "down as Away, and a new stretch starts when you return.")
                    Text("Quiet in front of something you are watching — a video, a call, a "
                         + "presentation keeping the screen awake — is never an absence, so it is "
                         + "never asked about. In a Meetings or Learning session it counts; in any "
                         + "other it pauses the clock quietly and appears as Watching.")
                }
            }
            Section {
                Toggle("Remind me to take breaks", isOn: $model.remindersEnabled)
            } header: {
                Text("Breaks")
            } footer: {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    ForEach(BreakTier.allCases, id: \.rawValue) { tier in
                        Text("\(Int(tier.workThreshold / 60)) minutes working → "
                             + "\(BreakPrompt.phrase(tier.breakLength)) off. \(tier.reason)")
                    }
                    Text("Timed from continuous use, not from sessions. A short break "
                         + "resets the short timer only; the longer ones keep running.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var automatic: some View {
        Form {
            Section {
                Toggle("Start sessions for me", isOn: $model.autoSessionsEnabled)
                Picker("Auto-session gap", selection: $model.breakLength) {
                    ForEach(FocusConstants.breakLengthOptions, id: \.self) {
                        Text(Tokens.duration($0)).tag($0)
                    }
                }
                Toggle("Celebrate milestones", isOn: $model.rewardsEnabled)
            } footer: {
                Text("Sessions the app starts can be undone from the notice, and one it "
                     + "ends on its own ends where the work stopped. The gap is how long "
                     + "a pause must be before such a session is treated as over.")
                Text("Started sessions are named by what you are doing — Browsing in a "
                     + "browser, Coding, Writing & AI, Design elsewhere. Apps the app "
                     + "does not know are read from the category they declare about "
                     + "themselves, when they declare one.")
            }
        }
        .formStyle(.grouped)
    }

    private var display: some View {
        Form {
            Section {
                Picker("Sessions per app", selection: $model.menuSessionCount) {
                    ForEach([3, 5, 7, 10], id: \.self) { Text("\($0)").tag($0) }
                }
                Toggle("Record app usage", isOn: $model.isTrackingEnabled)
            } footer: {
                Text("Recording is local and keeps app names and bundle identifiers only — "
                     + "never window titles, addresses, or anything you type.")
            }
        }
        .formStyle(.grouped)
    }
}
