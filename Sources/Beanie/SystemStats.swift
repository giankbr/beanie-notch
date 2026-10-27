import CSensors
import Darwin
import Foundation

@MainActor
final class SystemStats: ObservableObject {
    @Published var cpu: Double = 0
    @Published var ramUsed: UInt64 = 0
    @Published var disk: Double = 0
    @Published private(set) var temperature: Int?
    @Published private(set) var download: Int64 = 0
    @Published private(set) var upload: Int64 = 0
    @Published private(set) var diskTotal: Int64 = 0
    @Published private(set) var diskFree: Int64 = 0
    let ramTotal = ProcessInfo.processInfo.physicalMemory

    private var lastTicks: (used: UInt64, total: UInt64)?
    private var timer: Timer?
    private var diskCheckedAt = Date.distantPast
    private var lastNetwork: (counts: [String: (rx: UInt32, tx: UInt32)], at: Date)?

    var ram: Double { ramTotal == 0 ? 0 : Double(ramUsed) / Double(ramTotal) }

    init() {
        refresh()
    }

    // Only sampled while someone can see the numbers.
    func setActive(_ active: Bool) {
        timer?.invalidate()
        timer = nil
        guard active else { return }
        refresh()
        let t = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        t.tolerance = 0.3
        timer = t
    }

    // Values are rounded to what the panel shows and only published when that changes, so an unchanged
    // reading doesn't redraw anything.
    func refresh() {
        let ticks = Self.cpuTicks()
        if let last = lastTicks, ticks.total > last.total, ticks.used >= last.used {
            let value = (Double(ticks.used - last.used) / Double(ticks.total - last.total) * 100).rounded() / 100
            if value != cpu { cpu = value }
        }
        lastTicks = ticks

        let used = Self.memoryUsed()
        if used / 10_000_000 != ramUsed / 10_000_000 { ramUsed = used }

        let celsius = beanie_cpu_temperature()
        let temp = celsius > 0 ? Int(celsius.rounded()) : nil
        if temp != temperature { temperature = temp }

        let counts = Self.networkCounts()
        let now = Date()
        if let last = lastNetwork, now.timeIntervalSince(last.at) > 0.2 {
            var rx: UInt64 = 0, tx: UInt64 = 0
            for (name, c) in counts {
                guard let old = last.counts[name] else { continue }
                // The kernel keeps 32-bit counters; wrapping subtraction survives them rolling over.
                rx += UInt64(c.rx &- old.rx)
                tx += UInt64(c.tx &- old.tx)
            }
            let seconds = now.timeIntervalSince(last.at)
            let down = Int64(Double(rx) / seconds) / 1024 * 1024, up = Int64(Double(tx) / seconds) / 1024 * 1024
            if down != download { download = down }
            if up != upload { upload = up }
        }
        lastNetwork = (counts, now)

        // Free space goes through CacheDelete (it counts purgeable space) and is slow, so at most every 30 s.
        guard Date().timeIntervalSince(diskCheckedAt) > 30 else { return }
        diskCheckedAt = Date()
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
           let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage, total > 0 {
            let value = ((1 - Double(free) / Double(total)) * 100).rounded() / 100
            if value != disk { disk = value }
            diskTotal = Int64(total)
            diskFree = free
        }
    }

    // Bytes in and out per Wi-Fi or Ethernet interface (en0, en1…), from the link-level statistics.
    private static func networkCounts() -> [String: (rx: UInt32, tx: UInt32)] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [:] }
        defer { freeifaddrs(list) }
        var counts: [String: (rx: UInt32, tx: UInt32)] = [:]
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  entry.ifa_flags & UInt32(IFF_UP) != 0, let data = entry.ifa_data else { continue }
            let name = String(cString: entry.ifa_name)
            guard name.hasPrefix("en") else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            counts[name] = (stats.ifi_ibytes, stats.ifi_obytes)
        }
        return counts
    }

    private static func cpuTicks() -> (used: UInt64, total: UInt64) {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + idle + nice)
    }

    // Same sum Activity Monitor calls "Memory Used": app memory + wired + compressed.
    private static func memoryUsed() -> UInt64 {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let page = UInt64(getpagesize())
        let app = UInt64(vm.internal_page_count) - min(UInt64(vm.internal_page_count), UInt64(vm.purgeable_count))
        return (app + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * page
    }
}
