import AppKit
import CoreAudio
import IOKit

// One-click switches for things macOS buries in System Settings. Each reads its state from the system when
// the Controls page appears, so changes made elsewhere show up.
@MainActor
final class QuickToggles: ObservableObject {
    @Published private(set) var darkMode = false
    @Published private(set) var desktopIcons = true
    @Published private(set) var nightShift = false
    @Published private(set) var micMuted = false
    @Published private(set) var dockHidden = false
    private var micVolumeBeforeMute: Float32?

    func refresh() {
        darkMode = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        desktopIcons = CFPreferencesCopyAppValue("CreateDesktop" as CFString, "com.apple.finder" as CFString) as? Bool ?? true
        nightShift = NightShift.isOn
        micMuted = Microphone.isMuted
        dockHidden = CFPreferencesCopyAppValue("autohide" as CFString, "com.apple.dock" as CFString) as? Bool ?? false
    }

    // Through System Events, which asks once for permission to control it.
    func toggleDarkMode() {
        darkMode.toggle()
        run("tell application \"System Events\" to tell appearance preferences to set dark mode to \(darkMode)")
    }

    func toggleDockHidden() {
        dockHidden.toggle()
        run("tell application \"System Events\" to tell dock preferences to set autohide to \(dockHidden)")
    }

    // Finder reads this once, at launch, so it's restarted; its windows come back on their own.
    func toggleDesktopIcons() {
        desktopIcons.toggle()
        CFPreferencesSetAppValue("CreateDesktop" as CFString, desktopIcons as CFBoolean, "com.apple.finder" as CFString)
        CFPreferencesAppSynchronize("com.apple.finder" as CFString)
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").forEach { $0.terminate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
                                               configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func toggleNightShift() {
        nightShift.toggle()
        NightShift.set(nightShift)
    }

    func toggleMic() {
        micMuted.toggle()
        micVolumeBeforeMute = Microphone.setMuted(micMuted, restoring: micVolumeBeforeMute)
    }

    private func run(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
        }
    }
}

// Night Shift through CoreBrightness (private), loaded at run time.
enum NightShift {
    private static let client: NSObject? = {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        return (NSClassFromString("CBBlueLightClient") as? NSObject.Type)?.init()
    }()

    static var available: Bool { client != nil }

    static var isOn: Bool {
        let selector = NSSelectorFromString("getBlueLightStatus:")
        guard let client, client.responds(to: selector) else { return false }
        typealias Status = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        let status = unsafeBitCast(client.method(for: selector), to: Status.self)
        // The status struct starts with two flags: whether the schedule is active, and whether it's on now.
        var buffer = [UInt8](repeating: 0, count: 64)
        let ok = buffer.withUnsafeMutableBytes { status(client, selector, $0.baseAddress!) }
        return ok && buffer[1] != 0
    }

    static func set(_ on: Bool) {
        let selector = NSSelectorFromString("setEnabled:")
        guard let client, client.responds(to: selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Bool
        _ = unsafeBitCast(client.method(for: selector), to: Setter.self)(client, selector, on)
    }
}

// The default input's mute switch, or its level for microphones without one.
enum Microphone {
    private static var device: AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
    }

    static var isMuted: Bool {
        var address = address(kAudioDevicePropertyMute)
        var mute = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &mute) == noErr { return mute != 0 }
        address = Self.address(kAudioDevicePropertyVolumeScalar)
        var volume = Float32(1)
        size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume)
        return volume == 0
    }

    // Returns the level to restore on unmute when the level had to be used instead of the switch.
    static func setMuted(_ muted: Bool, restoring previous: Float32?) -> Float32? {
        let id = device
        var address = address(kAudioDevicePropertyMute)
        var settable: DarwinBoolean = false
        if AudioObjectIsPropertySettable(id, &address, &settable) == noErr, settable.boolValue {
            var value = UInt32(muted ? 1 : 0)
            AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
            return nil
        }
        address = Self.address(kAudioDevicePropertyVolumeScalar)
        var current = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &current)
        var value: Float32 = muted ? 0 : (previous ?? 0.75)
        AudioObjectSetPropertyData(id, &address, 0, nil, size, &value)
        return muted ? current : nil
    }
}

