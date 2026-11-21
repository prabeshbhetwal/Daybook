import Foundation

/// What a session records of how it began, and the file that remembers how the person files things: the
/// README's Privacy section says the same, and each sentence is true of the code (`SessionRecord`,
/// `CategoryCorrections`, `CorrectionsStore`, `DataBackup`).
extension SettingsPrivacyDisclosure {
    var sessionOriginDetail: String {
        " Each session also records how it began (started by you, by an Activity Rule or by Daybook),"
        + " where its category came from (you, a rule, a choice you made before or Daybook's own default)"
        + " and whether Daybook chose its name. When you file a finished session under another category,"
        + " Daybook keeps a small file, corrections.json, with only a pattern fingerprint of that kind of"
        + " session (its share of time by activity and the two apps with the most time), category names,"
        + " counts and dates. It is used only to suggest a category, including for the second half of a"
        + " session that Daybook splits itself. A choice you have not made again for 90 days stops being"
        + " suggested and is dropped from the file. Backups include the sessions and this file. Splitting a"
        + " session or merging it back never changes the time you worked; a part Daybook cannot place is"
        + " filed as Unsorted, which does not count toward your goals. With automatic sessions on, watching"
        + " or listening for 10 minutes or more outside a session is kept in leisure.json (the app and the"
        + " times only) and shown on the timeline; it never counts as focus or as a break, and backups"
        + " include it."
    }
}
