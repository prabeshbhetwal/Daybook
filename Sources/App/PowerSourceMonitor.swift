import Foundation
import IOKit
import IOKit.ps

protocol PowerSourceMonitoring: AnyObject {
    func observation(at timestamp: Date,
                     boundary: PowerCoverageBoundary?) -> PowerObservation
    func start(_ handler: @escaping (PowerObservation) -> Void)
    func stop()
}

final class PowerSourceMonitor: PowerSourceMonitoring {
    private var handler: ((PowerObservation) -> Void)?
    private var runLoopSource: CFRunLoopSource?
    /// The last observation handed out, boundary samples included, so a change
    /// the store already captured at a boundary is not reported twice.
    private var lastEmitted: PowerObservation?

    /// What a notification means. IOKit posts one on every battery level
    /// step, about once a minute, and every one was tagged `.sourceChanged`:
    /// an hour on battery wrote "source changed" forty times when the source
    /// had not changed once. A different source or charging state is a
    /// change; a different level is a sample.
    static func boundary(for next: PowerObservation,
                         after previous: PowerObservation?) -> PowerCoverageBoundary? {
        guard let previous else { return nil }
        return previous.source != next.source || previous.charging != next.charging
            ? .sourceChanged : nil
    }

    /// The adapter's rating from the battery's registry entry — the dictionary
    /// `pmset -g ac` and System Information both read. Unplugged, the entry
    /// keeps an `AdapterDetails` with no `Watts` key at all; some models leave
    /// a zero. Neither is a charger.
    static func adapterWatts(registry: [String: Any]) -> Int? {
        guard let details = registry["AdapterDetails"] as? [String: Any],
              let watts = (details["Watts"] as? NSNumber)?.intValue, watts > 0 else { return nil }
        return watts
    }

    static func parse(descriptions: [[String: Any]], at timestamp: Date,
                      boundary: PowerCoverageBoundary?,
                      adapterWatts: Int? = nil) -> PowerObservation {
        let selected = descriptions.first(where: {
            ($0[kIOPSTypeKey as String] as? String) == kIOPSInternalBatteryType
        }) ?? descriptions.first(where: {
            ($0[kIOPSTypeKey as String] as? String) == kIOPSUPSType
        }) ?? descriptions.first
        guard let selected else {
            return PowerObservation(timestamp: timestamp, source: .unknown, percentage: nil,
                                    charging: .unknown, boundary: boundary)
        }
        let type = selected[kIOPSTypeKey as String] as? String
        let state = selected[kIOPSPowerSourceStateKey as String] as? String
        let source: PowerSourceKind
        if type == kIOPSUPSType { source = .ups }
        else if state == kIOPSBatteryPowerValue { source = .battery }
        else if state == kIOPSACPowerValue { source = .external }
        else { source = .unknown }
        let charging: PowerChargingState
        if let value = selected[kIOPSIsChargingKey as String] as? Bool {
            charging = value ? .charging : .notCharging
        } else { charging = .unknown }
        // A reading belongs to the charger in use. On battery there is none,
        // whatever a stale registry value says.
        return PowerObservation.normalised(timestamp: timestamp, source: source,
            currentCapacity: (selected[kIOPSCurrentCapacityKey as String] as? NSNumber)?.doubleValue,
            maximumCapacity: (selected[kIOPSMaxCapacityKey as String] as? NSNumber)?.doubleValue,
            charging: charging, boundary: boundary,
            adapterWatts: source == .external ? adapterWatts : nil)
    }

    /// One registry read per sample: the `AppleSmartBattery` service's
    /// properties. Absent on a Mac with no battery, which is also no charger.
    private func registryAdapterWatts() -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let registry = properties?.takeRetainedValue() as? [String: Any] else { return nil }
        return Self.adapterWatts(registry: registry)
    }

    func observation(at timestamp: Date,
                     boundary: PowerCoverageBoundary?) -> PowerObservation {
        let observation = read(at: timestamp, boundary: boundary)
        lastEmitted = observation
        return observation
    }

    private func read(at timestamp: Date, boundary: PowerCoverageBoundary?) -> PowerObservation {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return PowerObservation(timestamp: timestamp, source: .unknown, percentage: nil,
                                    charging: .unknown, boundary: boundary)
        }
        let descriptions = sources.compactMap {
            IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any]
        }
        return Self.parse(descriptions: descriptions, at: timestamp, boundary: boundary,
                          adapterWatts: registryAdapterWatts())
    }

    /// One notification, tagged by what changed since the last observation.
    private func notified() {
        let raw = read(at: Date(), boundary: nil)
        let tagged = PowerObservation(id: raw.id, timestamp: raw.timestamp, source: raw.source,
                                      percentage: raw.percentage, charging: raw.charging,
                                      boundary: Self.boundary(for: raw, after: lastEmitted),
                                      adapterWatts: raw.adapterWatts)
        lastEmitted = tagged
        handler?(tagged)
    }

    func start(_ handler: @escaping (PowerObservation) -> Void) {
        guard runLoopSource == nil else { return }
        self.handler = handler
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.notified()
        }, context)?.takeRetainedValue() else { return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        handler = nil
    }
}
