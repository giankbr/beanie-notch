import AppKit
import CoreAudio
import CoreMediaIO

// A call in progress, told from the microphone or a camera being in use by any app (Zoom, Meet in a browser,
// FaceTime…). While it lasts the notch shows how long it's been and whether the mic is muted, and alerts that can
// wait are held until it's over.
@MainActor
final class MeetingWatcher: ObservableObject {
    @Published private(set) var since: Date?
    @Published private(set) var camera = false
    @Published private(set) var micMuted = false
    var onEnd: ((TimeInterval) -> Void)?
    private var timer: Timer?
    private var activeFor = 0, idleFor = 0
    private var micVolumeBeforeMute: Float32?

    var inCall: Bool { since != nil }

    func setEnabled(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        guard on else { since = nil; return }
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func toggleMute() {
        micMuted.toggle()
        micVolumeBeforeMute = Microphone.setMuted(micMuted, restoring: micVolumeBeforeMute)
    }

    // A few seconds either way, so dictation or a quick voice memo isn't a call, and a blip doesn't end one.
    private func poll() {
        let cam = Self.cameraInUse
        let active = Self.micInUse || cam
        camera = cam
        if active {
            idleFor = 0
            activeFor += 1
            if since == nil, activeFor >= 3 {
                since = Date().addingTimeInterval(-6)
                micMuted = Microphone.isMuted
            }
        } else {
            activeFor = 0
            idleFor += 1
            if let start = since, idleFor >= 2 {
                since = nil
                onEnd?(Date().timeIntervalSince(start))
            }
        }
    }

    private static var micInUse: Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return false }
        var running = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    private static var cameraInUse: Bool {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size = UInt32(0)
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used = UInt32(0)
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices) == noErr else { return false }
        address.mSelector = CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)
        return devices.contains { device in
            var running = UInt32(0)
            var got = UInt32(0)
            return CMIOObjectGetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &running) == noErr && running != 0
        }
    }
}
