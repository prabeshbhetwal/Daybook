import ApplicationServices
import Foundation

/// The real reader: the address of the focused window's web area, through
/// Accessibility, read-only. It reads the focused window, then children and roles
/// breadth-first until it meets a web area, and of that web area only its URL.
/// It never descends into a web area (no page content), never reads a title or
/// an address bar, sets no attribute on the other app and logs nothing.
struct AXSiteAddressReader: SiteAddressReading {
    static let maxElements = 400
    static let maxDepth = 12

    struct TimedOut: Error {}

    func read(pid: pid_t, timeout: TimeInterval) -> SiteAddressRead {
        let now = { ProcessInfo.processInfo.systemUptime }
        let startedAt = now()
        let seconds = Float(timeout)
        do {
            guard let window = try Self.element(Self.value(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute, seconds))
            else { return .failed }
            let address = try Self.walk(
                from: window, startedAt: startedAt, now: now,
                role: { try Self.value($0, kAXRoleAttribute, seconds) as? String },
                children: { try Self.value($0, kAXChildrenAttribute, seconds) as? [AXUIElement] ?? [] },
                url: { (try Self.value($0, kAXURLAttribute, seconds) as? URL)?.absoluteString })
            return address.map(SiteAddressRead.address) ?? .failed
        } catch {
            return .timedOut
        }
    }

    /// Breadth-first from the window to the first web area, at most `maxElements`
    /// and `maxDepth`, never below a web area, giving up once the read has taken
    /// `SiteSignalConstants.readDeadline`. Apart from Accessibility so checks can drive it.
    static func walk<Element>(from window: Element, startedAt: TimeInterval, now: () -> TimeInterval,
                              role: (Element) throws -> String?, children: (Element) throws -> [Element],
                              url: (Element) throws -> String?) throws -> String? {
        var queue: [(element: Element, depth: Int)] = [(window, 0)]
        var index = 0
        while index < queue.count {
            guard now() - startedAt < SiteSignalConstants.readDeadline else { throw TimedOut() }
            let (current, depth) = queue[index]
            index += 1
            if try role(current) == "AXWebArea" { return try url(current) }
            guard depth < maxDepth else { continue }
            for child in try children(current) where queue.count < maxElements { queue.append((child, depth + 1)) }
        }
        return nil
    }

    /// nil when the attribute is missing or unreadable; throws only when the app did not answer in time.
    private static func value(_ element: AXUIElement, _ attribute: String, _ timeout: Float) throws -> CFTypeRef? {
        // This process's own setting for messages to that element, not an attribute of the other app.
        AXUIElementSetMessagingTimeout(element, timeout)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if error == .cannotComplete { throw TimedOut() }
        return error == .success ? value : nil
    }

    private static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
