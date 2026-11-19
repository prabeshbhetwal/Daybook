import Foundation

/// Activity-aware sessions, phase D: the kind of site a web address belongs to.
/// Only fictional and public hosts appear here; no real browsing.
enum SiteKindChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Every site kind reads as its purpose", kindsReadAsPurposes),
        ("Only a web address gives a site name, and only its host", onlyWebAddressesGiveHosts),
        ("A subdomain finds its site, the most specific entry first", subdomainFindsItsSite),
        ("Sensitive sites give no kind, wherever they sit", sensitiveSitesGiveNoKind),
        ("A remembered site wins over the table but never over a sensitive one", rememberedSiteWins),
        ("A typed site name is normalised or refused", typedNamesAreNormalised),
        ("Every built-in site resolves to its own kind", everyBuiltInResolves),
    ]

    private static func kindsReadAsPurposes() -> [String] {
        var problems: [String] = []
        expect(SiteKind.documentation.rule == .fixed(.research), "documentation is not research", &problems)
        expect(SiteKind.codeHost.rule == .fixed(.coding), "code host is not coding", &problems)
        expect(SiteKind.mail.rule == .fixed(.communication), "mail is not communication", &problems)
        expect(SiteKind.meeting.rule == .fixed(.communication), "meeting is not communication", &problems)
        expect(SiteKind.aiChat.rule == .fixed(.writingAI), "AI chat is not writing and AI", &problems)
        for kind in [SiteKind.video, .social, .shopping] {
            expect(kind.rule == .ambiguous(active: .media, passive: .media),
                   "\(kind) does not read as media either way", &problems)
        }
        expect(Set(SiteKind.allCases.filter(\.isLeisure)) == [.video, .social, .shopping],
               "leisure is not exactly video, social and shopping", &problems)
        let names = SiteKind.allCases.map(\.displayName)
        expect(names == ["Video", "Documentation", "Code host", "Social", "Shopping", "Mail", "AI chat", "Meeting"],
               "display names are \(names)", &problems)
        return problems
    }

    private static func onlyWebAddressesGiveHosts() -> [String] {
        var problems: [String] = []
        let cases: [(String, String?)] = [
            ("https://www.YouTube.com./watch?v=x", "youtube.com"),
            ("http://user:pw@docs.python.org:8080/3/", "docs.python.org"),
            ("HTTPS://Example.org/a#b", "example.org"),
            ("file:///Users/x/a.pdf", nil), ("about:blank", nil), ("chrome://settings", nil),
            ("data:text/html,hi", nil), ("how to cook rice", nil), ("", nil),
        ]
        for (address, expected) in cases {
            let got = SiteAddress.siteName(fromAddress: address)
            expect(got == expected, "\(address) gave \(got ?? "nil"), wanted \(expected ?? "nil")", &problems)
        }
        for address in ["https://192.168.1.1/", "http://localhost:3000"] {
            guard let name = SiteAddress.siteName(fromAddress: address) else {
                problems.append("\(address) gave no name"); continue
            }
            expect(SiteKindTable.kind(forSite: name, remembered: [:]) == nil, "\(name) has a kind", &problems)
        }
        return problems
    }

    private static func subdomainFindsItsSite() -> [String] {
        var problems: [String] = []
        let cases: [(String, SiteKind?)] = [
            ("youtube.com", .video), ("m.youtube.com", .video), ("docs.github.com", .documentation),
            ("gist.github.com", .codeHost), ("github.com", .codeHost), ("example.com", nil),
            ("amazon.com.au", .shopping), ("www.amazon.com.au", .shopping), ("box.com", nil),
        ]
        for (site, expected) in cases {
            let got = SiteKindTable.kind(forSite: site, remembered: [:])
            expect(got == expected, "\(site) gave \(String(describing: got))", &problems)
        }
        return problems
    }

    private static func sensitiveSitesGiveNoKind() -> [String] {
        var problems: [String] = []
        let sensitive = ["accounts.google.com", "eu.accounts.google.com", "www.paypal.com", "my.gov.au",
                         "ato.gov.au", "irs.gov", "impots.gouv.fr", "x.gov.in", "x.go.jp", "x.gc.ca",
                         "login.example.com", "app.auth.example.com", "sso.company.io", "xvideos.com",
                         "mail.defence.mil", "bank.example.com.au.banking.example.org", "id.example.com"]
        for site in sensitive {
            expect(SiteKindTable.isSensitive(site), "\(site) is not sensitive", &problems)
            expect(SiteKindTable.kind(forSite: site, remembered: [:]) == nil, "\(site) has a kind", &problems)
            expect(SiteKindTable.kind(forSite: site, remembered: [site: .video]) == nil,
                   "\(site) has a remembered kind", &problems)
        }
        for site in ["government.example.com", "idea.com", "github.com", "gov.example.com", "example.id"] {
            expect(!SiteKindTable.isSensitive(site), "\(site) is sensitive", &problems)
        }
        return problems
    }

    private static func rememberedSiteWins() -> [String] {
        var problems: [String] = []
        let remembered: [String: SiteKind] = ["youtube.com": .documentation, "intranet.example.com": .documentation]
        expect(SiteKindTable.kind(forSite: "youtube.com", remembered: remembered) == .documentation,
               "remembered youtube.com did not win", &problems)
        expect(SiteKindTable.kind(forSite: "wiki.intranet.example.com", remembered: remembered) == .documentation,
               "remembered parent did not reach a subdomain", &problems)
        expect(SiteKindTable.kind(forSite: "paypal.com", remembered: ["paypal.com": .shopping]) == nil,
               "a remembered sensitive site gave a kind", &problems)
        // The most specific level still decides between two remembered entries.
        expect(SiteKindTable.kind(forSite: "a.b.example.com",
                                  remembered: ["example.com": .social, "b.example.com": .mail]) == .mail,
               "the more specific remembered entry did not win", &problems)
        return problems
    }

    private static func typedNamesAreNormalised() -> [String] {
        var problems: [String] = []
        let cases: [(String, String?)] = [
            ("  Example.COM ", "example.com"), ("https://www.example.com/a?b", "example.com"),
            ("example.com/path", "example.com"), ("example", nil), ("a b.com", nil), ("", nil),
            ("file:///x", nil), ("ftp://example.com", nil), ("exa_mple.com", nil), ("a..com", nil),
            ("example.com/a?u=http://x", "example.com"), ("mailto:a@b.com", nil),
        ]
        for (typed, expected) in cases {
            let got = SiteAddress.normalisedSiteName(typed)
            expect(got == expected, "\"\(typed)\" gave \(got ?? "nil"), wanted \(expected ?? "nil")", &problems)
        }
        return problems
    }

    /// A built-in host that is also sensitive by rule would silently give no kind.
    private static func everyBuiltInResolves() -> [String] {
        var problems: [String] = []
        for (kind, hosts) in SiteKindTable.builtInHosts {
            for host in hosts {
                let got = SiteKindTable.kind(forSite: host, remembered: [:])
                expect(got == kind, "\(host) gave \(String(describing: got)), wanted \(kind)", &problems)
            }
        }
        return problems
    }
}
