import Foundation

/// One Daybook at a time: a second copy cannot take the data folder's lock
/// while the first holds it, and gets it once the first is gone.
enum InstanceLockChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A second copy cannot take the data folder while one runs, and can once it ends", secondCopyRefused),
    ]

    private static func secondCopyRefused() -> [String] {
        var problems: [String] = []
        let folder = SelfTest.scratchDirectory()
        guard case .acquired(let first) = InstanceLock.acquire(in: folder) else {
            return ["the first copy did not get the lock"]
        }
        // A separate open is a separate lock, as it is in another process.
        let second = InstanceLock.acquire(in: folder)
        expect(second == .heldElsewhere, "a second copy is refused while the first runs, got \(second)", &problems)
        close(first)
        let third = InstanceLock.acquire(in: folder)
        if case .acquired(let descriptor) = third { close(descriptor) } else {
            problems.append("once the first copy ends the lock is free, got \(third)")
        }
        let file = folder.appendingPathComponent("not-a-folder")
        try? Data().write(to: file)
        let blocked = InstanceLock.acquire(in: file)
        expect(blocked == .unavailable, "a lock that cannot be opened lets the app start, got \(blocked)", &problems)
        return problems
    }
}
