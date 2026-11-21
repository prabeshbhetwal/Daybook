import Foundation

/// What each Settings panel's info mark says, keyed by the panel's title as it
/// reads on screen. Words only: `SurfacePanel` draws them, and the checks read
/// them here without drawing anything. Every entry starts with a control's name
/// as the panel shows it, and says what changes for the person, in plain words.
enum SettingsHelpText {
    static var groups: [String: [HelpEntry]] {
        [
            "Menu bar, Dock and login": menuBar, "Ask Daybook": ask, "Keyboard": keyboard,
            "Haptics": haptics, "Confirmations": confirmations, "Interface": interface, "Story": story,
            "Goal": goal, "Starting and ending": startingAndEnding, "Categories": categories,
            "Automatic categories": automaticCategories, "Automatic sessions": automatic,
            "Activity rules": activityRules, "Rules": rules, "New rule": ruleForm, "Edit rule": ruleForm,
            "Stepping away": steppingAway, "Apps working for you": appsWorking,
            "Reminders": reminders, "Weekday plan": weekdayPlan, "Overrides": overrides,
            "Working hours": workingHours, "Eyes and long stretches": eyesAndStretches,
            "When a break ends": breakEnds,
            "App use": appUse, "Daily goals": dailyGoals, "Privacy": privacy, "Backups": backups, "Updates": updates
        ]
    }

    /// Panels with no info mark, because each already says all it does.
    static let unexplained: Set<String> = [
        // Buttons that replay the welcome tour, under a line saying how long it takes.
        "Getting started",
        // The folder's path and a button that shows it in Finder; nothing to set.
        "Data folder",
        // Each row says what is read and kept, in the consent sheet's words; a card would restate them.
        "Site signal",
        // The version, the build and a recovery report, to read; nothing to set.
        "Diagnostics"
    ]

    // MARK: - General

    static let menuBar: [HelpEntry] = [
        HelpEntry("Open at login", """
            Daybook opens by itself each time you log in to your Mac, so it is ready to time your work. \
            If macOS asks you to approve it, a button appears here that takes you there.
            """),
        HelpEntry("Show the icon in the menu bar", """
            Puts Daybook's icon in the bar along the top of your screen, where you can start and stop \
            sessions. If you hide it, Daybook stays in the Dock so you can still open it.
            """),
        HelpEntry("Show the session time in the menu bar", """
            While a session runs, its time shows beside the icon. Off, the time is not shown. \
            This needs the menu bar icon to be shown.
            """),
        HelpEntry("Dock icon", """
            When Daybook appears in the Dock: while its window is open, always, or never. With Never, \
            Daybook also has no menus along the top of the screen. It always shows while the menu bar \
            icon is hidden.
            """)
    ]

    static let ask: [HelpEntry] = [
        HelpEntry("Show Ask in the toolbar", """
            Ask lets you type a question about your days, such as when you focus best, and on-device AI \
            answers on this Mac. Off hides the Ask button only: ⌘K still opens Ask.
            """),
        HelpEntry("Open Ask in", """
            Sheet opens Ask over the window. Side panel opens it beside your Story or History, so you can \
            read both at once. Small screens always get the sheet.
            """)
    ]

    static let keyboard: [HelpEntry] = [
        HelpEntry("Start or end a session from any app", """
            Press these keys in any app. With no session running, a focus session starts; with one running, \
            it stops. Click the keys to record your own. Reset brings back Control-Option-Space, and Turn \
            Off removes them.
            """)
    ]

    static let confirmations: [HelpEntry] = [
        HelpEntry("Ask before changing how a break counts", """
            On a recorded break, Count as Focus and Leave Uncounted ask you to confirm first. Off, they \
            change it straight away. Undo can put it back either way.
            """),
        HelpEntry("Ask before removing a session", """
            Remove on a session asks you to confirm first. Off, the session is removed straight away. \
            Undo can bring it back either way.
            """)
    ]

