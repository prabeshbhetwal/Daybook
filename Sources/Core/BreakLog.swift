import Foundation

/// Which prompt a reminder showed: the buttonless eyes glance, the main break
/// prompt, the long break (phase 2's Pomodoro; nothing produces it yet) or the
/// long-stretch guard.
enum BreakPromptKind: String, Codable {
    case eyes, main, long, stretchGuard

    static func of(_ tier: BreakTier) -> BreakPromptKind {
        switch tier {
        case .micro: return .eyes
        case .cognitive: return .main
        case .ultradian: return .stretchGuard
        }
    }
}

/// What became of a shown reminder. `later` is the state between a Later and
/// whatever answer follows it.
enum BreakPromptOutcome: String, Codable {
    case started, left, later, skipped, unanswered, held, credited
}

/// One reminder that was shown, how often it was put off, and how it ended.
struct BreakPromptEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let kind: BreakPromptKind
    let due: Date
    let shown: Date
    var laterCount = 0
    var outcome: BreakPromptOutcome?
    var outcomeAt: Date?
    // Phase 3: a reminder held back while the person was busy.
    var heldSeconds: TimeInterval?
    var holdReasons: [String]?
}

/// The break rhythm in force on one day. `preset` is a `BreakPreset` raw value
/// or "off" (no main rhythm that day); nil means a phase-1 build wrote it, from
/// the three switches alone.
struct BreakRhythmSnapshot: Codable, Equatable {
    var workMinutes: Int?
    var breakMinutes: Int?
    var eyes: Bool
    var guardMinutes: Int?
    var override: String?
    var preset: String?
    var longEvery: Int?
    var longMinutes: Int?

    /// No main rhythm, no Eyes, no guard.
    static let off = BreakRhythmSnapshot(eyes: false, preset: "off")
}

/// One day: its rhythm, and how many eyes prompts it showed.
struct BreakDay: Codable, Equatable {
    let day: Date
    var rhythm: BreakRhythmSnapshot
    var eyesPrompts: Int
}

/// Every break reminder shown, its Later count and outcome, and the rhythm in
/// force each day, in `break-log.json` for the break analytics to read.
///
/// Modelled on `AmbientPowerLog`: a versioned document, an atomic write, and a
/// file that cannot be read is left alone. Entries older than
/// `retentionDays` go on each write, counted from the moment that write
/// carries, so the log needs no clock of its own. `Core` only.
final class BreakLog {
    private struct Document: Codable {
        let version: Int
        var prompts: [BreakPromptEntry]
        var days: [BreakDay]
    }

    static let fileName = "break-log.json"
    static let retentionDays = 400

    private let directory: URL
    private let fileURL: URL
    private let calendar: Calendar
    private let writeOverride: ((Data) -> String?)?
    private(set) var prompts: [BreakPromptEntry] = []
    private(set) var days: [BreakDay] = []
    /// Why the file on disk could not be read. It may be the only copy of the
    /// log, so while this is set nothing is written over it.
    private var loadFailure: String?

    init(directory: URL = SessionArchive.defaultDirectory, calendar: Calendar = .current,
         writeOverride: ((Data) -> String?)? = nil) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent(Self.fileName)
        self.calendar = calendar
        self.writeOverride = writeOverride
        load()
    }

    @discardableResult
    func recordShown(_ entry: BreakPromptEntry) -> String? {
        guard !prompts.contains(where: { $0.id == entry.id }) else { return nil }
        prompts.append(entry)
        prompts.sort { $0.shown < $1.shown }
        return commit(at: entry.shown)
    }

    @discardableResult
    func setOutcome(_ outcome: BreakPromptOutcome, for id: UUID, at moment: Date) -> String? {
        guard let index = prompts.firstIndex(where: { $0.id == id }) else { return nil }
        prompts[index].outcome = outcome
        prompts[index].outcomeAt = moment
        return commit(at: moment)
    }

    /// A Later: counts it and leaves the reminder in the `later` state until
    /// the answer that follows.
    @discardableResult
    func noteLater(for id: UUID, at moment: Date) -> String? {
        guard let index = prompts.firstIndex(where: { $0.id == id }) else { return nil }
        prompts[index].laterCount += 1
        prompts[index].outcome = .later
        prompts[index].outcomeAt = moment
        return commit(at: moment)
    }

    /// The rhythm in force on `moment`'s day. A day already holding this
    /// rhythm is not written again.
    @discardableResult
    func noteRhythm(_ rhythm: BreakRhythmSnapshot, on moment: Date) -> String? {
        let day = calendar.startOfDay(for: moment)
        if let index = days.firstIndex(where: { $0.day == day }) {
            guard days[index].rhythm != rhythm else { return nil }
            days[index].rhythm = rhythm
        } else {
            days.append(BreakDay(day: day, rhythm: rhythm, eyesPrompts: 0))
            days.sort { $0.day < $1.day }
        }
        return commit(at: moment)
    }

    /// An eyes prompt on `moment`'s day. A day nobody noted a rhythm for yet
    /// starts from the latest earlier rhythm, or one that records only that
    /// Eyes was on.
    @discardableResult
    func noteEyesPrompt(at moment: Date) -> String? {
        let day = calendar.startOfDay(for: moment)
        if let index = days.firstIndex(where: { $0.day == day }) {
            days[index].eyesPrompts += 1
        } else {
            let inherited = days.last(where: { $0.day < day })?.rhythm
                ?? BreakRhythmSnapshot(eyes: true)
            days.append(BreakDay(day: day, rhythm: inherited, eyesPrompts: 1))
            days.sort { $0.day < $1.day }
        }
        return commit(at: moment)
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: fileURL))
            guard document.version == 1 else {
                loadFailure = "The break log was written by a newer version and remains read-only."
                Diagnostics.log(loadFailure ?? "")
                return
            }
            prompts = document.prompts.sorted { $0.shown < $1.shown }
            days = document.days.sorted { $0.day < $1.day }
        } catch {
            loadFailure = "The break log could not be read. The original file was preserved."
            Diagnostics.log("\(loadFailure ?? ""): \(error)")
        }
    }

    private func commit(at moment: Date) -> String? {
        if let loadFailure { return loadFailure }
        if let horizon = calendar.date(byAdding: .day, value: -Self.retentionDays,
                                       to: calendar.startOfDay(for: moment)) {
            prompts.removeAll { $0.shown < horizon }
            days.removeAll { $0.day < horizon }
        }
        do {
            let data = try JSONEncoder().encode(Document(version: 1, prompts: prompts, days: days))
            if let writeOverride {
                if let error = writeOverride(data) {
                    Diagnostics.log("break log not saved: \(error)")
                    return error
                }
            } else {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: fileURL, options: .atomic)
            }
            return nil
        } catch {
            let message = "The break log could not be saved: \(error.localizedDescription)"
            Diagnostics.log(message)
            return message
        }
    }
}
