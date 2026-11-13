import AppKit
import SwiftUI

/// Settings → Breaks: when to be reminded to rest, and how the breaks are
/// spaced. Every row below the master switch is off while it is off. The
/// dates and times these rows show come from the model, never from here.
extension SettingsGroups {
    var breaks: some View {
        let on = model.remindersEnabled
        return VStack(alignment: .leading, spacing: layout.panelSpacing) {
            rhythmPanel
            SurfacePanel(title: "Weekday plan", layout: layout) { weekdayRows }
                .disabled(!on)
            SurfacePanel(title: "Overrides", layout: layout) { overrideRows }
                .disabled(!on)
            SurfacePanel(title: "Working hours", layout: layout) { workingHoursRows }
                .disabled(!on)
            SurfacePanel(title: "Eyes and long stretches", layout: layout) { addOnRows }
                .disabled(!on)
            SurfacePanel(title: "When a break ends", layout: layout) {
                preferenceRow("Play a sound when a break is over") {
                    HStack(spacing: Tokens.Space.m) {
                        // Works with the switch off too: hearing it is how you decide.
                        Button {
                            NSSound(named: FocusConstants.breakOverSoundName)?.play()
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        .accessibilityLabel("Play the break-over sound")
                        Toggle("Play a sound when a break is over", isOn: $model.breakOverSound)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(Tokens.Zoom.controlSize(.mini))
                    }
                }
                toggleRow("Show break countdown in the menu bar", isOn: $model.menuBarShowsBreakCountdown)
                    .disabled(!model.showsMenuBarIcon)
            }
            .disabled(!on)
        }
    }

    // MARK: - Rhythm

    private var rhythmPanel: some View {
        SurfacePanel(title: "Reminders", layout: layout) {
            toggleRow("Remind me to take breaks",
                      detail: "Timed from typing and clicking, not from sessions.",
                      isOn: $model.remindersEnabled)
            rowDivider
            preferenceRow("Rhythm",
                          detail: model.breakRhythm.evidenceNote ?? "Your own numbers, set below.") {
                RowMenu("Rhythm", selection: $model.breakRhythm,
                        options: BreakPreset.allCases) { $0.pickerTitle }
            }
            .disabled(!model.remindersEnabled)
            if model.breakRhythm == .custom {
                customRows.disabled(!model.remindersEnabled)
            }
        }
    }

    @ViewBuilder private var customRows: some View {
        let custom = model.customRhythm
        rowDivider
        preferenceRow("Work") { minutesStepper("Work", \.workMinutes, 10...180, step: 5) }
        rowDivider
        preferenceRow("Break") { minutesStepper("Break", \.breakMinutes, 1...30, step: 1) }
        rowDivider
        preferenceRow("Long break every", detail: Self.longBreakDetail(every: custom.longEvery)) {
            RowMenu("Long break every", selection: customBinding(\.longEvery),
                    options: [nil] + (2...8).map { Optional($0) }) { $0.map { "\($0) breaks" } ?? "Off" }
        }
        if custom.longEvery != nil {
            rowDivider
            preferenceRow("Long break length") {
                minutesStepper("Long break length", \.longMinutes, max(5, custom.breakMinutes)...60, step: 5)
            }
        }
    }

    private func customBinding<Value>(_ keyPath: WritableKeyPath<CustomRhythm, Value>) -> Binding<Value> {
        Binding(get: { model.customRhythm[keyPath: keyPath] },
                set: { value in
                    var custom = model.customRhythm
                    custom[keyPath: keyPath] = value
                    model.customRhythm = custom
                })
    }

    private func minutesStepper(_ label: String, _ keyPath: WritableKeyPath<CustomRhythm, Int>,
                                _ range: ClosedRange<Int>, step: Int) -> some View {
        let minutes = customBinding(keyPath)
        return Stepper(value: minutes, in: range, step: step) {
            Text("\(minutes.wrappedValue) min").font(Tokens.Typography.control).monospacedDigit()
        }
        .accessibilityLabel(label)
        .accessibilityValue("\(minutes.wrappedValue) minutes")
    }

    // MARK: - Weekday plan and overrides

    @ViewBuilder private var weekdayRows: some View {
        let order = model.weekdayOrder
        ForEach(order, id: \.self) { index in
            if index != order.first { rowDivider }
            let name = model.weekdayName(index)
            preferenceRow(name) {
                planMenu(name, Binding(get: { model.breakWeekdayPlans[index] },
                                       set: { model.breakWeekdayPlans[index] = $0 }),
                         usual: "Usual rhythm")
            }
        }
        explanation("No reminders leaves Eyes and the guard on.")
    }

    @ViewBuilder private var overrideRows: some View {
        overrideRow("Today", .today)
        rowDivider
        overrideRow("This week", .week)
        rowDivider
        overrideRow("This month", .month)
        rowDivider
        overrideRow("Dates", .range)
        if model.breakOverridePlan(.range) != .usual {
            preferenceRow("From") { datePicker("Dates from", $model.breakRangeFrom, .date) }
                .padding(.leading, Tokens.Space.l)
            preferenceRow("To") { datePicker("Dates to", $model.breakRangeTo, .date) }
                .padding(.leading, Tokens.Space.l)
        }
        explanation(Self.overridesFootnote)
    }

    static let overridesFootnote = "These replace the weekday plan. Where two overlap, the shorter one wins."

    /// What the Long break every row says about the chosen number: "Every 3rd
    /// break is the long one."
    static func longBreakDetail(every: Int?) -> String {
        guard let every else { return "Off, every break is the same length." }
        return "Every \(Ordinal.text(every)) break is the long one."
    }

    /// A date or time picker working in the model's calendar and zone, so it
    /// shows the day and minute that are stored. `title` is what VoiceOver
    /// reads, so it names the panel as well as the end ("Dates from", not
    /// "From" twice).
    private func datePicker(_ title: String, _ selection: Binding<Date>,
                            _ components: DatePickerComponents) -> some View {
        DatePicker(title, selection: selection, displayedComponents: components)
            .labelsHidden()
            .accessibilityLabel(title)
            .environment(\.calendar, model.pickerCalendar)
            .environment(\.timeZone, model.pickerCalendar.timeZone)
    }

    private func overrideRow(_ title: String, _ kind: BreakOverrideKind) -> some View {
        preferenceRow(title) {
            planMenu(title, Binding(get: { model.breakOverridePlan(kind) },
                                    set: { model.setBreakOverride(kind, plan: $0,
                                                                  from: kind == .range ? model.breakRangeFrom : nil,
                                                                  to: kind == .range ? model.breakRangeTo : nil) }),
                     usual: "Weekday plan")
        }
    }

    private func planMenu(_ title: String, _ selection: Binding<BreakDayPlan>, usual: String) -> some View {
        RowMenu(title, selection: selection,
                options: [.usual] + BreakPreset.allCases.map(BreakDayPlan.preset) + [.off]) { plan in
            switch plan {
            case .usual: return usual
            case .preset(let preset): return preset.title
            case .off: return "No reminders"
            }
        }
    }

    // MARK: - Working hours, Eyes and the guard

    @ViewBuilder private var workingHoursRows: some View {
        toggleRow("Working hours",
                  detail: "Quiet outside these hours. 22:00 to 06:00 runs overnight.",
                  isOn: $model.workingHoursEnabled)
        if model.workingHoursEnabled {
            preferenceRow("From") { datePicker("Working hours from", $model.workingHoursFrom, .hourAndMinute) }
                .padding(.leading, Tokens.Space.l)
            preferenceRow("To") { datePicker("Working hours to", $model.workingHoursTo, .hourAndMinute) }
                .padding(.leading, Tokens.Space.l)
        }
    }

    @ViewBuilder private var addOnRows: some View {
        toggleRow("Eyes",
                  detail: "Look far away every 20 minutes. Skipped near a break.",
                  isOn: $model.breakEyes)
        rowDivider
        toggleRow("Long-stretch guard",
                  detail: Self.guardDetail(pickedMinutes: model.breakGuardMinutes,
                                           comesAfter: model.guardComesAfter),
                  isOn: $model.breakGuardEnabled)
        preferenceRow("Guard comes after") {
            RowMenu("Guard comes after", selection: $model.breakGuardMinutes,
                    options: Self.guardChoices(including: model.breakGuardMinutes)) {
                Tokens.duration(TimeInterval($0 * 60))
            }
        }
        .padding(.leading, Tokens.Space.l)
        .disabled(!model.breakGuardEnabled)
    }

    /// What the Long-stretch guard row says. The second sentence names the
    /// time the guard really comes only when it is not the one the picker
    /// shows: a guard set at or past the rhythm's work block waits until 15
    /// minutes after that block.
    static func guardDetail(pickedMinutes: Int, comesAfter: TimeInterval?) -> String {
        let base = "One firmer prompt after a long unbroken stretch."
        guard let comesAfter, comesAfter != TimeInterval(pickedMinutes * 60) else { return base }
        return base + " With your usual rhythm it comes after \(Tokens.duration(comesAfter))."
    }

    /// 60 to 180 minutes in quarter hours, and the stored value when it is
    /// not one of them, so the picker always has something selected.
    static func guardChoices(including current: Int) -> [Int] {
        let range = BreakPlan.guardRange
        let steps = Array(stride(from: range.lowerBound, through: range.upperBound, by: 15))
        return steps.contains(current) ? steps : (steps + [current]).sorted()
    }
}

private extension BreakPreset {
    /// The picker's wording: the name, then the work and break minutes
    /// where they are fixed.
    var pickerTitle: String {
        let rhythm = BreakRhythm(self)
        guard self != .custom, let work = rhythm.work, let rest = rhythm.breakLength else { return title }
        return "\(title) · \(Int(work / 60))/\(Int(rest / 60))"
    }
}
