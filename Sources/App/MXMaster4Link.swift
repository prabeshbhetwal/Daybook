import Foundation
import IOKit.hid

/// An MX Master 4 over Bluetooth, spoken to in HID++ 2.0 without Logitech's
/// software. Opened without seizing it, so Logi Options+ keeps working
/// beside it. Daybook only reads the mouse's haptic settings and plays
/// waveforms; it never writes its configuration (function 2).
///
/// Everything runs on `work`, one serial queue, so a switch turned off in
/// the middle of a discovery waits its turn. Replies arrive on `callbacks`,
/// which a discovery waits on but never blocks, and neither is the main
/// thread: a discovery can wait 1.5 s for each reply.
final class MXMaster4Link: MouseHapticLink {
    private static let vendorID = 0x046D
    private static let productID = 0xB042
    private static let softwareID: UInt8 = 0x0B
    private static let replyTimeout: TimeInterval = 1.5
    private static let reportCapacity = 64
    /// A pulse after a failed discovery does not try again for this long, so
    /// pulses aimed at an asleep or absent mouse do not queue up behind waits.
    private static let retryAfter: TimeInterval = 10

    private let work = DispatchQueue(label: "com.prabesh.daybook.haptics.mouse")
    private let callbacks = DispatchQueue(label: "com.prabesh.daybook.haptics.mouse-callbacks")

    // Touched only on `work`. `device` sends plays and never listens.
    private var device: IOHIDDevice?
    private var featureIndex: UInt8?
    private var configuration: HapticConfiguration?
    private var capabilities: HapticCapabilities?
    private var status = MouseLinkStatus.closed
    private var lastFailure: Date?

    // One request in flight at a time, answered from `callbacks`.
    private let replyLock = NSLock()
    private var pendingRequest: [UInt8]?
    private var pendingReply: HIDPP.Reply?
    private let replySignal = DispatchSemaphore(value: 0)

    /// Opening when the switch turns on puts any permission prompt beside it.
    func open() { work.async { self.discover(force: true) } }

    func close() {
        work.async {
            self.release()
            self.status = .closed
        }
    }

    func play(_ waveform: UInt8) {
        work.async {
            if self.status != .ready { self.discover(force: false) }
            guard self.status == .ready, let device = self.device, let index = self.featureIndex,
                  let configuration = self.configuration, let capabilities = self.capabilities,
                  MouseHaptics.playable(configuration: configuration, capabilities: capabilities,
                                        waveform: waveform) else { return }
            let request = HIDPP.request(feature: index, function: 4, softwareID: Self.softwareID,
                                        parameters: [waveform, 0, 0])
            // Asleep, switched to another computer, or gone: the next pulse
            // finds the mouse again, with its feature index and settings.
            if !Self.send(request, to: device) {
                self.release()
                self.status = .closed
            }
        }
    }

    func rediscover(completion: @escaping (MouseLinkStatus) -> Void) {
        work.async {
            self.discover(force: true)
            let status = self.status
            DispatchQueue.main.async { completion(status) }
        }
    }

    private func discover(force: Bool) {
        if !force, let lastFailure, Date().timeIntervalSince(lastFailure) < Self.retryAfter { return }
        release()
        status = connect()
        lastFailure = status == .ready ? nil : Date()
    }

    private func connect() -> MouseLinkStatus {
        let matching = IOServiceMatching(kIOHIDDeviceKey) as NSMutableDictionary
        matching[kIOHIDVendorIDKey] = Self.vendorID
        matching[kIOHIDProductIDKey] = Self.productID
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { return .noMouse }
        defer { IOObjectRelease(service) }
        guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { return .noMouse }
        switch IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) {
        case kIOReturnSuccess: break
        case kIOReturnNotPermitted: return .notPermitted
        default: return .noMouse
        }
        self.device = device
        return readHaptics(from: service)
    }

    private func release() {
        if let device { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        device = nil
        featureIndex = nil
        configuration = nil
        capabilities = nil
    }

    /// The only time Daybook listens to the mouse. A device object scheduled
    /// on a queue cannot drop its report callback, so each discovery listens
    /// through a device object of its own and cancels it afterwards: moving
    /// the mouse never wakes the app.
    private func readHaptics(from service: io_service_t) -> MouseLinkStatus {
        guard let listener = IOHIDDeviceCreate(kCFAllocatorDefault, service),
              IOHIDDeviceOpen(listener, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
        else { return .noReply }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.reportCapacity)
        IOHIDDeviceRegisterInputReportCallback(listener, buffer, Self.reportCapacity, {
            context, _, _, _, _, report, length in
            guard let context else { return }
            Unmanaged<MXMaster4Link>.fromOpaque(context).takeUnretainedValue()
                .received(Array(UnsafeBufferPointer(start: report, count: length)))
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceSetDispatchQueue(listener, callbacks)
        // No callback runs after this handler, so it is the place to let go.
        IOHIDDeviceSetCancelHandler(listener) {
            IOHIDDeviceClose(listener, IOOptionBits(kIOHIDOptionsTypeNone))
            buffer.deallocate()
        }
        IOHIDDeviceActivate(listener)
        defer { IOHIDDeviceCancel(listener) }

        let (high, low) = HIDPP.hapticFeature
        guard let feature = call(listener, feature: 0, function: 0, parameters: [high, low, 0]) else {
            return .noReply
        }
        guard let index = feature.first, index != 0 else { return .noMouse }
        guard let caps = call(listener, feature: index, function: 0).flatMap(HapticCapabilities.init),
              let config = call(listener, feature: index, function: 1).flatMap(HapticConfiguration.init)
        else { return .noReply }
        featureIndex = index
        capabilities = caps
        configuration = config
        return config.isEnabled && config.intensity > 0 ? .ready : .hapticsOff
    }

    /// One request and its answer, or nil after an error or the timeout.
    private func call(_ device: IOHIDDevice, feature: UInt8, function: UInt8,
                      parameters: [UInt8] = []) -> [UInt8]? {
        let request = HIDPP.request(feature: feature, function: function,
                                    softwareID: Self.softwareID, parameters: parameters)
        while replySignal.wait(timeout: .now()) == .success {}  // a late answer to an earlier request
        replyLock.withLock { pendingRequest = request; pendingReply = nil }
        defer { replyLock.withLock { pendingRequest = nil } }
        guard Self.send(request, to: device),
              replySignal.wait(timeout: .now() + Self.replyTimeout) == .success,
              case .answer(let payload)? = replyLock.withLock({ pendingReply }) else { return nil }
        return payload
    }

    private func received(_ report: [UInt8]) {
        replyLock.withLock {
            guard let request = pendingRequest, pendingReply == nil else { return }
            let reply = HIDPP.reply(report, to: request)
            guard reply != .unrelated else { return }
            pendingReply = reply
            replySignal.signal()
        }
    }

    private static func send(_ request: [UInt8], to device: IOHIDDevice) -> Bool {
        IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(HIDPP.longReportID),
                             request, request.count) == kIOReturnSuccess
    }
}
