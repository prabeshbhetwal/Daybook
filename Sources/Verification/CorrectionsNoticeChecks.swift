import Foundation

/// A category change that could not be remembered says so on screen, as a refused write of any other store
/// does: a newer Daybook's corrections file, kept read-only, used to stop every lesson with a line in the log only.
enum CorrectionsNoticeChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A category change that can't be remembered stands, and says why on screen", unrememberedChangeSaysWhy),
    ]

    private static func unrememberedChangeSaysWhy() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let (store, clock, suite) = CorrectionsStoreChecks.make()
            defer { MemoryDefaults.remove(named: suite) }
            let url = store.engine.archive.dataDirectoryURL.appendingPathComponent(CorrectionsStore.fileName)
            let newer = Data("{\"version\":2,\"entries\":[]}".utf8)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? newer.write(to: url)
            guard let session = CorrectionsStoreChecks.ended(store, clock, begin: CorrectionsStoreChecks.automatic("Parser")) else {
                return ["no session was made"]
            }
            expect(store.setWorkType(.learning, for: session), "the category change was refused", &problems)
            expect(CorrectionsStoreChecks.record(session, in: store)?.workType == .learning,
                   "the category change did not stand", &problems)
            expect(store.correctionError?.contains("newer version of Daybook") == true,
                   "nothing on screen said the choice was not remembered: \(store.correctionError ?? "no message")", &problems)
            expect((try? Data(contentsOf: url)) == newer, "the newer version's file was changed", &problems)

            // Once the file can be written again, a change says nothing.
            let (well, wellClock, wellSuite) = CorrectionsStoreChecks.make()
            defer { MemoryDefaults.remove(named: wellSuite) }
            guard let other = CorrectionsStoreChecks.ended(well, wellClock, begin: CorrectionsStoreChecks.automatic("Router")) else {
                return problems + ["no second session was made"]
            }
            expect(well.setWorkType(.learning, for: other) && well.correctionError == nil,
                   "a remembered change showed \(well.correctionError ?? "a refusal")", &problems)
            return problems
        }
    }
}