    static let interface: [HelpEntry] = [
        HelpEntry("Appearance", """
            Light or Dark sets how Daybook looks. System follows your Mac, so Daybook changes when your \
            Mac does.
            """),
        HelpEntry("Interface density", """
            Compact fits more on the screen, with less space between things. Comfortable gives everything \
            more room.
            """),
        HelpEntry("Zoom", """
            Makes everything in Daybook bigger or smaller, from 80% to 160%. If you set 120%, text and \
            controls are a fifth larger. The arrow beside it, or ⌘0, goes back to 100%.
            """)
    ]

    static let story: [HelpEntry] = [
        HelpEntry("Show Story timestamps", """
            Shows the time of each entry down the left of the Story, the page that tells your day in \
            order. Off hides those times.
            """),
        HelpEntry("Expand entry details by default", """
            Entries in the Story open with their details showing, such as the apps you used. Off, they \
            start closed and you click one to open it.
            """),
        HelpEntry("Fold quiet stretches after", """
            Gaps, and app use outside your sessions, fold into one line you can open. If you set 3 rows, \
            three or more such rows in a row become one line. Never shows every row.
            """),
        HelpEntry("Apps shown in a card", """
            How many apps the Top apps card lists in the Story and History. If you set 4, you see your top \
            4 apps.
            """),
        HelpEntry("Recent app visits", """
            When you click an app in the Top apps card, this many of its latest visits are listed. If you \
            set 5, you see 5, and a Show All button lists the rest.
            """)
    ]

    static let haptics: [HelpEntry] = [
        HelpEntry("Haptic feedback", """
            Your trackpad, or a Logitech MX Master 4 mouse, gives a small tap at moments such as a session \
            starting or stopping, a break being due or your goal being reached.
            """),
        HelpEntry("Try haptic feedback", """
            Try plays one tap now, so you know what to feel for. It works while Haptic feedback is on, and \
            says so if the mouse could not be reached.
            """)
    ]

    // MARK: - Sessions

    static let dailyGoals: [HelpEntry] = [
        HelpEntry("Add Goal", """
            Adds a goal for a category, such as Coding, or an app. A category goal counts focus with an \
            app in use, as your daily goal does. Each goal's menu sets its amount, pauses it or removes it. \
            You can keep up to eight goals.
            """),
        HelpEntry("App limit", """
            Time to keep an app under, such as a video app. It counts all the time the app was in front \
            that day, in a session or not. If you set 2 hours, you have 1 hour 15 minutes left after 45 \
            minutes.
            """)
    ]
    static let goal: [HelpEntry] = [
        HelpEntry("Daily goal", """
            How much focus you aim for each day. Focus is time in focus sessions, the stretches of work \
            you time, and it counts only while you are using the Mac. If you set 4 hours, the goal is met \
            at 4 hours.
            """),
        HelpEntry("Usual pace compares with", """
            Daybook compares your focus so far today with what you usually had by this time of day. If you \
            set last 14 days, your usual comes from the past 14 days.
            """),
        HelpEntry("Streak counts a day after", """
            Your streak is how many days in a row reach this much focus. If you set 25 minutes, a day with \
            only 20 minutes ends the run.
            """),
        HelpEntry("Celebrate milestones", """
            Short notes cheer you on at good moments, such as reaching your daily goal, a new streak \
            record or being ahead of your usual pace. Off, they no longer appear.
            """)
    ]

    static let startingAndEnding: [HelpEntry] = [
        HelpEntry("New sessions start as", """
            The category already chosen for your next session when Daybook opens. A category is the kind \
            of work a session is filed under, such as Deep work. You can pick another before you start.
            """),
        HelpEntry("Suggest activities from", """
            Names you gave sessions recently are offered when you start the next one. If you set last 30 \
            days, a name you last used 6 weeks ago is not offered.
            """),
        HelpEntry("Keep sessions longer than", """
            A session shorter than this is not saved. If you set 1 minute, a session you stop after 40 \
            seconds leaves nothing behind. Breaks and time away shorter than this are not saved either.
            """)
    ]

