import AppKit
import Darwin

/// Reads a process's parent and app identity for `OwningApp`.
enum ProcessLookup {
    /// `proc_pidinfo(PROC_PIDTBSDINFO)` for the parent; `NSRunningApplication` for the bundle id and policy.
    /// Nil when the process no longer exists.
    static func info(_ pid: Int32) -> ProcessInfoLite? {
        var bsd = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size else { return nil }
        let app = NSRunningApplication(processIdentifier: pid)
        return ProcessInfoLite(pid: pid, parent: Int32(bitPattern: bsd.pbi_ppid), bundleID: app?.bundleIdentifier,
                               isRegularApp: app?.activationPolicy == .regular)
    }

    static func runningRegularApps() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier))
    }
}
