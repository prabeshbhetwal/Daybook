import Foundation

/// What the tail of a split begins as (plan rulings B5, B8, B9, B11). Daybook never files time that is not
/// clearly focused work under a category that counts as focus: such a tail is the person's to file, or
/// Unsorted when an automatic session cuts itself.
enum SplitTailChoice: Equatable {
    /// Daybook's pick, for a tail whose dominant purpose is focused: a category the person remembered for
    /// this kind of work (`correction`), else the one built in for its top app (`builtIn`).
    case chosen(WorkType, DecisionSource)
    /// Not clearly focused work, or nothing to go on: the person picks, starting from this category.
    case ask(WorkType)

    /// `remembered` and `suggested` count only while they are categories a person can still start.
    /// `ownCut`: an automatic session cutting itself, where a tail the evidence says was not focused work takes
    /// the category the person remembered for it, else Unsorted (spec section 6), which never counts as focus.
    /// The person's offer still asks.
    static func decide(label: ActivityLabel?, remembered: WorkType?, suggested: WorkType?,
                       head: WorkType, ownCut: Bool = false) -> SplitTailChoice {
        guard case .activity(let purpose)? = label, purpose.isFocused else {
            guard ownCut, label != nil else { return .ask(head) }
            if let remembered, WorkType.startable.contains(remembered) { return .chosen(remembered, .correction) }
            return .chosen(.unsorted, .builtIn)
        }
        if let remembered, WorkType.startable.contains(remembered) { return .chosen(remembered, .correction) }
        if let suggested, WorkType.startable.contains(suggested) { return .chosen(suggested, .builtIn) }
        return .ask(head)
    }
}

extension SplitTail {
    /// Ruling B9: a head whose name was Daybook's gives the tail the name for what it was (empty when that
    /// has none, which reads as unnamed); a name the person gave carries over to the tail as theirs.
    init(after head: SessionRecord, workType: WorkType, source: DecisionSource, purpose: AppPurpose?,
         topApp: String?) {
        if head.nameByApp == true {
            let name = purpose.map { AutoSessionDetector.sessionName(forApp: topApp, purpose: $0) } ?? ""
            self.init(name: name, workType: workType, source: source, nameByApp: !name.isEmpty, detectedApp: topApp)
        } else {
            self.init(name: head.name, workType: workType, source: source, nameByApp: false, detectedApp: topApp)
        }
    }
}
