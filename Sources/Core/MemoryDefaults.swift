import Foundation

/// Preferences that live only in this process, for the self-checks and the
/// review modes. Each check used to open a suite of its own, and every suite
/// is a real domain that cfprefsd tracks and writes a plist for: hundreds a
/// run, from several runs at once, exhausted its file descriptors on 9
/// October 2026, after which no app on the Mac could save its settings until
/// it restarted. These never reach cfprefsd.
///
/// Suites with the same name share their values, as real ones do, so a check
/// can open a suite again to read what a relaunch would see. Every
/// `UserDefaults` method is overridden: one left to the superclass would read
/// or write a real domain.
final class MemoryDefaults: UserDefaults {
    private static var suites: [String: [String: Any]] = [:]
    private static let lock = NSLock()

    /// The suite called `name`. Optional only so it reads like
    /// `UserDefaults(suiteName:)` at the call sites it replaced.
    static func suite(named name: String) -> UserDefaults? {
        MemoryDefaults(name: name)
    }

    /// Forgets every value in the suite called `name`.
    static func remove(named name: String) {
        lock.lock(); defer { lock.unlock() }
        suites[name] = nil
    }

    private let name: String
    private var registered: [String: Any] = [:]
    private var volatile: [String: [String: Any]] = [:]

    private init?(name: String) {
        self.name = name
        // A fixed domain this class never reads or writes, so the superclass
        // has somewhere harmless to point.
        super.init(suiteName: "com.prabesh.daybook.memory-defaults")
    }

    private static func values(_ name: String) -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return suites[name] ?? [:]
    }

    private static func update(_ name: String, _ change: (inout [String: Any]) -> Void) {
        lock.lock(); defer { lock.unlock() }
        var values = suites[name] ?? [:]
        change(&values)
        suites[name] = values
    }

    // MARK: - Reading

    override func object(forKey defaultName: String) -> Any? {
        Self.values(name)[defaultName] ?? registered[defaultName]
    }

    override func string(forKey defaultName: String) -> String? {
        let value = object(forKey: defaultName)
        return value as? String ?? (value as? NSNumber)?.stringValue
    }

    override func array(forKey defaultName: String) -> [Any]? { object(forKey: defaultName) as? [Any] }

    override func dictionary(forKey defaultName: String) -> [String: Any]? {
        object(forKey: defaultName) as? [String: Any]
    }

    override func data(forKey defaultName: String) -> Data? { object(forKey: defaultName) as? Data }

    override func stringArray(forKey defaultName: String) -> [String]? { object(forKey: defaultName) as? [String] }

    override func integer(forKey defaultName: String) -> Int {
        number(defaultName)?.intValue ?? 0
    }

    override func float(forKey defaultName: String) -> Float {
        number(defaultName)?.floatValue ?? 0
    }

    override func double(forKey defaultName: String) -> Double {
        number(defaultName)?.doubleValue ?? 0
    }

    override func bool(forKey defaultName: String) -> Bool {
        if let text = object(forKey: defaultName) as? String { return (text as NSString).boolValue }
        return number(defaultName)?.boolValue ?? false
    }

    override func url(forKey defaultName: String) -> URL? {
        let value = object(forKey: defaultName)
        if let url = value as? URL { return url }
        guard let text = value as? String else { return nil }
        return text.hasPrefix("/") || text.hasPrefix("~")
            ? URL(fileURLWithPath: (text as NSString).expandingTildeInPath) : URL(string: text)
    }

    /// A number, or a string that reads as one, as the real class converts.
    private func number(_ key: String) -> NSNumber? {
        let value = object(forKey: key)
        if let number = value as? NSNumber { return number }
        guard let text = value as? String, let parsed = Double(text) else { return nil }
        return NSNumber(value: parsed)
    }

    // MARK: - Writing

    override func set(_ value: Any?, forKey defaultName: String) {
        // The real class stops the process on a value it cannot store; so
        // does this, or a check would pass on code that crashes in the app.
        if let value {
            precondition(PropertyListSerialization.propertyList(value, isValidFor: .binary),
                         "\(defaultName) is not a property-list value: \(type(of: value))")
        }
        willChangeValue(forKey: defaultName)
        // Stored as the property-list objects the real class hands back, so
        // an Int reads back as a Double and a Bool is a CFBoolean.
        Self.update(name) { $0[defaultName] = value.map { $0 as AnyObject } }
        didChangeValue(forKey: defaultName)
    }

    override func removeObject(forKey defaultName: String) { set(nil, forKey: defaultName) }
    override func set(_ value: Int, forKey defaultName: String) { set(value as Any?, forKey: defaultName) }
    override func set(_ value: Float, forKey defaultName: String) { set(value as Any?, forKey: defaultName) }
    override func set(_ value: Double, forKey defaultName: String) { set(value as Any?, forKey: defaultName) }
    override func set(_ value: Bool, forKey defaultName: String) { set(value as Any?, forKey: defaultName) }
    override func set(_ url: URL?, forKey defaultName: String) { set(url as Any?, forKey: defaultName) }

    override func register(defaults registrationDictionary: [String: Any]) {
        registered.merge(registrationDictionary) { $1 }
    }

    // MARK: - Domains

    override func addSuite(named suiteName: String) {}
    override func removeSuite(named suiteName: String) {}

    override func dictionaryRepresentation() -> [String: Any] {
        registered.merging(Self.values(name)) { $1 }
    }

    override var volatileDomainNames: [String] { Array(volatile.keys) }
    override func volatileDomain(forName domainName: String) -> [String: Any] { volatile[domainName] ?? [:] }
    override func setVolatileDomain(_ domain: [String: Any], forName domainName: String) { volatile[domainName] = domain }
    override func removeVolatileDomain(forName domainName: String) { volatile[domainName] = nil }

    /// Any suite's values: the real class reads other apps' domains here.
    override func persistentDomain(forName domainName: String) -> [String: Any]? {
        Self.lock.lock(); defer { Self.lock.unlock() }
        return Self.suites[domainName]
    }

    override func setPersistentDomain(_ domain: [String: Any], forName domainName: String) {
        Self.update(domainName) { $0 = domain.mapValues { $0 as AnyObject } }
    }

    override func removePersistentDomain(forName domainName: String) { Self.remove(named: domainName) }

    override func synchronize() -> Bool { true }
    override func objectIsForced(forKey key: String) -> Bool { false }
    override func objectIsForced(forKey key: String, inDomain domain: String) -> Bool { false }
}
