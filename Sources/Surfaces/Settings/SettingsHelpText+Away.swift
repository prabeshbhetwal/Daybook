import Foundation

/// The Away, Breaks, Recording, Privacy and About pages' explanations. See
/// `SettingsHelpText` for what an entry is.
extension SettingsHelpText {
    // MARK: - Away

    static let steppingAway: [HelpEntry] = [
        HelpEntry("Pause after no input for", """
            After this long without the keyboard, mouse or trackpad, you count as away: the session pauses \
            from your last touch and that time is left out. If you set 10 minutes, 12 quiet minutes of \
            reading pause it.
            """),
        HelpEntry("Ask me after", """
            When you come back after being away this long, Daybook asks what the time was: a break, work, \
            or time to leave out. If you set 15 minutes, 20 minutes away gets the question and 10 is left \
            out quietly.
            """),
        HelpEntry("Stop session after", """
            Being away this long ends the session at the moment you left, without a question. If you set 4 \
            hours, a laptop closed overnight ends the session when you closed it. Never keeps it open.
            """),
        HelpEntry("Full-screen prompt after", """
            Shorter absences are asked about from the menu bar; longer ones on a card over the whole \
            screen. If you set 30 minutes, 10 minutes away is asked about in the menu bar and 40 minutes \
            on the full screen.
            """)
    ]

    static let appsWorking: [HelpEntry] = [
        HelpEntry("While an app works for you", """
            What your session does while you wait on an app, such as an AI agent, a video export or a \
            build. Count it as work keeps the clock going, Pause without asking stops it, and Treat it as \
            time away changes nothing.
            """),
        HelpEntry("Notice apps working for you by themselves", """
            Daybook checks whether a coding or AI app you used this session is busy sending data or \
            working hard, to tell that it is working for you. It never reads what the app holds.
            """),
        HelpEntry("Count a coding app in front as you being here", """
            While a coding or AI app is the one you are using, quiet time counts as you being here. Leave \
            this off if you often walk away with one open.
            """),
        HelpEntry("Count a keep-awake app as you being here", """
            While an app such as Amphetamine or Caffeine keeps your screen on, quiet time counts as you \
            being here. A lunch with one running counts too.
            """),
        HelpEntry("Let your agent tell Daybook when it works", """
            The button copies a short message. Paste it into Claude Code, Codex, Gemini CLI or Cursor, and \
            the agent sets itself up to let Daybook know each time it is busy. Nothing else is shared.
            """)
    ]

    // MARK: - Breaks

    static let reminders: [HelpEntry] = [
        HelpEntry("Remind me to take breaks", """
            Daybook tells you when it is time to rest, timed from your typing and clicking whether or not \
            a session is running. Off, no break reminders appear at all, Eyes and the guard included.
            """),
        HelpEntry("Rhythm", """
            How long you work before a break, and how long it lasts. Steady · 50/5 means 50 minutes of \
            work, then 5 minutes off. With Flow you stop when you choose; Custom uses your own numbers.
            """),
        HelpEntry("Work", """
            For Custom: how long you work before a break is due. If you set 45 min, a reminder comes after \
            45 minutes of steady work.
            """),
        HelpEntry("Break", """
            For Custom: how long each break lasts. If you set 10 min, the break counts down from 10 minutes.
            """),
        HelpEntry("Long break every", """
            Makes some breaks longer. If you set 3 breaks, every third break is the long one. Off keeps \
            every break the same length.
            """),
        HelpEntry("Long break length", """
            How long the long break lasts. It is never shorter than a normal break.
            """)
    ]

    static let weekdayPlan: [HelpEntry] = [
        HelpEntry("Usual rhythm", """
            Each day's menu sets that day's breaks. Usual rhythm follows the rhythm under Reminders. Pick \
            another for a day that works differently, such as Deep work on Fridays.
            """),
        HelpEntry("No reminders", """
            That day gets no break reminders. Eyes and the long-stretch guard still appear if they are on.
            """)
    ]

    static let overrides: [HelpEntry] = [
        HelpEntry("Today", """
            A different rhythm, or no reminders, for today only. Tomorrow goes back to your weekday plan.
            """),
        HelpEntry("This week", """
            The same for every day of this week. Next week goes back to your weekday plan.
            """),
        HelpEntry("This month", """
            The same for every day of this month. Next month goes back to your weekday plan.
            """),
        HelpEntry("Dates", """
            The same for the days you choose with From and To, such as a holiday. After the last day, your \
            weekday plan comes back.
            """)
    ]

