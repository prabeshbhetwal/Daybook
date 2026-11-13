import Foundation

extension String {
    /// A system error's description with a full stop at its end, so a message
    /// can follow it with the next sentence. `localizedDescription` ends in
    /// one most of the time and not always: "Couldn't save. <description> Check
    /// free space" ran two sentences together whenever it did not.
    var endingInFullStop: String {
        let text = trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = text.last, !".!?…".contains(last) else { return text }
        return text + "."
    }
}
