import AppKit
import AudioToolbox
import CoreAudio
import IOKit.pwr_mgt

// Keeps the Mac and its display awake, like `caffeinate -d`, for a while or until turned off. The assertion
// belongs to this process, so quitting Brow always lets the Mac sleep again.
@MainActor
final class KeepAwake: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var until: Date?
    private var assertion = IOPMAssertionID(0)
    private var timer: Timer?

    // `minutes` of 0 means until turned off.
    func start(minutes: Int) {
        stop()
        guard IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                                          IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                          "Brow keep awake" as CFString, &assertion) == kIOReturnSuccess else { return }
        active = true
        guard minutes > 0 else { return }
        until = Date().addingTimeInterval(Double(minutes) * 60)
        timer = Timer.scheduledTimer(withTimeInterval: Double(minutes) * 60, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if assertion != 0 { IOPMAssertionRelease(assertion) }
        assertion = 0
        active = false
        until = nil
    }
}

// Downloads in progress, read off the partial files browsers write to Downloads: Chrome and Edge
// `.crdownload`, Safari a `.download` bundle, Firefox `.part`, Opera `.opdownload`.
@MainActor
final class DownloadWatcher: ObservableObject {
    struct Item: Equatable {
        let name: String
        let bytes: Int64
    }

    @Published private(set) var current: Item?
    @Published private(set) var speed: Int64 = 0
    var onDone: ((URL) -> Void)?
    private var source: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var partials: Set<String> = []
    private let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    private static let partialTypes: Set = ["crdownload", "download", "part", "opdownload"]

    func setEnabled(_ on: Bool) {
        source?.cancel()
        source = nil
        stopSampling()
        partials = []
        current = nil
        guard on else { return }
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        s.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.scan() } }
        s.setCancelHandler { close(fd) }
        s.resume()
        source = s
        scan()
    }

    private func scan() {
        let names = Set(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { Self.partialTypes.contains(($0 as NSString).pathExtension.lowercased()) })
        for gone in partials.subtracting(names) {
            // A finished download keeps its name without the partial extension.
            let final = folder.appendingPathComponent((gone as NSString).deletingPathExtension)
            if FileManager.default.fileExists(atPath: final.path) { onDone?(final) }
        }
        partials = names
        if names.isEmpty {
            stopSampling()
            current = nil
        } else if timer == nil {
            sample()
            let t = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            t.tolerance = 0.3
            timer = t
        }
    }

    // The biggest download in progress, and how fast it grows.
    private func sample() {
        let sizes = partials.map { ($0, Self.size(folder.appendingPathComponent($0))) }
        guard let (name, bytes) = sizes.max(by: { $0.1 < $1.1 }) else { return }
        let shown = (name as NSString).deletingPathExtension
        if current?.name == shown { speed = max(0, bytes - (current?.bytes ?? 0)) } else { speed = 0 }
        current = Item(name: shown, bytes: bytes)
    }

    private func stopSampling() {
        timer?.invalidate()
        timer = nil
        speed = 0
    }

    nonisolated private static func size(_ url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        guard isDir.boolValue else { return Int64((try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0) }
        // Safari's bundle holds the growing file inside it.
        return ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).reduce(0) {
            $0 + Int64((try? fm.attributesOfItem(atPath: url.appendingPathComponent($1).path)[.size] as? Int) ?? 0)
        }
    }
}

// The output volume, reported each time it changes, so the notch can show it in place of the system's
// volume overlay. Follows the output device when it changes.
@MainActor
final class VolumeWatcher {
    var onChange: ((Float, Bool) -> Void)?
    private var device = AudioDeviceID(0)
    private var listener: AudioObjectPropertyListenerBlock?
    private var last: (Float, Bool)?

    init() {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attach() }
        }
        attach()
    }

    private func attach() {
        if let listener {
            for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
                var address = Self.address(selector)
                AudioObjectRemovePropertyListenerBlock(device, &address, .main, listener)
            }
        }
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        device = id
        last = read()
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.changed() }
        }
        listener = block
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(device, &address, .main, block)
        }
    }

    func nudge(by delta: Float) {
        guard var volume = read()?.0 else { return }
        volume = max(0, min(1, volume + delta))
        var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
        if volume > 0 {
            var unmute = UInt32(0)
            var muteAddress = Self.address(kAudioDevicePropertyMute)
            AudioObjectSetPropertyData(device, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &unmute)
        }
    }

    private func changed() {
        guard let now = read(), now.0 != last?.0 || now.1 != last?.1 else { return }
        last = now
        onChange?(now.0, now.1)
    }

    private func read() -> (Float, Bool)? {
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return nil }
        var mute = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address = Self.address(kAudioDevicePropertyMute)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &mute)
        return (volume, mute != 0)
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}

extension NSColor {
    var hex: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}

// The built-in display's brightness, through DisplayServices (private, loaded at run time so a missing symbol
// only switches this off). Read a few times a second, which costs next to nothing, and only steps the size
// of a key press count, so auto-brightness drifting in the background doesn't flash the notch.
@MainActor
final class BrightnessWatcher {
    var onChange: ((Float) -> Void)?
    private typealias Getter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private let getter: Getter?
    private var last: Float?
    private var timer: Timer?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        getter = dlsym(handle, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: Getter.self) }
        guard getter != nil else { return }
        last = read()
        let t = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        t.tolerance = 0.05
        timer = t
    }

    private func poll() {
        guard let now = read() else { return }
        defer { last = now }
        guard let last, abs(now - last) >= 0.03 else { return }
        onChange?(now)
    }

    private func read() -> Float? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &count)
        guard let getter, let builtIn = ids.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) else { return nil }
        var value: Float = 0
        return getter(builtIn, &value) == 0 ? value : nil
    }
}
