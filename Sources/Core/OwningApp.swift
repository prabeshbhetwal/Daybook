import Foundation

/// What the resolver needs to know about one process, read by the App layer.
struct ProcessInfoLite: Equatable {
    let pid: Int32
    let parent: Int32?
    let bundleID: String?
    let isRegularApp: Bool
}

/// Names the app a process works for, so a browser's helper that holds the screen awake
/// reads as the browser and nothing else reads as one.
enum OwningApp {
    private static let maxParents = 4

    /// Itself if a regular app; else the nearest regular ancestor within 4 parents; else the
    /// running regular app whose bundle id is the longest dot-separated prefix of this one's
    /// (com.google.Chrome.helper → com.google.Chrome); else nil.
    static func resolve(_ process: ProcessInfoLite, lookup: (Int32) -> ProcessInfoLite?,
                        runningApps: Set<String>) -> String? {
        if process.isRegularApp { return process.bundleID }
        var seen: Set<Int32> = [process.pid]
        var next = process.parent
        for _ in 0..<maxParents {
            // Pid 1 is the launch daemon: every orphan hangs off it, so it names nobody.
            guard let pid = next, pid > 1, seen.insert(pid).inserted, let parent = lookup(pid) else { break }
            if parent.isRegularApp, let id = parent.bundleID { return id }
            next = parent.parent
        }
        return byPrefix(process.bundleID, runningApps)
    }

    /// Matches whole components: com.google.Chrome does not own com.google.ChromeX.helper.
    private static func byPrefix(_ bundleID: String?, _ runningApps: Set<String>) -> String? {
        guard let bundleID else { return nil }
        return runningApps
            .filter { bundleID == $0 || bundleID.hasPrefix($0 + ".") }
            .max { $0.count < $1.count }
    }
}
