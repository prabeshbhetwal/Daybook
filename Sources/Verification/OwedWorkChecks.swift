import Foundation
/// Work a correction owes is kept in the correction journal, which also holds the receipts Undo needs. A build
/// that does not know a kind of step, because a newer one wrote it, must still read the journal.
enum OwedWorkChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Owed work holding a step this build does not know reads as nothing to do, and the journal holding it still reads",
         unknownStepIsNotFatal),
    ]

    private static func unknownStepIsNotFatal() -> [String] {
        var problems: [String] = []
        let id = UUID()
        let work = #"{"id":"\#(id.uuidString)","steps":[{"teleport":{"record":"\#(UUID().uuidString)"}}]}"#
        let read = try? JSONDecoder().decode(OwedWork.self, from: Data(work.utf8))
        expect(read?.id == id && read?.steps.isEmpty == true, "work with an unknown step read as \(String(describing: read))", &problems)
        let journal = #"{"version":1,"fields":[],"owed":[\#(work)]}"#
        let document = try? JSONDecoder().decode(DecisionHistory.Document.self, from: Data(journal.utf8))
        expect(document?.owed?.count == 1, "a journal holding work with an unknown step could not be read", &problems)
        return problems
    }
}
