import Foundation

/// The one place a web address is reduced to a site name. Nothing here keeps,
/// logs or returns the address, and the path, query and fragment are never read.
enum SiteAddress {

    /// http or https only; the host, lowercased, without a trailing dot, a port,
    /// user info or a leading "www.". nil for anything else.
    static func siteName(fromAddress address: String) -> String? {
        guard let parts = URLComponents(string: address),
              let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = parts.host?.lowercased() else { return nil }
        while host.hasSuffix(".") { host.removeLast() }
        // "www.com" is a site, not "www" in front of "com".
        if host.hasPrefix("www."), host.dropFirst(4).contains(".") { host.removeFirst(4) }
        return host.isEmpty ? nil : host
    }

    /// A name the person typed for Remember sites: a bare host or a full address,
    /// normalised the same way. nil unless it has at least two labels of
    /// letters, digits or hyphens.
    static func normalisedSiteName(_ typed: String) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        // An address starts with a scheme; "://" later on belongs to a query.
        let hasScheme = trimmed.range(of: "://").map { range in
            trimmed[..<range.lowerBound].allSatisfy { $0.isLetter || $0.isNumber || "+.-".contains($0) }
        } ?? false
        // "@" is an email address or user info, never a site name someone types.
        guard !trimmed.contains("@"),
              let name = siteName(fromAddress: hasScheme ? trimmed : "https://" + trimmed) else { return nil }
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        guard labels.count >= 2,
              labels.allSatisfy({ !$0.isEmpty && $0.allSatisfy(allowed.contains) }) else { return nil }
        return name
    }
}