// The Shortcuts app's shortcuts, through its command-line tool.
@MainActor
final class ShortcutsRunner: ObservableObject {
    @Published private(set) var names: [String] = []
    @Published private(set) var running: String?
    @Published private(set) var loaded = false
    var onDone: ((String, Bool) -> Void)?

    func load() {
        Task {
            let output = await Self.shortcuts(["list"])
            names = (output ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            loaded = true
        }
    }

    func run(_ name: String) {
        guard running == nil else { return }
        running = name
        Task {
            let ok = await Self.shortcuts(["run", name]) != nil
            running = nil
            onDone?(name, ok)
        }
    }

    nonisolated private static func shortcuts(_ arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { p in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil)
            }
            do { try process.run() } catch { continuation.resume(returning: nil) }
        }
    }
}

// The Mac's battery wear and the charge of connected Bluetooth devices (AirPods report each bud and the case).
@MainActor
final class BatteryInfo: ObservableObject {
    struct Device: Identifiable, Hashable {
        let name: String
        let levels: [(label: String, percent: Int)]
        var id: String { name }
        static func == (a: Device, b: Device) -> Bool { a.name == b.name && a.levels.map(\.percent) == b.levels.map(\.percent) }
        func hash(into hasher: inout Hasher) { hasher.combine(name) }
    }

    @Published private(set) var cycles: Int?
    @Published private(set) var health: Int?
    @Published private(set) var devices: [Device] = []

    func refresh() {
        readMac()
        Task { devices = await Self.bluetooth() }
    }

    private func readMac() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        func value(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        cycles = value("CycleCount") as? Int
        // Health the way System Settings shows it: what a full charge holds now against what it held new.
        if let data = value("BatteryData") as? [String: Any], let design = data["DesignCapacity"] as? Int, design > 0,
           let now = data["NominalChargeCapacity"] as? Int ?? value("AppleRawMaxCapacity") as? Int {
            health = min(100, now * 100 / design)
        }
    }

    // system_profiler is slow (about a second), so it only runs on demand, off the main thread.
    nonisolated static func bluetooth() async -> [Device] {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: parse(data))
            }
            do { try process.run() } catch { continuation.resume(returning: []) }
        }
    }

    nonisolated private static func parse(_ data: Data) -> [Device] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let root = (json["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = root["device_connected"] as? [[String: Any]] else { return [] }
        let keys = [("device_batteryLevelLeft", "L"), ("device_batteryLevelRight", "R"),
                    ("device_batteryLevelCase", "Case"), ("device_batteryLevelMain", "")]
        return connected.flatMap { entry in
            entry.compactMap { name, info -> Device? in
                guard let info = info as? [String: Any] else { return nil }
                let levels = keys.compactMap { key, label -> (String, Int)? in
                    guard let text = info[key] as? String, let percent = Int(text.filter(\.isNumber)) else { return nil }
                    return (label, percent)
                }
                return levels.isEmpty ? nil : Device(name: name, levels: levels)
            }
        }
    }
}

// Brightness for every screen: the built-in one through DisplayServices, external monitors over DDC/CI
// (the IOAVService I²C channel on Apple silicon, the way MonitorControl does it).
@MainActor
final class Displays: ObservableObject {
    struct Screen: Identifiable {
        let id: String
        let name: String
        var level: Double
        let builtIn: Bool
        fileprivate let service: CFTypeRef?
    }

