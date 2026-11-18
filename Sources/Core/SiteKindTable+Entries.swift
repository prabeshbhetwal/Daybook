import Foundation

extension SiteKindTable {

    static let builtInHosts: [(SiteKind, [String])] = [
        (.video, ["youtube.com", "youtu.be", "vimeo.com", "twitch.tv", "netflix.com", "primevideo.com",
                  "disneyplus.com", "tv.apple.com", "max.com", "hulu.com", "dailymotion.com"]),
        (.documentation, ["developer.apple.com", "developer.mozilla.org", "docs.python.org", "swift.org",
                          "stackoverflow.com", "learn.microsoft.com", "readthedocs.io", "docs.github.com",
                          "react.dev", "nodejs.org", "devdocs.io", "docs.rs",
                          "wikipedia.org"]),
        (.codeHost, ["github.com", "gitlab.com", "bitbucket.org", "codeberg.org", "sr.ht"]),
        (.social, ["facebook.com", "instagram.com", "x.com", "twitter.com", "tiktok.com", "reddit.com",
                   "linkedin.com", "threads.net", "bsky.app", "mastodon.social", "pinterest.com",
                   "tumblr.com"]),
        (.shopping, ["amazon.com", "amazon.com.au", "ebay.com", "ebay.com.au", "etsy.com", "aliexpress.com",
                     "temu.com", "walmart.com", "target.com", "bestbuy.com"]),
        (.mail, ["mail.google.com", "outlook.live.com", "outlook.office.com", "mail.yahoo.com",
                 "mail.proton.me", "app.fastmail.com"]),
        (.aiChat, ["chatgpt.com", "chat.openai.com", "claude.ai", "gemini.google.com", "perplexity.ai",
                   "copilot.microsoft.com", "chat.deepseek.com", "grok.com", "poe.com"]),
        (.meeting, ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "whereby.com",
                    "webex.com"]),
    ]

    /// Banking, health, government, sign-in and adult sites. They give no signal.
    static let sensitiveHostList: [String] = [
        // banking
        "paypal.com", "wise.com", "revolut.com", "stripe.com", "chase.com", "bankofamerica.com",
        "wellsfargo.com", "hsbc.com", "barclays.co.uk", "commbank.com.au", "anz.com.au", "westpac.com.au",
        "nab.com.au",
        // health
        "webmd.com", "mayoclinic.org", "nhs.uk", "healthdirect.gov.au", "healthengine.com.au", "mychart.org",
        // government
        "my.gov.au",
        // sign-in
        "accounts.google.com", "login.microsoftonline.com", "login.live.com", "appleid.apple.com",
        "account.apple.com", "idmsa.apple.com", "okta.com", "my.1password.com", "vault.bitwarden.com",
        "lastpass.com",
        // adult
        "pornhub.com", "xvideos.com", "xnxx.com", "xhamster.com", "onlyfans.com", "chaturbate.com",
    ]
}
