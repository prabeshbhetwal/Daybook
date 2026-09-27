import Foundation

/// Moves history that cannot be read out of the way, under a name no earlier
/// set-aside file already holds. A nil result means the bytes are still where
/// they were: they may be the only copy of that history, so the caller must stop
/// writing rather than start a fresh file over them.
enum UnreadableFile {
    static func setAside(_ url: URL, prefix: String, pathExtension: String, at date: Date) -> URL? {
        let directory = url.deletingLastPathComponent()
        let stamp = Int(date.timeIntervalSince1970)
        // ponytail: 100 same-second collisions is not a real history; past that
        // the caller goes read-only, which loses nothing.
        for attempt in 1...100 {
            let suffix = attempt == 1 ? "" : "-\(attempt)"
            let aside = directory.appendingPathComponent("\(prefix)\(stamp)\(suffix).\(pathExtension)")
            guard !FileManager.default.fileExists(atPath: aside.path) else { continue }
            do {
                try FileManager.default.moveItem(at: url, to: aside)
                return aside
            } catch {
                return nil
            }
        }
        return nil
    }
}
