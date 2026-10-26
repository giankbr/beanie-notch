import AppKit
import CoreAudio
import IOKit.ps

@MainActor
final class PowerMonitor: ObservableObject {
    @Published var present = false
    @Published var percent = 0
    @Published var plugged = false
    @Published var charging = false
    var onNotice: ((Notice) -> Void)?
    private var lowWarned = false
    private var source: CFRunLoopSource?

    init() {
        read(announce: false)
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let me = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { me.read(announce: true) }
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    private func read(announce: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for item in list {
            guard let d = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let pct = max > 0 ? current * 100 / max : current
            let onAC = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let wasPlugged = plugged
            let isCharging = d[kIOPSIsChargingKey] as? Bool ?? false
            if !present { present = true }
            if percent != pct { percent = pct }
            if plugged != onAC { plugged = onAC }
            if charging != isCharging { charging = isCharging }

            if announce, onAC != wasPlugged {
                onNotice?(Notice(icon: onAC ? "bolt.fill" : "battery.75percent", color: onAC ? Theme.accent : Theme.dim,
                                 left: onAC ? "Charging" : "On battery", right: "\(pct)%"))
            }
            if onAC {
                lowWarned = false
            } else if pct <= 20, !lowWarned {
                lowWarned = true
                onNotice?(Notice(icon: "battery.25percent", color: Theme.red, left: "Low battery", right: "\(pct)%", duration: 6))
            }
            return
        }
    }
}

// The sound output: lists the devices to pick from, switches between them, and announces Bluetooth
// headphones (AirPods and the like) when they become the output.
@MainActor
final class AudioOutputMonitor: ObservableObject {
    struct Device: Identifiable, Hashable {
        let id: AudioDeviceID
        let name: String
        let bluetooth: Bool
    }

    @Published private(set) var current: AudioDeviceID
    var onNotice: ((Notice) -> Void)?
    var onBluetooth: ((String) -> Void)?

    var currentName: String { Self.name(current) }

    init() {
        current = Self.defaultOutput()
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.outputChanged() }
        }
    }

    // Read when the menu opens, so devices that come and go are always current.
    var devices: [Device] {
        var size: UInt32 = 0
        var address = Self.address(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter(Self.hasOutput).map { Device(id: $0, name: Self.name($0), bluetooth: Self.isBluetooth($0)) }
    }

    func select(_ device: Device) {
        var id = device.id
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                   UInt32(MemoryLayout<AudioDeviceID>.size), &id)
    }

    private func outputChanged() {
        let id = Self.defaultOutput()
        guard id != current else { return }
        current = id
        guard Self.isBluetooth(id) else { return }
        let title = Self.name(id)
        onNotice?(Notice(icon: title.localizedCaseInsensitiveContains("airpods") ? "airpodspro" : "headphones",
                         color: Theme.accent2, left: "Connected", right: title))
        // Headphones report their charge a few seconds after connecting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            MainActor.assumeIsolated { self?.onBluetooth?(title) }
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func get<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: inout T) -> Bool {
        var address = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) == noErr
        }
    }

    private static func defaultOutput() -> AudioDeviceID {
        var id = AudioDeviceID(0)
        _ = get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, &id)
        return id
    }

    private static func name(_ id: AudioDeviceID) -> String {
        var name: Unmanaged<CFString>?
        _ = get(id, kAudioObjectPropertyName, &name)
        return name?.takeRetainedValue() as String? ?? "Speakers"
    }

    private static func isBluetooth(_ id: AudioDeviceID) -> Bool {
        var transport: UInt32 = 0
        return get(id, kAudioDevicePropertyTransportType, &transport)
            && (transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE)
    }

    private static func hasOutput(_ id: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }
}

// Watches the folder screenshots are saved to (Desktop unless changed in the Screenshot app) and picks out
// new files carrying the screen-capture mark macOS puts on every screenshot. Spotlight would be simpler, but
// it hides results from Desktop unless the app has been granted access through it.
@MainActor
final class ScreenshotWatcher {
    var onShot: ((URL) -> Void)?
    private var source: DispatchSourceFileSystemObject?
    private var seen = Set<String>()

    private var folder: URL {
        if let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    func setEnabled(_ on: Bool) {
        source?.cancel()
        source = nil
        guard on else { return }
        let dir = folder
        seen = Set(Self.files(in: dir).map(\.path))
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        s.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scan(dir) }
        }
        s.setCancelHandler { close(fd) }
        s.resume()
        source = s
    }

    private func scan(_ dir: URL) {
        for url in Self.files(in: dir) where !seen.contains(url.path) {
            seen.insert(url.path)
            if Self.isScreenshot(url) {
                onShot?(url)
            } else {
                // The mark can land a moment after the file appears.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    MainActor.assumeIsolated { if Self.isScreenshot(url) { self?.onShot?(url) } }
                }
            }
        }
    }

    nonisolated private static func files(in dir: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
    }

    nonisolated private static func isScreenshot(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0
    }
}