    @Published private(set) var screens: [Screen] = []
    private let queue = DispatchQueue(label: "brow.ddc")
    private var pending: [String: Double] = [:]

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CreateService = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias I2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    nonisolated(unsafe) private static let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    nonisolated(unsafe) private static let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
    private static let getBrightness = dlsym(displayServices, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetBrightness.self) }
    private static let setBrightness = dlsym(displayServices, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetBrightness.self) }
    private static let createService = dlsym(iokit, "IOAVServiceCreateWithService").map { unsafeBitCast($0, to: CreateService.self) }
    nonisolated private static let writeI2C = dlsym(iokit, "IOAVServiceWriteI2C").map { unsafeBitCast($0, to: I2C.self) }
    nonisolated private static let readI2C = dlsym(iokit, "IOAVServiceReadI2C").map { unsafeBitCast($0, to: I2C.self) }

    func refresh() {
        var found: [Screen] = []
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &count)
        if let builtIn = ids.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }), let get = Self.getBrightness {
            var value: Float = 0
            if get(builtIn, &value) == 0 { found.append(Screen(id: "builtin", name: "Built-in display", level: Double(value), builtIn: true, service: nil)) }
        }
        let names = NSScreen.screens.filter { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID).map { CGDisplayIsBuiltin($0) == 0 } ?? false
        }.map(\.localizedName)
        for (i, service) in Self.externalServices().enumerated() {
            let id = "external-\(i)"
            let previous = screens.first { $0.id == id }?.level
            found.append(Screen(id: id, name: i < names.count ? names[i] : "External display \(i + 1)",
                                level: previous ?? 0.5, builtIn: false, service: service))
            // The monitor's own value arrives a moment later; reading takes a round trip over the cable.
            queue.async { [weak self] in
                guard let level = Self.ddcRead(service) else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if let j = self?.screens.firstIndex(where: { $0.id == id }) { self?.screens[j].level = level }
                    }
                }
            }
        }
        screens = found
    }

    func set(_ screen: Screen, _ level: Double) {
        guard let i = screens.firstIndex(where: { $0.id == screen.id }) else { return }
        screens[i].level = level
        if screen.builtIn {
            var ids = [CGDirectDisplayID](repeating: 0, count: 8)
            var count: UInt32 = 0
            CGGetActiveDisplayList(8, &ids, &count)
            if let builtIn = ids.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) {
                _ = Self.setBrightness?(builtIn, Float(level))
            }
        } else if let service = screen.service {
            // Slider moves arrive faster than a monitor takes them: only the latest is sent.
            let first = pending[screen.id] == nil
            pending[screen.id] = level
            guard first else { return }
            queue.async { [weak self] in
                usleep(60_000)
                let latest = DispatchQueue.main.sync { MainActor.assumeIsolated { self?.pending.removeValue(forKey: screen.id) } }
                if let latest { Self.ddcWrite(service, latest) }
            }
        }
    }

    private static func externalServices() -> [CFTypeRef] {
        guard let create = createService else { return [] }
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var services: [CFTypeRef] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            if location == "External", let service = create(kCFAllocatorDefault, entry)?.takeRetainedValue() { services.append(service) }
        }
        return services
    }

    // DDC/CI "set VCP feature" 0x10 (luminance), 0–100.
    nonisolated private static func ddcWrite(_ service: CFTypeRef, _ level: Double) {
        let value = UInt8(max(0, min(100, (level * 100).rounded())))
        send(service, [0x84, 0x03, 0x10, 0x00, value])
    }

    nonisolated private static func ddcRead(_ service: CFTypeRef) -> Double? {
        guard let readI2C else { return nil }
        for _ in 0..<3 {
            send(service, [0x82, 0x01, 0x10])
            usleep(50_000)
            var reply = [UInt8](repeating: 0, count: 12)
            let ok = reply.withUnsafeMutableBytes { readI2C(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count)) } == 0
            // A good reply is a "VCP feature reply" (0x02) for 0x10 with no error, carrying max and current.
            if ok, reply[2] == 0x02, reply[3] == 0, reply[4] == 0x10 {
                let maximum = Double(Int(reply[6]) << 8 | Int(reply[7]))
                let current = Double(Int(reply[8]) << 8 | Int(reply[9]))
                return maximum > 0 ? current / maximum : nil
            }
            usleep(40_000)
        }
        return nil
    }

    nonisolated private static func send(_ service: CFTypeRef, _ body: [UInt8]) {
        guard let writeI2C else { return }
        var packet = body
        packet.append(body.reduce(UInt8(0x6E ^ 0x51), ^))
        _ = packet.withUnsafeMutableBytes { writeI2C(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count)) }
    }
}
