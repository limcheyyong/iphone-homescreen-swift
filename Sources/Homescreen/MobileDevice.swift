// iPhone over USB through Apple's private MobileDevice.framework, the same stack Finder uses.
// It handles usbmuxd, pairing and TLS, so the app needs no networking or crypto code of its own.
// The framework has no public headers: functions are looked up at runtime with dlsym.
import Foundation

struct DeviceError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum MD {
    typealias Ref = UnsafeMutableRawPointer
    typealias Callback = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Void

    private static let handle: UnsafeMutableRawPointer? = {
        for path in ["/Library/Apple/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice",
                     "/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice"] {
            if let h = dlopen(path, RTLD_NOW) { return h }
        }
        return nil
    }()
    static var available: Bool { handle != nil }

    private static func fn<T>(_ name: String, _: T.Type) -> T {
        guard let h = handle, let s = dlsym(h, name) else { fatalError("MobileDevice.framework is missing \(name)") }
        return unsafeBitCast(s, to: T.self)
    }

    static let subscribe = fn("AMDeviceNotificationSubscribe",
        (@convention(c) (Callback, UInt32, UInt32, UnsafeMutableRawPointer?, UnsafeMutablePointer<Ref?>) -> Int32).self)
    static let connect = fn("AMDeviceConnect", (@convention(c) (Ref) -> Int32).self)
    static let disconnect = fn("AMDeviceDisconnect", (@convention(c) (Ref) -> Int32).self)
    static let isPaired = fn("AMDeviceIsPaired", (@convention(c) (Ref) -> Int32).self)
    static let pair = fn("AMDevicePair", (@convention(c) (Ref) -> Int32).self)
    static let validatePairing = fn("AMDeviceValidatePairing", (@convention(c) (Ref) -> Int32).self)
    static let startSession = fn("AMDeviceStartSession", (@convention(c) (Ref) -> Int32).self)
    static let stopSession = fn("AMDeviceStopSession", (@convention(c) (Ref) -> Int32).self)
    static let interfaceType = fn("AMDeviceGetInterfaceType", (@convention(c) (Ref) -> Int32).self)
    static let copyIdentifier = fn("AMDeviceCopyDeviceIdentifier", (@convention(c) (Ref) -> Unmanaged<CFString>?).self)
    static let copyValue = fn("AMDeviceCopyValue", (@convention(c) (Ref, CFString?, CFString?) -> UnsafeRawPointer?).self)
    static let startService = fn("AMDeviceSecureStartService",
        (@convention(c) (Ref, CFString, CFDictionary?, UnsafeMutablePointer<Ref?>) -> Int32).self)
    static let send = fn("AMDServiceConnectionSendMessage", (@convention(c) (Ref, UnsafeRawPointer, Int) -> Int32).self)
    static let receive = fn("AMDServiceConnectionReceiveMessage",
        (@convention(c) (Ref, UnsafeMutablePointer<UnsafeRawPointer?>, UnsafeMutablePointer<Int>?) -> Int32).self)
    static let invalidate = fn("AMDServiceConnectionInvalidate", (@convention(c) (Ref) -> Void).self)

    static let xmlFormat = 100  // kCFPropertyListXMLFormat_v1_0
}

private func check(_ code: Int32, _ what: String) throws {
    guard code != 0 else { return }
    let hex = String(format: "0x%08X", UInt32(bitPattern: code))
    throw DeviceError(L("%@ failed (%@). Make sure your iPhone is unlocked, connected by USB, and trusts this Mac.", L(what), hex))
}

/// Keeps track of iPhones plugged in over USB. Notifications arrive on the main run loop.
final class DeviceWatcher {
    static let shared = DeviceWatcher()
    private(set) var devices: [String: MD.Ref] = [:]  // udid -> retained AMDeviceRef
    var onChange: (() -> Void)?
    private var subscription: MD.Ref?

    func start() {
        guard MD.available, subscription == nil else { return }
        var sub: MD.Ref?
        _ = MD.subscribe({ info, _ in
            // struct am_device_notification_callback_info { AMDeviceRef device; unsigned int msg; ... }
            guard let info, let dev = info.load(as: UnsafeMutableRawPointer?.self) else { return }
            let msg = info.load(fromByteOffset: MemoryLayout<UnsafeRawPointer>.size, as: UInt32.self)
            DeviceWatcher.shared.handle(dev, msg)
        }, 0, 0, nil, &sub)
        subscription = sub
    }

