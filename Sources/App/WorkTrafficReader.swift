import AppKit
import Darwin

/// One reading for `WorkTraffic`: bytes sent and processor time used per
/// process, and the app each process belongs to. Bytes come from macOS's own
/// `nettop`, processor time from `proc_pid_rusage`; neither needs root or any
/// permission for the user's own processes, and the pair costs about 0.05 s
/// of CPU. Run off the main thread; which apps count is decided on it, where
/// `PurposeMap` and the session's app record live.
enum WorkTrafficReader {
    struct Reading {
        /// Nil when `nettop` could not be read; processor time still is.
        let sent: [Int32: UInt64]?
        /// Nanoseconds of processor time, children that have exited included,
        /// so a build's short-lived compilers count.
        let cpu: [Int32: UInt64]
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
        let sent = readSent()
        let cpu = readCPU()
        var apps: [Int32: String] = [:]
        var topApps: [Int32: String?] = [:]
        for pid in Set(sent.map { Array($0.keys) } ?? []).union(cpu.keys) {
            let top = topLevelProcess(of: pid)
            if topApps[top] == nil {
                topApps[top] = NSRunningApplication(processIdentifier: top)?.bundleIdentifier
            }
            if let app = topApps[top] ?? nil { apps[pid] = app }
        }
        return Reading(sent: sent, cpu: cpu, apps: apps)
    }

    private static func readSent() -> [Int32: UInt64]? {
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
        return WorkTraffic.totals(fromNettop: String(decoding: data, as: UTF8.self))
    }

    private static let nanosecondsPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom)
    }()

    private static func readCPU() -> [Int32: UInt64] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [:] }
        var pids = [Int32](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<Int32>.size)))
        var cpu: [Int32: UInt64] = [:]
        for pid in pids.prefix(max(0, count)) where pid > 0 {
            var usage = rusage_info_v2()
            let status = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            guard status == 0 else { continue }
            let ticks = usage.ri_user_time + usage.ri_system_time
                + usage.ri_child_user_time + usage.ri_child_system_time
            cpu[pid] = UInt64(Double(ticks) * nanosecondsPerTick)
        }
        return cpu
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
