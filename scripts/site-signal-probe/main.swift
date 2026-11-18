import AppKit
import ApplicationServices
import Foundation

// The site signal probe: runs the app's own reader against the front browser
// for a fixed time and prints kinds and timings. Run it from Terminal, never
// inside Daybook, and see docs/debug/2026-11-19-site-signal-probe-steps.md.
//
//   site-signal-probe [--seconds N] [--expect KIND|none] [--show-site]
//
// It never prints an address. The address a read returns is reduced to a site
// name and a kind in `reduce` and dropped there. --show-site also prints the
// site name (host only), for the owner's eyes, never for a report.

setvbuf(stdout, nil, _IOLBF, 0)

var seconds = 120.0
var expected: String?
var showSite = false
var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    switch arg {
    case "--seconds": seconds = args.popFirst().flatMap(Double.init) ?? seconds
    case "--expect": expected = args.popFirst()
    case "--show-site": showSite = true
    default:
        print("usage: site-signal-probe [--seconds N] [--expect \(SiteKind.allCases.map(\.rawValue).joined(separator: "|"))|none] [--show-site]")
        exit(2)
    }
}

// Never prompts: AXIsProcessTrusted() only asks whether Terminal already has the grant.
guard AXIsProcessTrusted() else {
    print("""
    Terminal does not have Accessibility yet. Grant it, then run the probe again:
      System Settings > Privacy & Security > Accessibility > add or tick Terminal.
    Remove the grant when the probe is finished.
    """)
    exit(1)
}

// Spike 5: the apps macOS says can open a web link, as the app's list would show them.
print("Web-link apps (bundle identifier, name, ticked by default):")
for app in SiteSignalSettings.candidates(WebLinkApps.current()) {
    print("  \(app.bundleID)  \(app.name)  \(app.ticked ? "ticked" : "not ticked")")
}

/// The one place the probe sees an address: reduced to a site name and a kind, then dropped.
func reduce(_ address: String) -> (site: String?, kind: SiteKind?) {
    guard let site = SiteAddress.siteName(fromAddress: address) else { return (nil, nil) }
    return (site, SiteKindTable.kind(forSite: site, remembered: [:]))
}

struct Sample { let result: String; let ms: Double; let correct: Bool }
var samples: [String: [Sample]] = [:]
var consecutiveTimeouts: [String: Int] = [:]
var sawTwoInARow: Set<String> = []

let reader = AXSiteAddressReader()
let interval = 2.0
let end = Date().addingTimeInterval(seconds)
print("\nReading every \(Int(interval)) s for \(Int(seconds)) s. Keep the page under test in front. readTimeout \(SiteSignalConstants.readTimeout) s, readDeadline \(SiteSignalConstants.readDeadline) s.")
print("browser | result | ms | elements walked\(showSite ? " | site" : "")")

while Date() < end {
    if let front = NSWorkspace.shared.frontmostApplication, let id = front.bundleIdentifier,
       SiteSignalConstants.knownBrowsers.contains(id) {
        let started = ProcessInfo.processInfo.systemUptime
        let read = reader.read(pid: front.processIdentifier, timeout: SiteSignalConstants.readTimeout)
        let ms = (ProcessInfo.processInfo.systemUptime - started) * 1000
        var result: String
        var site: String?
        switch read {
        case .address(let address):
            let reduced = reduce(address)
            site = reduced.site
            result = reduced.kind?.rawValue ?? "none"
        case .failed: result = "failed"
        case .timedOut: result = "timedOut"
        }
        let isTimeout = read == .timedOut
        consecutiveTimeouts[id] = isTimeout ? (consecutiveTimeouts[id] ?? 0) + 1 : 0
        if (consecutiveTimeouts[id] ?? 0) >= SiteSignalConstants.timeoutsBeforeSkipping { sawTwoInARow.insert(id) }
        let correct = expected.map { $0 == result } ?? false
        samples[id, default: []].append(Sample(result: result, ms: ms, correct: correct))
        // n/a: AXSiteAddressReader does not report how many elements it walked.
        print("\(id) | \(result) | \(String(format: "%.0f", ms)) | n/a\(showSite ? " | \(site ?? "-")" : "")")
    } else {
        print("(front app is not a known browser)")
    }
    Thread.sleep(forTimeInterval: interval)
}

func percentile(_ sorted: [Double], _ p: Double) -> Double {
    // Nearest rank.
    sorted.isEmpty ? 0 : sorted[max(0, Int((p * Double(sorted.count)).rounded(.up)) - 1)]
}

print("\nSummary\(expected.map { " (expected: \($0))" } ?? "")")
if samples.isEmpty { print("No browser was in front for any read.") }
for (id, list) in samples.sorted(by: { $0.key < $1.key }) {
    let times = list.map(\.ms).sorted()
    let successes = list.filter { !["failed", "timedOut"].contains($0.result) }.count
    var line = "\(id): reads \(list.count), successes \(successes)"
    if expected != nil { line += ", right \(list.filter(\.correct).count)" }
    line += String(format: ", p50 %.0f ms, p95 %.0f ms, longest %.0f ms", percentile(times, 0.5), percentile(times, 0.95), times.last ?? 0)
    line += ", two consecutive timeouts: \(sawTwoInARow.contains(id) ? "yes" : "no")"
    print(line)
}
