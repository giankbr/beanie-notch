using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace Beanotch.Services;

public sealed record Display(string Name, int Level, bool BuiltIn, nint Handle);

// Built-in screens through WMI (a short PowerShell call, since the WMI client libraries don't survive trimming), and
// external monitors over DDC/CI, the same way the Mac app drives them.
public static unsafe partial class Brightness
{
    [StructLayout(LayoutKind.Sequential)]
    private struct PhysicalMonitor
    {
        public nint Handle;
        public fixed char Description[128];
    }

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool EnumDisplayMonitors(nint dc, nint clip, delegate* unmanaged<nint, nint, nint, nint, int> callback, nint data);

    [LibraryImport("dxva2.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetNumberOfPhysicalMonitorsFromHMONITOR(nint monitor, out uint count);

    [LibraryImport("dxva2.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetPhysicalMonitorsFromHMONITOR(nint monitor, uint count, PhysicalMonitor* monitors);

    [LibraryImport("dxva2.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetVCPFeatureAndVCPFeatureReply(nint monitor, byte code, out uint type, out uint current, out uint maximum);

    [LibraryImport("dxva2.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SetVCPFeature(nint monitor, byte code, uint value);

    private static readonly List<nint> Found = [];

    [UnmanagedCallersOnly]
    private static int Collect(nint monitor, nint dc, nint rect, nint data)
    {
        Found.Add(monitor);
        return 1;
    }

    // DDC/CI answers slowly (tens of milliseconds per monitor), so callers run this off the UI thread.
    public static List<Display> Read()
    {
        var displays = new List<Display>();
        if (BuiltInLevel() is int builtIn) displays.Add(new Display("Built-in display", builtIn, true, 0));
        lock (Found)
        {
            Found.Clear();
            EnumDisplayMonitors(0, 0, &Collect, 0);
            foreach (var monitor in Found)
            {
                if (!GetNumberOfPhysicalMonitorsFromHMONITOR(monitor, out var count) || count == 0) continue;
                var physical = new PhysicalMonitor[count];
                fixed (PhysicalMonitor* p = physical)
                {
                    if (!GetPhysicalMonitorsFromHMONITOR(monitor, count, p)) continue;
                    for (var i = 0; i < count; i++)
                    {
                        if (!GetVCPFeatureAndVCPFeatureReply(p[i].Handle, 0x10, out _, out var current, out var max) || max == 0) continue;
                        var name = new string(p[i].Description).TrimEnd('\0');
                        displays.Add(new Display(name.Length > 0 && name != "Generic PnP Monitor" ? name : "External display",
                                                 (int)Math.Round(current * 100.0 / max), false, p[i].Handle));
                    }
                }
            }
        }
        return displays;
    }

    public static void Set(Display display, int level)
    {
        level = Math.Clamp(level, 0, 100);
        if (display.BuiltIn) SetBuiltIn(level);
        else SetVCPFeature(display.Handle, 0x10, (uint)level);
    }

    private static int? BuiltInLevel()
    {
        var output = PowerShell("(Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness -ErrorAction SilentlyContinue | Select-Object -First 1).CurrentBrightness");
        return int.TryParse(output?.Trim(), out var level) ? level : null;
    }

    private static void SetBuiltIn(int level) =>
        PowerShell($"Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods | Invoke-CimMethod -MethodName WmiSetBrightness -Arguments @{{Timeout=1;Brightness={level}}} | Out-Null");

    private static string? PowerShell(string command)
    {
        try
        {
            using var process = Process.Start(new ProcessStartInfo("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", command])
            {
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true,
            });
            if (process is null) return null;
            var output = process.StandardOutput.ReadToEnd();
            process.WaitForExit(4000);
            return output;
        }
        catch (Exception) { return null; }
    }
}
