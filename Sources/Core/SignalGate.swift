import Foundation

/// Phase D's site kind is the only signal; Phase A reads none.
enum SignalKind: String, Codable, CaseIterable { case siteKind }

/// A signal claims nothing until a committed probe report shows it reads true
/// on a macOS major. Evidence, not hope, turns one on: a line is added to
/// `passing` in the same commit as its passing report under `docs/debug/`.
enum SignalGate {
    /// Signal to the macOS majors a committed probe report passed on. Empty until one does.
    static let passing: [SignalKind: Set<Int>] = [:]

    static func isOn(_ signal: SignalKind, macOSMajor: Int) -> Bool {
        passing[signal]?.contains(macOSMajor) ?? false
    }
}
