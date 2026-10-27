using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace Beanotch.Services;

// The Mac's Controls tab, with Windows' own switches: dark mode, keep awake, mic mute, taskbar auto-hide, desktop
// icons and hidden files; brightness for the built-in screen (WMI) and external monitors (DDC/CI); and a few actions.
public static partial class Controls
{
    private const string Personalize = @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
    private const string Advanced = @"Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced";

    // Dark mode

    public static bool DarkMode
    {
        get => Registry.CurrentUser.OpenSubKey(Personalize)?.GetValue("AppsUseLightTheme") is int light && light == 0;
        set
        {
            using var key = Registry.CurrentUser.CreateSubKey(Personalize);
            key.SetValue("AppsUseLightTheme", value ? 0 : 1, RegistryValueKind.DWord);
            key.SetValue("SystemUsesLightTheme", value ? 0 : 1, RegistryValueKind.DWord);
            Broadcast("ImmersiveColorSet");
        }
    }

    // Keep awake

    private static bool awake;

    public static bool KeepAwake
    {
        get => awake;
        set
        {
            awake = value;
            // ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED, or ES_CONTINUOUS alone to let go.
            Native.SetThreadExecutionState(value ? 0x80000003u : 0x80000000u);
        }
    }

    // Mic

    public static bool MicMuted
    {
        get => Audio.MicrophoneMuted() ?? false;
        set => Audio.SetMicrophoneMuted(value);
    }

    // Taskbar auto-hide

    [StructLayout(LayoutKind.Sequential)]
    private struct AppBarData
    {
        public uint Size;
        public nint Window;
        public uint CallbackMessage, Edge;
        public int Left, Top, Right, Bottom;
        public nint Param;
    }

    [LibraryImport("shell32.dll")]
    private static partial nuint SHAppBarMessage(uint message, ref AppBarData data);

    [LibraryImport("user32.dll", StringMarshalling = StringMarshalling.Utf16)]
    private static partial nint FindWindowW(string? className, string? windowName);

    [LibraryImport("user32.dll", StringMarshalling = StringMarshalling.Utf16)]
    private static partial nint FindWindowExW(nint parent, nint after, string? className, string? windowName);

    [LibraryImport("user32.dll")]
    private static partial nint SendMessageW(nint window, uint message, nint w, nint l);

    [LibraryImport("user32.dll", StringMarshalling = StringMarshalling.Utf16)]
    private static partial nint SendMessageTimeoutW(nint window, uint message, nint w, string l, uint flags, uint timeout, out nint result);

    public static bool TaskbarHidden
    {
        get
        {
            var data = new AppBarData { Size = (uint)Marshal.SizeOf<AppBarData>(), Window = FindWindowW("Shell_TrayWnd", null) };
            return ((uint)SHAppBarMessage(4 /* ABM_GETSTATE */, ref data) & 1) != 0;
        }
        set
        {
            var data = new AppBarData { Size = (uint)Marshal.SizeOf<AppBarData>(), Window = FindWindowW("Shell_TrayWnd", null), Param = value ? 1 : 2 };
            SHAppBarMessage(10 /* ABM_SETSTATE */, ref data);
        }
    }

    // Desktop icons: Explorer toggles them itself on this command, and saves the choice.

    public static bool DesktopIcons
    {
        get => Registry.CurrentUser.OpenSubKey(Advanced)?.GetValue("HideIcons") is not int hide || hide == 0;
        set
        {
            if (value == DesktopIcons) return;
            var view = DesktopView();
            if (view != 0) SendMessageW(view, 0x0111 /* WM_COMMAND */, 0x7402, 0);
        }
    }

    private static nint DesktopView()
    {
        var progman = FindWindowW("Progman", null);
        var view = FindWindowExW(progman, 0, "SHELLDLL_DefView", null);
        if (view != 0) return view;
        // After the wallpaper has changed, the view lives under one of the WorkerW windows instead.
        nint worker = 0;
        while ((worker = FindWindowExW(0, worker, "WorkerW", null)) != 0)
        {
            view = FindWindowExW(worker, 0, "SHELLDLL_DefView", null);
            if (view != 0) return view;
        }
        return 0;
    }

    // Hidden files

    [LibraryImport("shell32.dll")]
    private static partial void SHChangeNotify(int eventId, uint flags, nint item1, nint item2);

    public static bool HiddenFiles
    {
        get => Registry.CurrentUser.OpenSubKey(Advanced)?.GetValue("Hidden") is int h && h == 1;
        set
        {
            using var key = Registry.CurrentUser.CreateSubKey(Advanced);
            key.SetValue("Hidden", value ? 1 : 2, RegistryValueKind.DWord);
            SHChangeNotify(0x08000000 /* SHCNE_ASSOCCHANGED */, 0, 0, 0);
            Broadcast("ShellState");
        }
    }

    private static void Broadcast(string area) =>
        SendMessageTimeoutW(0xFFFF /* HWND_BROADCAST */, 0x001A /* WM_SETTINGCHANGE */, 0, area, 2 /* SMTO_ABORTIFHUNG */, 200, out _);

    // Actions

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool LockWorkStation();

    [LibraryImport("powrprof.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SetSuspendState([MarshalAs(UnmanagedType.Bool)] bool hibernate, [MarshalAs(UnmanagedType.Bool)] bool force,
                                                [MarshalAs(UnmanagedType.Bool)] bool disableWake);

    [LibraryImport("shell32.dll", StringMarshalling = StringMarshalling.Utf16)]
    private static partial int SHEmptyRecycleBinW(nint window, string? root, uint flags);

    public static void Lock() => LockWorkStation();
    public static void Sleep() => SetSuspendState(false, false, false);
    public static void Snip() => Launch("ms-screenclip:");
    public static void EmptyRecycleBin() => SHEmptyRecycleBinW(0, null, 0x1 /* SHERB_NOCONFIRMATION */ | 0x4 /* SHERB_NOSOUND */);
    public static void Camera() => Launch("microsoft.windows.camera:");
    public static void Settings(string page = "") => Launch("ms-settings:" + page);

    public static void Launch(string target)
    {
        try { Process.Start(new ProcessStartInfo(target) { UseShellExecute = true }); }
        catch (Exception) { }
    }
}
