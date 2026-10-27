using System.Net.NetworkInformation;
using System.Runtime.InteropServices;

namespace Beanotch.Services;

// CPU from GetSystemTimes, memory from GlobalMemoryStatusEx, network from the interfaces' byte counters, and the
// system drive's fill. Sampled every two seconds while the panel is open.
public sealed partial class SystemStats
{
    [StructLayout(LayoutKind.Sequential)]
    private struct FileTime { public uint Low, High; public readonly ulong Value => ((ulong)High << 32) | Low; }

    [StructLayout(LayoutKind.Sequential)]
    private struct MemoryStatus
    {
        public uint Length, Load;
        public ulong TotalPhys, AvailPhys, TotalPageFile, AvailPageFile, TotalVirtual, AvailVirtual, AvailExtendedVirtual;
    }

    [LibraryImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetSystemTimes(out FileTime idle, out FileTime kernel, out FileTime user);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GlobalMemoryStatusEx(ref MemoryStatus status);

    private ulong lastIdle, lastBusy;
    private long lastReceived, lastSent;
    private DateTime lastSample;

    public double Cpu { get; private set; }
    public double Ram { get; private set; }
    public ulong RamUsed { get; private set; }
    public ulong RamTotal { get; private set; }
    public double Download { get; private set; }
    public double Upload { get; private set; }
    public double Disk { get; private set; }
    public long DiskFree { get; private set; }

    public void Sample()
    {
        if (GetSystemTimes(out var idle, out var kernel, out var user))
        {
            // Kernel time includes idle time.
            var busy = kernel.Value + user.Value - idle.Value;
            var dIdle = idle.Value - lastIdle;
            var dBusy = busy - lastBusy;
            if (lastBusy != 0 && dIdle + dBusy > 0) Cpu = (double)dBusy / (dIdle + dBusy);
            lastIdle = idle.Value;
            lastBusy = busy;
        }

        var memory = new MemoryStatus { Length = (uint)Marshal.SizeOf<MemoryStatus>() };
        if (GlobalMemoryStatusEx(ref memory))
        {
            RamTotal = memory.TotalPhys;
            RamUsed = memory.TotalPhys - memory.AvailPhys;
            Ram = memory.TotalPhys == 0 ? 0 : (double)RamUsed / memory.TotalPhys;
        }

        long received = 0, sent = 0;
        try
        {
            foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (nic.OperationalStatus != OperationalStatus.Up || nic.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                var s = nic.GetIPv4Statistics();
                received += s.BytesReceived;
                sent += s.BytesSent;
            }
        }
        catch (NetworkInformationException) { }
        var now = DateTime.UtcNow;
        var seconds = (now - lastSample).TotalSeconds;
        if (lastSample != default && seconds > 0)
        {
            Download = Math.Max(0, (received - lastReceived) / seconds);
            Upload = Math.Max(0, (sent - lastSent) / seconds);
        }
        lastReceived = received;
        lastSent = sent;
        lastSample = now;

        try
        {
            var drive = new DriveInfo(Path.GetPathRoot(Environment.SystemDirectory) ?? "C:\\");
            DiskFree = drive.AvailableFreeSpace;
            Disk = drive.TotalSize == 0 ? 0 : 1 - (double)drive.TotalFreeSpace / drive.TotalSize;
        }
        catch (IOException) { }
    }
}

public static class Format
{
    public static string Bytes(double bytes)
    {
        string[] units = ["B", "KB", "MB", "GB", "TB"];
        var i = 0;
        while (bytes >= 1000 && i < units.Length - 1) { bytes /= 1000; i++; }
        return i == 0 ? $"{bytes:0} B" : $"{bytes:0.#} {units[i]}";
    }

    public static string Rate(double bytesPerSecond) => Bytes(bytesPerSecond) + "/s";

    public static string Memory(ulong bytes) => $"{bytes / 1_073_741_824.0:0.#} GB";
}
