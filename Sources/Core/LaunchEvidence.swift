import Foundation

/// What a launch can find out about how the previous run ended, beyond the
/// run's own marker: which boot this is, the reports macOS writes when an app
/// crashes or the kernel panics, the macOS version, and when the login session
/// at the Mac's own screen began. Gathered once at launch.
struct LaunchEvidence {
    /// A Daybook crash report: when it was written and which process it is
    /// about, when its body says.
    struct CrashReport: Equatable {
        let date: Date
        let pid: Int32?
    }

    let bootSessionID: String
    let bootTime: Date
    let crashReports: [CrashReport]
    /// Modification dates of kernel panic reports. That folder is readable by
    /// administrators only; for anyone else this is empty, and a panic reads
    /// as a power loss.
    let panicReports: [Date]
    let now: Date
    /// macOS's version and build, e.g. "27.2 (26B5101f)". A boot on a
    /// different one followed an update.
    var osVersion = ""
    /// When the login session at the Mac's own screen began. A log out ends
    /// it, so one that began after Daybook quit means the log out went ahead.
    var consoleLogin: Date?

    static let crashFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    static let panicFolder = URL(fileURLWithPath: "/Library/Logs/DiagnosticReports", isDirectory: true)

    /// Nil only when the kernel will not name this boot, and then nothing
    /// about the previous run can be worked out.
    static func gather(now: Date) -> LaunchEvidence? {
        guard let boot = BootSession.current() else { return nil }
        return LaunchEvidence(
            bootSessionID: boot.id, bootTime: boot.start,
            crashReports: crashReports(in: crashFolder),
            panicReports: reports(in: panicFolder, prefix: "", pathExtension: "panic").map(\.date),
            now: now, osVersion: SystemFacts.osVersion, consoleLogin: SystemFacts.consoleLogin())
    }

    static func crashReports(in folder: URL) -> [CrashReport] {
        reports(in: folder, prefix: "Daybook", pathExtension: "ips").map {
            CrashReport(date: $0.date, pid: processID(in: $0.url))
        }
    }

    /// Each report in `folder` whose name starts with `prefix` and ends in
    /// `pathExtension`, oldest first by when it was last written. A missing
    /// or unreadable folder has none.
    static func reports(in folder: URL, prefix: String,
                        pathExtension: String) -> [(url: URL, date: Date)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names
            .filter { $0.hasPrefix(prefix) && ($0 as NSString).pathExtension == pathExtension }
            .compactMap { name -> (url: URL, date: Date)? in
                let url = folder.appendingPathComponent(name)
                guard let date = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]
                        as? Date else { return nil }
                return (url, date)
            }
            .sorted { $0.date < $1.date }
    }

    /// The `"pid"` an `.ips` report gives near the top of its body. Only the
    /// first 4 KB is read; a report without one is matched by time alone.
    static func processID(in report: URL) -> Int32? {
        guard let handle = try? FileHandle(forReadingFrom: report) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4_096) else { return nil }
        let text = String(decoding: head, as: UTF8.self)
        guard let field = text.range(of: "\"pid\" : ") else { return nil }
        return Int32(text[field.upperBound...].prefix(while: \.isNumber))
    }
}

/// This boot, as the kernel names it. `kern.bootsessionuuid` is new at every
/// boot, so unlike the boot time it cannot be moved by a clock change.
enum BootSession {
    static func current() -> (id: String, start: Date)? {
        guard let id = SystemFacts.kernelString("kern.bootsessionuuid"), !id.isEmpty else { return nil }
        var time = timeval()
        var length = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &time, &length, nil, 0) == 0 else { return nil }
        let start = Date(timeIntervalSince1970: TimeInterval(time.tv_sec)
                         + TimeInterval(time.tv_usec) / 1_000_000)
        return (id, start)
    }
}

/// Small facts about this Mac that the launch evidence reads.
enum SystemFacts {
    /// "27.2 (26B5101f)": the version people know, and the build, which also
    /// changes for a security update that leaves the version alone.
    static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let name = "\(version.majorVersion).\(version.minorVersion)"
            + (version.patchVersion > 0 ? ".\(version.patchVersion)" : "")
        return kernelString("kern.osversion").map { "\(name) (\($0))" } ?? name
    }

    /// When `user`'s session at the Mac's own screen began, from the login
    /// records macOS keeps (the ones `last` reads). Nil when there is none.
    static func consoleLogin(of user: String = NSUserName()) -> Date? {
        setutxent()
        defer { endutxent() }
        var latest: Date?
        while let entry = getutxent() {
            let record = entry.pointee
            guard Int32(record.ut_type) == USER_PROCESS, text(record.ut_line) == "console",
                  text(record.ut_user) == user else { continue }
            let began = Date(timeIntervalSince1970: TimeInterval(record.ut_tv.tv_sec)
                             + TimeInterval(record.ut_tv.tv_usec) / 1_000_000)
            latest = max(latest ?? began, began)
        }
        return latest
    }

    static func kernelString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// A fixed-size C character field, up to its first zero.
    private static func text<Field>(_ field: Field) -> String {
        withUnsafeBytes(of: field) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
