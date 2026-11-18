import Foundation

/// Which kind a site belongs to. Public, well-known hosts only; the person can
/// add their own in Settings. A sensitive site gives no kind from anywhere.
enum SiteKindTable {

    /// Most specific level first, from the full host to its parent domains. At
    /// each level a remembered entry wins over the built-in table. A sensitive
    /// entry anywhere in the chain gives nil.
    static func kind(forSite siteName: String, remembered: [String: SiteKind]) -> SiteKind? {
        guard !isSensitive(siteName) else { return nil }
        for level in levels(of: siteName) {
            if let kind = remembered[level] ?? builtIn[level] { return kind }
        }
        return nil
    }

    static func isSensitive(_ siteName: String) -> Bool {
        let labels = labels(of: siteName)
        guard let last = labels.last else { return false }
        if levels(of: siteName).contains(where: sensitiveHosts.contains) { return true }
        if governmentLastLabels.contains(last) { return true }
        if labels.count >= 2, governmentSecondLabels.contains(labels[labels.count - 2]) { return true }
        if labels.suffix(2) == ["gc", "ca"] { return true }
        // The last label is the top-level domain: `example.id` is not a sign-in page.
        return !signInLabels.isDisjoint(with: labels.dropLast())
    }

    private static func labels(of siteName: String) -> [String] {
        siteName.lowercased().split(separator: ".").map(String.init)
    }

    /// "a.b.c", "b.c", "c".
    private static func levels(of siteName: String) -> [String] {
        let parts = labels(of: siteName)
        return parts.indices.map { parts[$0...].joined(separator: ".") }
    }

    // Rule-based sensitivity: government and sign-in pages the fixed list cannot
    // name. Over-matching only loses a signal; it never leaks one.
    private static let governmentLastLabels: Set<String> = ["gov", "mil"]
    private static let governmentSecondLabels: Set<String> = ["gov", "govt", "gouv", "gob", "gv", "go", "mil"]
    private static let signInLabels: Set<String> = [
        "login", "signin", "sign-in", "signup", "auth", "oauth", "sso", "account", "accounts",
        "myaccount", "id", "idp", "passport", "password", "secure", "banking",
    ]

    private static let builtIn: [String: SiteKind] = {
        var table: [String: SiteKind] = [:]
        for (kind, hosts) in builtInHosts { for host in hosts { table[host] = kind } }
        return table
    }()

    private static let sensitiveHosts: Set<String> = Set(sensitiveHostList)
}
