import Foundation

/// `leisure.json` beside `sessions.json`: watching or listening outside a session, each finished run written
/// once. Its own file, so nothing that reads the session archive counts it. The data folder's backups carry
/// it. A file that cannot be read is set aside as the other stores do, and one a newer Daybook wrote is left
/// exactly as it is.
final class LeisureStore {
    static let fileName = "leisure.json"

    private struct File: Codable {
        var version = 1
        var blocks: [LeisureBlock]
    }
    private struct Stamp: Decodable { let version: Int? }

    private let url: URL
    private(set) var blocks: [LeisureBlock] = []
    /// Why nothing is written. While set, the file on disk may be the only copy of what it holds.
    private(set) var failure: String?

    init(directory: URL, now: Date = Date()) {
        url = directory.appendingPathComponent(Self.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            if let version = (try? JSONDecoder().decode(Stamp.self, from: data))?.version, version != 1 {
                failure = "Leisure was written by a newer version of Daybook. Its file was kept."
                return
            }
            // A block that could not have been written (backwards, endless) is dropped, not drawn.
            let read = try JSONDecoder().decode(File.self, from: data).blocks
            blocks = read.filter { $0.end > $0.start && $0.end.timeIntervalSince($0.start) <= 86_400 }
            if blocks.count < read.count { Diagnostics.log("leisure.json: \(read.count - blocks.count) impossible blocks dropped") }
        } catch {
            if UnreadableFile.setAside(url, prefix: "leisure-corrupt-", pathExtension: "json", at: now) == nil {
                failure = "Leisure couldn't be read. \(error.localizedDescription.endingInFullStop) Its file was kept."
            }
            Diagnostics.log("leisure.json unreadable: \(error)")
        }
    }

    /// Adds the blocks that overlap none already kept. Nil when saved or nothing was new, else why not.
    @discardableResult
    func add(_ found: [LeisureBlock]) -> String? {
        let fresh = found.filter { block in !blocks.contains { $0.start < block.end && block.start < $0.end } }
        guard !fresh.isEmpty else { return nil }
        if let failure { return failure }
        let next = (blocks + fresh).sorted { $0.start < $1.start }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(File(blocks: next)).write(to: url, options: .atomic)
            blocks = next
            return nil
        } catch {
            return "Leisure couldn't be saved. \(error.localizedDescription.endingInFullStop)"
        }
    }
}