    private func handle(_ dev: MD.Ref, _ msg: UInt32) {
        guard let udid = MD.copyIdentifier(dev)?.takeRetainedValue() as String? else { return }
        if msg == 1 {  // connected
            guard MD.interfaceType(dev) == 1, devices[udid] == nil else { return }  // USB only, not Wi-Fi
            _ = Unmanaged<AnyObject>.fromOpaque(dev).retain()
            devices[udid] = dev
        } else if msg == 2, let old = devices.removeValue(forKey: udid) {  // disconnected
            Unmanaged<AnyObject>.fromOpaque(old).release()
        }
        onChange?()
    }
}

/// One session with one iPhone. Every call blocks, so use it off the main thread.
final class Device {
    private let ref: MD.Ref
    private static let queue = DispatchQueue(label: "homescreen.device")

    private init(_ ref: MD.Ref) { self.ref = ref }

    /// Opens a session, runs `body` on the device queue and always closes the session.
    static func session<T>(_ ref: MD.Ref, _ body: @escaping (Device) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                let d = Device(ref)
                cont.resume(with: Result {
                    try d.open()
                    defer { d.close() }
                    return try body(d)
                })
            }
        }
    }

    private func open() throws {
        try check(MD.connect(ref), "Connecting to iPhone")
        if MD.isPaired(ref) != 1 {
            _ = MD.pair(ref)  // shows "Trust This Computer?" on the phone
            _ = MD.disconnect(ref)
            throw DeviceError(L("This Mac is not trusted by your iPhone yet. Unlock your phone, tap “Trust” in the prompt, enter your passcode, then read again."))
        }
        try check(MD.validatePairing(ref), "Validating pairing")
        try check(MD.startSession(ref), "Starting session")
    }

    private func close() {
        _ = MD.stopSession(ref)
        _ = MD.disconnect(ref)
    }

    var name: String? {
        guard let v = MD.copyValue(ref, nil, "DeviceName" as CFString) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(v).takeRetainedValue() as? String
    }

    private func springboard<T>(_ body: (Service) throws -> T) throws -> T {
        var conn: MD.Ref?
        try check(MD.startService(ref, "com.apple.springboardservices" as CFString, nil, &conn), "Starting the home screen service")
        let s = Service(conn: conn!)
        defer { s.close() }
        return try body(s)
    }

    func iconState() throws -> IconState {
        try springboard { s in
            try s.send(["command": "getIconState", "formatVersion": "2"])
            return try Layout.parse(s.receive())
        }
    }

    func setIconState(_ state: IconState) throws {
        try springboard { s in
            try s.send(["command": "setIconState", "iconState": state])  // no reply
            Thread.sleep(forTimeInterval: 1)
        }
        Thread.sleep(forTimeInterval: 2)  // let SpringBoard re-layout before reading again
    }

    /// Real icons straight from the phone. One connection, one request per app; failures just get skipped.
    func iconPNGs(_ bundleIds: [String]) -> [String: Data] {
        guard !bundleIds.isEmpty else { return [:] }
        return (try? springboard { s in
            var out: [String: Data] = [:]
            for id in bundleIds {
                guard (try? s.send(["command": "getIconPNGData", "bundleId": id])) != nil,
                      let reply = try? s.receive() as? [String: Any] else { break }
                if let png = reply["pngData"] as? Data { out[id] = png }
            }
            return out
        }) ?? [:]
    }
}

private struct Service {
    let conn: MD.Ref

    func send(_ message: [String: Any]) throws {
        let obj = message as NSDictionary
        try withExtendedLifetime(obj) {
            try check(MD.send(conn, Unmanaged.passUnretained(obj).toOpaque(), MD.xmlFormat), "Sending data to iPhone")
        }
    }

    func receive() throws -> Any {
        var out: UnsafeRawPointer?
        try check(MD.receive(conn, &out, nil), "Reading the iPhone reply")
        guard let out else { throw DeviceError(L("Your iPhone did not respond. Make sure it is unlocked.")) }
        return Unmanaged<AnyObject>.fromOpaque(out).takeRetainedValue()
    }

    func close() { MD.invalidate(conn) }
}