    static let categories: [HelpEntry] = [
        HelpEntry("New Category", """
            Makes a category of your own for work the others do not describe. Click any category in the \
            list to change it.
            """),
        HelpEntry("Category name", """
            What the category is called wherever Daybook shows it. Two categories cannot share a name.
            """),
        HelpEntry("Colour", """
            The colour the category wears in your Story, History and charts.
            """),
        HelpEntry("Icon", """
            The small picture beside the category's name: a symbol, or a letter or number drawn in a \
            circle or a square.
            """),
        HelpEntry("Daily goal", """
            A goal for this category alone, shown as its own line under the day's goal. If you set 1 hour, \
            that line is met after an hour of this kind of work. None leaves it out.
            """),
        HelpEntry("Remind me to take breaks during this category", """
            On, break reminders appear as usual during this category's sessions. Off, they wait until \
            the session ends, which suits calls.
            """),
        HelpEntry("Counts while watching", """
            For categories you make. On, time spent watching without typing, such as a call or a lecture, \
            still counts. Off, it pauses the clock.
            """),
        HelpEntry("Reset to Default", """
            For a built-in category you changed. Its name, icon and colour go back to the originals, its \
            daily goal is removed and break reminders go back to normal. You confirm first.
            """),
        HelpEntry("Retire", """
            Stops offering the category for new sessions. Sessions already filed under it keep it. The \
            last category that can start a session cannot be retired.
            """),
        HelpEntry("Restore", """
            Offers a retired category for new sessions again.
            """)
    ]

    static let automatic: [HelpEntry] = [
        HelpEntry("Guess sessions from the app in front", """
            Daybook starts a focus session by itself after about 5 minutes in work apps, such as a code \
            editor, and pauses it when you move to a break app, such as a video player. You can undo one it \
            started.
            """),
        HelpEntry("Stop a paused automatic session after", """
            A session Daybook started by itself ends once it has been paused this long. If you set 10 \
            minutes, a 15-minute video ends it. Never keeps it paused until you come back.
            """)
    ]

    // MARK: - Activities

    static let activityRules: [HelpEntry] = [
        HelpEntry("Use my activity rules", """
            Lets your rules start sessions by themselves. A rule links an activity, such as Coding, to the \
            apps you use for it. A rule starts one only when none is running. While this is on, guessing \
            from the app in front is off.
            """)
    ]

    static let rules: [HelpEntry] = [
        HelpEntry("New Rule", """
            Opens a form for a new rule: its name, its apps and how long to wait. Click a rule to change \
            it. Its switch turns it on or off, and its … menu can also duplicate or delete it.
            """)
    ]

    static let ruleForm: [HelpEntry] = [
        HelpEntry("Activity name", """
            What the rule's sessions are called. The category beside it is where they are filed. Typing a \
            category's name, such as Meetings, picks that category for you.
            """),
        HelpEntry("Start after", """
            How long you must stay in one of the rule's apps before its session starts. If you set 3 \
            minutes, a 1-minute visit starts nothing. Custom takes 30 to 1,800 seconds.
            """),
        HelpEntry("Use this rule", """
            Shown for a new rule. Off, the rule is saved but starts nothing until you turn on the switch on \
            its card.
            """),
        HelpEntry("Running now", """
            Apps open on your Mac right now. Click one to add it to this rule.
            """),
        HelpEntry("All apps", """
            Every app on your Mac. Click an app to add it to the rule or take it out, or search for one by \
            name. Apps in the rule show under In this activity, where a click takes one out.
            """),
        HelpEntry("Add App…", """
            Choose an app that is not in the list, such as one kept outside your Applications folder.
            """),
        HelpEntry("Delete Rule", """
            Removes the rule after you confirm. Sessions it already started stay in your history.
            """)
    ]
}