    static let workingHours: [HelpEntry] = [
        HelpEntry("Working hours", """
            Break reminders appear only between From and To. Outside them Daybook stays quiet but keeps \
            counting your work. If you set 09:00 to 17:30, no reminder appears at 18:00.
            """)
    ]

    static let eyesAndStretches: [HelpEntry] = [
        HelpEntry("Eyes", """
            Every 20 minutes a small reminder asks you to look at something far away for a moment, to rest \
            your eyes. It is skipped when a break is close.
            """),
        HelpEntry("Long-stretch guard", """
            If you keep working a long time without a break, one firmer reminder appears.
            """),
        HelpEntry("Guard comes after", """
            How long you work without a break before the guard appears. If you set 2 hours, it comes after \
            2 hours of unbroken work. With some rhythms it waits longer, and the line above says when.
            """)
    ]

    static let breakEnds: [HelpEntry] = [
        HelpEntry("Play a sound when a break is over", """
            A short sound plays when your break time is up. Play lets you hear it first, even with the \
            switch off.
            """),
        HelpEntry("Show break countdown in the menu bar", """
            During a break, the time left shows beside Daybook's icon in the menu bar. This needs the menu \
            bar icon to be shown.
            """)
    ]

    // MARK: - Recording

    static let appUse: [HelpEntry] = [
        HelpEntry("Record app use", """
            Daybook notes which app you are using and for how long, all day, and keeps it on this Mac: your \
            recorded app use. Off, nothing new is noted and the Story shows sessions only. Earlier records stay.
            """),
        HelpEntry("Apps shown in a card", """
            How many apps the Your apps card lists in the Story and History. If you set 4, you see your top \
            4 apps.
            """),
        HelpEntry("Recent app visits", """
            When you click an app in the Your apps card, this many of its latest visits are listed. If you \
            set 5, you see 5, and a Show All button lists the rest.
            """)
    ]

    // MARK: - Privacy

    /// The on-device AI row is drawn only on a Mac that can run the model.
    static var privacy: [HelpEntry] {
        [
            HelpEntry("Storage", """
                Where your history is kept. Local only means it stays on this Mac. It says backed up to \
                iCloud while automatic backups go to iCloud Drive.
                """),
            HelpEntry("App use measured precisely since", """
                From this date, recorded app use leaves out time you were away. Records from before it may \
                count some time away as app use.
                """)
        ] + (ModelGate.modelAvailable ? [onDeviceAI] : [])
    }

    static let onDeviceAI = HelpEntry("Use on-device AI", """
        Lets on-device AI write short notes about your days, suggest names for unnamed sessions and help \
        History's search understand you. It runs on this Mac and nothing leaves it. Ask has its own switch.
        """)

    static let backups: [HelpEntry] = [
        HelpEntry("Back up automatically", """
            Copies your Daybook history and settings to a dated folder on a schedule. If you set Every day, \
            a fresh copy is made each day. Off makes copies only when you choose Back Up Now.
            """),
        HelpEntry("Back up to", """
            Where backups go: iCloud Drive, or another folder or disk you pick with Choose Folder. If \
            iCloud Drive is off on this Mac, nothing is backed up until you turn it on or pick a folder.
            """),
        HelpEntry("Keep automatic backups", """
            How long automatic copies stay. If you set For a month, older automatic copies move to the \
            Trash. Copies made with Back Up Now are always kept.
            """),
        HelpEntry("Back Up Now", """
            Makes a copy straight away, in the place Back up to names.
            """),
        HelpEntry("Show Backups", """
            Opens the folder that holds your backups in Finder.
            """)
    ]

    // MARK: - About

    static let updates: [HelpEntry] = [
        HelpEntry("Check for updates automatically", """
            Daybook looks for a newer version by itself. The only thing it sends is the version number you \
            have.
            """),
        HelpEntry("How often", """
            How often Daybook looks. If you set Weekly, it checks about once a week.
            """),
        HelpEntry("When an update is found", """
            Ask first shows what is new and lets you install, wait or skip that version. Install \
            automatically downloads it, then installs after a 30-second countdown you can cancel.
            """),
        HelpEntry("Check for Updates", """
            Check Now looks for a newer version straight away.
            """)
    ]
}
