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
                toggleRow("Play a sound when a break is over",
                          detail: "A short tone with the \"Break's over\" prompt.",
                          isOn: $model.breakOverSound)
                toggleRow("Show break countdown in the menu bar",
                          detail: "Off, the menu bar shows only the cup while a break is under way.",
                          isOn: $model.menuBarShowsBreakCountdown)
                    .disabled(!model.showsMenuBarIcon)
            }
            .disabled(!on)
        }
    }

    // MARK: - Rhythm

    private var rhythmPanel: some View {
        SurfacePanel(title: "Reminders", layout: layout) {
            toggleRow("Remind me to take breaks",
                      detail: "A notice after a long stretch of continuous use, timed from your typing "
                        + "and clicking rather than from sessions.",
                      isOn: $model.remindersEnabled)
            rowDivider
            preferenceRow("Rhythm",
                          detail: model.breakRhythm.evidenceNote ?? "Your own numbers, set below.") {
                Picker("Rhythm", selection: $model.breakRhythm) {
                    ForEach(BreakPreset.allCases, id: \.self) { Text($0.pickerTitle).tag($0) }
                }
                .labelsHidden()
                .accessibilityLabel("Rhythm")
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
        preferenceRow("Long break every", detail: "Every this many breaks, one is the long one.") {
            Picker("Long break every", selection: customBinding(\.longEvery)) {
                Text("Off").tag(Int?.none)
                ForEach(2...8, id: \.self) { Text("\($0) breaks").tag(Int?.some($0)) }
            }
            .labelsHidden()
            .accessibilityLabel("Long break every")
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
                Picker(name, selection: Binding(get: { model.breakWeekdayPlans[index] },
                                                set: { model.breakWeekdayPlans[index] = $0 })) {
                    planOptions(usual: "Usual rhythm")
                }
                .labelsHidden()
                .accessibilityLabel(name)
            }
        }
        explanation("No reminders turns off the rhythm that day. Eyes and the long-stretch guard follow "
                    + "their own switches.")
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
            preferenceRow("From") {
                DatePicker("From", selection: $model.breakRangeFrom, displayedComponents: .date).labelsHidden()
            }
            .padding(.leading, Tokens.Space.l)
            preferenceRow("To") {
                DatePicker("To", selection: $model.breakRangeTo, displayedComponents: .date).labelsHidden()
            }
            .padding(.leading, Tokens.Space.l)
        }
        explanation("These set the weekday plan aside for a while. Where more than one covers a day, "
                    + "the shortest wins.")
    }

    private func overrideRow(_ title: String, _ kind: BreakOverrideKind) -> some View {
        preferenceRow(title) {
            Picker(title, selection: Binding(get: { model.breakOverridePlan(kind) },
                                             set: { model.setBreakOverride(kind, plan: $0,
                                                                           from: kind == .range ? model.breakRangeFrom : nil,
                                                                           to: kind == .range ? model.breakRangeTo : nil) })) {
                planOptions(usual: "Weekday plan")
            }
            .labelsHidden()
            .accessibilityLabel(title)
        }
    }

    @ViewBuilder private func planOptions(usual: String) -> some View {
        Text(usual).tag(BreakDayPlan.usual)
        ForEach(BreakPreset.allCases, id: \.self) { Text($0.title).tag(BreakDayPlan.preset($0)) }
        Text("No reminders").tag(BreakDayPlan.off)
    }

    // MARK: - Working hours, Eyes and the guard

    @ViewBuilder private var workingHoursRows: some View {
        toggleRow("Working hours",
                  detail: "Reminders stay quiet outside these hours. A start later than the end runs "
                    + "overnight, such as 22:00 to 06:00.",
                  isOn: $model.workingHoursEnabled)
        if model.workingHoursEnabled {
            preferenceRow("From") {
                DatePicker("From", selection: $model.workingHoursFrom, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            .padding(.leading, Tokens.Space.l)
            preferenceRow("To") {
                DatePicker("To", selection: $model.workingHoursTo, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            .padding(.leading, Tokens.Space.l)
        }
    }

    @ViewBuilder private var addOnRows: some View {
        toggleRow("Eyes",
                  detail: "Every 20 minutes of use, a short reminder to look at something far away. It has "
                    + "no buttons, and stays quiet within 5 minutes of a break, so short blocks such as "
                    + "Pomodoro rarely show it.",
                  isOn: $model.breakEyes)
        rowDivider
        toggleRow("Long-stretch guard",
                  detail: "One clearer prompt after an unbroken stretch, whatever the rhythm. With a longer "
                    + "work block it comes 15 minutes after that block.",
                  isOn: $model.breakGuardEnabled)
        preferenceRow("Guard comes after") {
            Picker("Guard comes after", selection: $model.breakGuardMinutes) {
                ForEach(Self.guardChoices(including: model.breakGuardMinutes), id: \.self) {
                    Text(Tokens.duration(TimeInterval($0 * 60))).tag($0)
                }
            }
            .labelsHidden()
            .accessibilityLabel("Guard comes after")
        }
        .padding(.leading, Tokens.Space.l)
        .disabled(!model.breakGuardEnabled)
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
