import Foundation

/// What kind of site a browser tab is on. Only the kind is ever kept; the
/// address it came from is dropped where it is read. Sensitive sites (banking,
/// health, government, sign-in, adult) are deliberately not cases here: they
/// give no signal at all, so no value exists that could record one.
enum SiteKind: String, Codable, CaseIterable {
    case video, documentation, codeHost, social, shopping, mail, aiChat, meeting

    var displayName: String {
        switch self {
        case .video: return "Video"
        case .documentation: return "Documentation"
        case .codeHost: return "Code host"
        case .social: return "Social"
        case .shopping: return "Shopping"
        case .mail: return "Mail"
        case .aiChat: return "AI chat"
        case .meeting: return "Meeting"
        }
    }

    /// Leisure kinds read as media whether or not the person is typing; the
    /// others read like an app with that one purpose.
    var rule: PurposeRule {
        switch self {
        case .video, .social, .shopping: return .ambiguous(active: .media, passive: .media)
        case .documentation: return .fixed(.research)
        case .codeHost: return .fixed(.coding)
        case .mail, .meeting: return .fixed(.communication)
        case .aiChat: return .fixed(.writingAI)
        }
    }

    var isLeisure: Bool {
        switch self {
        case .video, .social, .shopping: return true
        case .documentation, .codeHost, .mail, .aiChat, .meeting: return false
        }
    }
}
