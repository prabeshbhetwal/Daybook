import AppKit
import Darwin

/// One `nettop` reading for `WorkTraffic`: bytes sent per process, and the
/// app each process belongs to. macOS's own tool, run off the main thread; it
/// reports counts without root or any permission, for about 0.04 s of CPU.
/// Which of those apps are work apps is decided on the main thread, where
/// `PurposeMap` lives.
enum WorkTrafficReader {
    struct Reading {
        let totals: [Int32: UInt64]
        /// The bundle identifier of the app each process descends from.
        let apps: [Int32: String]
    }

    private static let queue = DispatchQueue(label: "com.prabesh.daybook.work-traffic", qos: .utility)

    /// Reads on a background queue and hands the result to `completion` on the main queue.
    static func read(_ completion: @escaping @MainActor (Reading?) -> Void) {
        queue.async {
            let reading = readNow()
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(reading) } }
        }
    }

    private static func readNow() -> Reading? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-L", "1", "-x", "-J", "bytes_out"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // A reading takes a tenth of a second; one that hangs is killed, not
        // asked to stop, or it would hold `queue` and end readings for good.
        let deadline = DispatchWorkItem { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        // Not on `queue`: it is busy right here, waiting for this reading.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: deadline)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        guard process.terminationStatus == 0 else { return nil }
        let totals = WorkTraffic.totals(fromNettop: String(decoding: data, as: UTF8.self))
        var apps: [Int32: String] = [:]
        var topApps: [Int32: String?] = [:]
        for pid in totals.keys {
            let top = topLevelProcess(of: pid)
            if topApps[top] == nil {
                topApps[top] = NSRunningApplication(processIdentifier: top)?.bundleIdentifier
            }
            if let app = topApps[top] ?? nil { apps[pid] = app }
        }
        return Reading(totals: totals, apps: apps)
    }

    /// The process an app's helpers, shells and agents all descend from: the
    /// ancestor launchd started. A command-line agent in a terminal belongs to
    /// the terminal; an IDE's helpers to the IDE.
    private static func topLevelProcess(of pid: Int32) -> Int32 {
        var current = pid
        for _ in 0..<64 {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(current, PROC_PIDTBSDINFO, 0, &info, size) == size else { break }
            let parent = Int32(info.pbi_ppid)
            if parent <= 1 { break }
            current = parent
        }
        return current
    }
}
