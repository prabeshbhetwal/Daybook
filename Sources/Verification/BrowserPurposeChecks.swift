import Foundation

/// Every browser the site signal may read is read as a browser without it too: research while in use,
/// media while watched. A browser missing from `PurposeMap` was credited as a utility, and with the site
/// signal on its sessions read "Mixed" almost every time.
enum BrowserPurposeChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Every browser the site signal may read is credited as a browser", everyKnownBrowserIsABrowser),
    ]

    private static func everyKnownBrowserIsABrowser() -> [String] {
        var problems: [String] = []
        for browser in SiteSignalConstants.knownBrowsers.sorted() {
            expect(PurposeMap.isAmbiguous(browser), "\(browser) is not read as a browser", &problems)
            expect(PurposeMap.purpose(for: browser, activity: .passive, overrides: [:]) == .media,
                   "\(browser) watched is not media", &problems)
        }
        let typing = PurposeMap.purpose(for: "com.brave.Browser", activity: .active, overrides: [:])
        expect(typing == .research, "Brave in use is \(typing.rawValue), not research", &problems)
        return problems
    }
}
