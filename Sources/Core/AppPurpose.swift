import Foundation

/// What an app is *for*. The third and last classification axis, deliberately
/// separate from the two that already exist:
///
/// - `AppCategory` answers "should this app pause my session?"
/// - `WorkType` answers "what did the user say this session was?"
/// - `AppPurpose` answers "what is this tool?"
///
/// Collapsing any pair breaks something: Terminal and Figma are both `.work`,
/// but one is coding and the other design.
enum AppPurpose: String, Codable, CaseIterable {
    case coding, writingAI, design, communication, research, media, utility

    var displayName: String {
        switch self {
        case .coding: return "Coding"
        case .writingAI: return "Writing & AI"
        case .design: return "Design"
        case .communication: return "Communication"
        case .research: return "Research"
        case .media: return "Media"
        case .utility: return "Utility"
        }
    }

    var symbolName: String {
        switch self {
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .writingAI: return "sparkles"
        case .design: return "paintbrush.pointed.fill"
        case .communication: return "bubble.left.and.bubble.right.fill"
        case .research: return "magnifyingglass"
        case .media: return "play.rectangle.fill"
        case .utility: return "wrench.and.screwdriver.fill"
        }
    }

    /// Purposes that constitute focused work. `research` is excluded on purpose:
    /// it supports deep work, but a day of only reading is not a day of making.
    var isFocused: Bool {
        switch self {
        case .coding, .writingAI, .design: return true
        case .communication, .research, .media, .utility: return false
        }
    }
}

/// How an app's purpose is decided.
enum PurposeRule: Equatable {
    /// Always this, whatever the user is doing.
    case fixed(AppPurpose)
    /// Decided by behaviour. Browsers and AI clients carry no fixed purpose, and
    /// without an Accessibility grant the app can never read the URL or window
    /// title to find out — so it reads input instead.
    case ambiguous(active: AppPurpose, passive: AppPurpose)
}

enum PurposeMap {

    /// Code-constant. Only bundle identifiers that are known-good go here;
    /// guessing an identifier would silently misfile an app forever.
    static let rules: [String: PurposeRule] = [
        // Coding
        "com.apple.dt.Xcode": .fixed(.coding),
        "com.microsoft.VSCode": .fixed(.coding),
        "com.microsoft.VSCodeInsiders": .fixed(.coding),
        "com.todesktop.230313mzl4w4u92": .fixed(.coding),   // Cursor
        "com.jetbrains.WebStorm": .fixed(.coding),
        "com.apple.Terminal": .fixed(.coding),
        "com.googlecode.iterm2": .fixed(.coding),
        "dev.warp.Warp-Stable": .fixed(.coding),
        "com.google.antigravity": .fixed(.coding),
        "com.google.antigravity-ide": .fixed(.coding),
        "com.mongodb.compass": .fixed(.coding),
        "com.docker.docker": .fixed(.coding),
        "com.tinyapp.TablePlus": .fixed(.coding),
        "com.postmanlabs.mac": .fixed(.coding),
        "com.github.GitHubClient": .fixed(.coding),

        // Writing and AI
        "com.anthropic.claudefordesktop": .fixed(.writingAI),
        "com.google.GeminiMacOS": .fixed(.writingAI),
        "com.openai.chat": .fixed(.writingAI),
        "notion.id": .fixed(.writingAI),
        "com.apple.Notes": .fixed(.writingAI),

        // Design
        "com.figma.Desktop": .fixed(.design),
        "com.bohemiancoding.sketch3": .fixed(.design),
        "com.adobe.Photoshop": .fixed(.design),

        // Communication
        "us.zoom.xos": .fixed(.communication),
        "com.microsoft.teams2": .fixed(.communication),
        "com.tinyspeck.slackmacgap": .fixed(.communication),
        "com.apple.iChat": .fixed(.communication),
        "com.apple.mail": .fixed(.communication),

        // Media
        "com.netflix.Netflix": .fixed(.media),
        "com.apple.TV": .fixed(.media),
        "com.apple.Music": .fixed(.media),
        "com.spotify.client": .fixed(.media),
        "org.videolan.vlc": .fixed(.media),
        "com.valvesoftware.steam": .fixed(.media),
        "com.hnc.Discord": .fixed(.media),

        // Utility
        "com.apple.finder": .fixed(.utility),
        "com.apple.systemsettings": .fixed(.utility),
        "com.apple.systempreferences": .fixed(.utility),

        // Ambiguous — the whole reason `InputDensity` exists.
        "com.google.Chrome": .ambiguous(active: .research, passive: .media),
        "com.apple.Safari": .ambiguous(active: .research, passive: .media),
        "org.mozilla.firefox": .ambiguous(active: .research, passive: .media),
        "company.thebrowser.Browser": .ambiguous(active: .research, passive: .media),
        "company.thebrowser.dia": .ambiguous(active: .writingAI, passive: .media)
    ]

    /// Set once by the App layer: bundle id → the category the app declares
    /// about itself (`LSApplicationCategoryType`). Core cannot look inside app
    /// bundles. The value is a hint of last resort — a rule or an override
    /// always wins, it is self-reported, and many apps outside the App Store
    /// declare nothing at all (Dia and Chrome among them).
    static var declaredCategory: (String) -> String? = { _ in nil }

    /// An app whose purpose is behaviour-decided — in practice, a browser or
    /// an AI client. Named work in one of these is "Browsing", not the tool.
    static func isAmbiguous(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        if case .ambiguous = rules[bundleID] { return true }
        return false
    }

    /// What an App Store category says about purpose, for apps the rules do
    /// not know. Deliberately partial: a category that says nothing useful
    /// returns nil and the caller keeps `.utility` — never guess focus out of
    /// a label like "productivity"... except that productivity tools are, in
    /// fact, where unmapped writing apps live, so that one maps.
    static func categoryFallback(_ category: String?) -> AppPurpose? {
        guard let category else { return nil }
        switch category {
        case "public.app-category.developer-tools":
            return .coding
        case "public.app-category.graphics-design",
             "public.app-category.photography":
            return .design
        case "public.app-category.productivity":
            return .writingAI
        case "public.app-category.education",
             "public.app-category.reference",
             "public.app-category.news":
            return .research
        case "public.app-category.social-networking",
             "public.app-category.business":
            return .communication
        case "public.app-category.music",
             "public.app-category.entertainment",
             "public.app-category.video",
             "public.app-category.games":
            return .media
        default:
            return nil
        }
    }

    /// Precedence: user override → rule → declared category → `.utility`. An
    /// unmapped, unlabelled app is far more often a utility than anything
    /// else, and a name describing the common case reads better in the UI
    /// than one describing a lookup failure.
    static func purpose(for bundleID: String?,
                        activity: InputActivity,
                        overrides: [String: String] = [:]) -> AppPurpose {
        guard let bundleID, !bundleID.isEmpty else { return .utility }
        if let raw = overrides[bundleID], let override = AppPurpose(rawValue: raw) {
            return override
        }
        switch rules[bundleID] {
        case .fixed(let purpose):
            return purpose
        case .ambiguous(let active, let passive):
            // An absent user is not doing research.
            return activity == .active ? active : passive
        case nil:
            return categoryFallback(declaredCategory(bundleID)) ?? .utility
        }
    }
}
