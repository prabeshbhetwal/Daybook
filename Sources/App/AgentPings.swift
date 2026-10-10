import Foundation
import notify

/// Hears the ping an AI agent's hook posts (`notifyutil -p <pingName>`) as it
/// starts and finishes each step. A Darwin notification: no file, no port, no
/// permission, and nothing left behind when Daybook is not running.
enum AgentPings {
    private static var token: Int32 = NOTIFY_TOKEN_INVALID

    /// Calls `onPing` on the main queue for every ping, for the app's lifetime.
    static func listen(_ onPing: @escaping @MainActor () -> Void) {
        guard token == NOTIFY_TOKEN_INVALID else { return }
        notify_register_dispatch(AgentPresence.pingName, &token, .main) { _ in
            MainActor.assumeIsolated { onPing() }
        }
    }
}
