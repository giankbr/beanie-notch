using System.Runtime.InteropServices;

namespace Beanotch.Services;

static partial class Native
{
    [LibraryImport("user32.dll")]
    internal static partial uint GetDpiForWindow(nint hwnd);

    [LibraryImport("user32.dll")]
    private static partial uint GetDpiForSystem();

    internal static double SystemDpi() => Math.Max(96, GetDpiForSystem());

    [LibraryImport("gdi32.dll")]
    private static partial nint CreateRoundRectRgn(int left, int top, int right, int bottom, int width, int height);

    [LibraryImport("user32.dll")]
    private static partial int SetWindowRgn(nint hwnd, nint region, [MarshalAs(UnmanagedType.Bool)] bool redraw);

    [LibraryImport("kernel32.dll")]
    internal static partial uint SetThreadExecutionState(uint flags);

    [LibraryImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static partial nint GetWindowLongPtr(nint hwnd, int index);

    [LibraryImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static partial nint SetWindowLongPtr(nint hwnd, int index, nint value);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SetWindowPos(nint hwnd, nint after, int x, int y, int cx, int cy, uint flags);

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    private struct MonitorInfo { public int Size; public Rect Monitor, Work; public uint Flags; }

    [LibraryImport("user32.dll")]
    private static partial nint GetForegroundWindow();

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetWindowRect(nint hwnd, out Rect rect);

    [LibraryImport("user32.dll")]
    private static partial nint MonitorFromWindow(nint hwnd, uint flags);

    [LibraryImport("user32.dll", EntryPoint = "GetMonitorInfoW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetMonitorInfo(nint monitor, ref MonitorInfo info);

    [LibraryImport("user32.dll", EntryPoint = "GetClassNameW", StringMarshalling = StringMarshalling.Utf16)]
    private static partial int GetClassName(nint hwnd, [Out] char[] name, int max);

    [LibraryImport("shell32.dll")]
    private static partial int SHQueryUserNotificationState(out int state);

    // Something fills the island's screen: a game (Direct3D full screen), a slideshow, or any window, a video
    // player in full screen say, covering the whole monitor. The desktop and the taskbar don't count.
    internal static bool FullscreenAppOpen(nint island)
    {
        if (SHQueryUserNotificationState(out var state) == 0 && state is 3 or 4) return true; // D3D full screen, presentation mode
        var front = GetForegroundWindow();
        if (front == 0 || front == island) return false;
        var name = new char[64];
        var length = GetClassName(front, name, name.Length);
        if (new string(name, 0, Math.Max(length, 0)) is "Progman" or "WorkerW" or "Shell_TrayWnd" or "Shell_SecondaryTrayWnd") return false;
        var monitor = MonitorFromWindow(front, 2); // nearest
        if (monitor != MonitorFromWindow(island, 2)) return false;
        var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
        if (!GetMonitorInfo(monitor, ref info) || !GetWindowRect(front, out var r)) return false;
        return r.Left <= info.Monitor.Left && r.Top <= info.Monitor.Top && r.Right >= info.Monitor.Right && r.Bottom >= info.Monitor.Bottom;
    }

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool MessageBeep(uint type);

    // The system's "asterisk" sound, for a prayer time.
    internal static void Chime() => MessageBeep(0x40);

    [LibraryImport("dwmapi.dll")]
    private static partial int DwmSetWindowAttribute(nint hwnd, int attribute, ref uint value, int size);

    // A bare popup: no frame at all. With the title bar merely hidden, Windows 11 still rounds the corners and draws a
    // hairline border, which lifts the notch off the top edge of the screen.
    internal static void Frameless(nint hwnd)
    {
        const long caption = 0x00C00000, thickFrame = 0x00040000, sysMenu = 0x00080000, minBox = 0x00020000, maxBox = 0x00010000, popup = 0x80000000;
        var style = (long)GetWindowLongPtr(hwnd, -16);
        SetWindowLongPtr(hwnd, -16, (nint)((style & ~(caption | thickFrame | sysMenu | minBox | maxBox)) | popup));
        var ex = (long)GetWindowLongPtr(hwnd, -20);
        SetWindowLongPtr(hwnd, -20, (nint)(ex & ~(0x1L | 0x100L | 0x200L | 0x20000L))); // dialog frame, window, client and static edges
        uint square = 1, noBorder = 0xFFFFFFFE;
        DwmSetWindowAttribute(hwnd, 33, ref square, 4);   // DWMWA_WINDOW_CORNER_PREFERENCE = DWMWCP_DONOTROUND
        DwmSetWindowAttribute(hwnd, 34, ref noBorder, 4); // DWMWA_BORDER_COLOR = DWMWA_COLOR_NONE
        // Windows 11 still keeps a sliver of frame (a light line along the edges) on a window without a title bar: the
        // window's whole area is made client area, and what shows behind the content is painted black like the notch.
        unsafe { SetWindowSubclass(hwnd, &NoFrame, 7, 0); }
        SetWindowPos(hwnd, 0, 0, 0, 0, 0, 0x0020 | 0x0002 | 0x0001 | 0x0004 | 0x0010); // FRAMECHANGED | NOMOVE | NOSIZE | NOZORDER | NOACTIVATE
    }

    [LibraryImport("comctl32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static unsafe partial bool SetWindowSubclass(nint hwnd, delegate* unmanaged[Stdcall]<nint, uint, nint, nint, nuint, nuint, nint> proc, nuint id, nuint data);

    [LibraryImport("comctl32.dll")]
    private static partial nint DefSubclassProc(nint hwnd, uint message, nint wParam, nint lParam);

    [LibraryImport("gdi32.dll")]
    private static partial nint GetStockObject(int index);

    [LibraryImport("user32.dll")]
    private static partial int FillRect(nint dc, in Rect rect, nint brush);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetClientRect(nint hwnd, out Rect rect);

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvStdcall)])]
    private static nint NoFrame(nint hwnd, uint message, nint wParam, nint lParam, nuint id, nuint data)
    {
        switch (message)
        {
            case 0x0083 when wParam != 0: // WM_NCCALCSIZE: the client area is the whole window
                return 0;
            case 0x0014 when GetClientRect(hwnd, out var rect): // WM_ERASEBKGND: black, never the system's white
                FillRect(wParam, rect, GetStockObject(4)); // BLACK_BRUSH
                return 1;
        }
        return DefSubclassProc(hwnd, message, wParam, lParam);
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct FileOperation
    {
        public nint Window;
        public uint Function;
        public string From;
        public string? To;
        public ushort Flags;
        [MarshalAs(UnmanagedType.Bool)] public bool Aborted;
        public nint NameMappings;
        public string? Title;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHFileOperationW(ref FileOperation operation);

    // Moves a file or folder to the Recycle Bin, so a mistake can be undone.
    internal static void Recycle(string path)
    {
        var op = new FileOperation
        {
            Function = 3, // FO_DELETE
            From = path + "\0\0",
            Flags = 0x0040 | 0x0010 | 0x0004 | 0x0400, // FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI
        };
        SHFileOperationW(ref op);
    }

    [LibraryImport("gdi32.dll")]
    private static partial nint CreateRectRgn(int left, int top, int right, int bottom);

    [LibraryImport("gdi32.dll")]
    private static partial nint CreateEllipticRgn(int left, int top, int right, int bottom);

    [LibraryImport("gdi32.dll")]
    private static partial int CombineRgn(nint destination, nint first, nint second, int mode);

    [LibraryImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool DeleteObject(nint handle);

    // The MacBook notch's outline: flat along the top edge of the screen, rounded at the bottom, and with a concave
    // shoulder on each side where it meets the top edge. The body sits between the shoulders.
    internal static void Notch(nint hwnd, int width, int height, int ear, int radius, bool floating = false)
    {
        // Floating is rounded at the top too; otherwise the top corners run off the screen's edge, square.
        var body = CreateRoundRectRgn(ear, floating ? 0 : -radius, width - ear + 1, height + 1, radius * 2, radius * 2);
        if (ear > 0)
        {
            foreach (var (left, centre) in new[] { (0, 0), (width - ear, width) })
            {
                // A square at the top corner, less the circle that curves from the top edge down into the body's side.
                var square = CreateRectRgn(left, 0, left + ear, ear);
                var circle = CreateEllipticRgn(centre - ear, 0, centre + ear + 1, ear * 2 + 1);
                CombineRgn(square, square, circle, 4 /* RGN_DIFF */);
                CombineRgn(body, body, square, 2 /* RGN_OR */);
                DeleteObject(square);
                DeleteObject(circle);
            }
        }
        SetWindowRgn(hwnd, body, true);
    }

    [LibraryImport("user32.dll", EntryPoint = "SendMessageTimeoutW", StringMarshalling = StringMarshalling.Utf16)]
    private static partial nint SendMessageTimeout(nint hwnd, uint msg, nint wParam, string lParam, uint flags, uint timeout, out nint result);

    // Tells open programs (Explorer, new terminals) that the user's PATH changed.
    internal static void EnvironmentChanged() => SendMessageTimeout(0xFFFF, 0x001A, 0, "Environment", 0x0002, 1000, out _);

    [StructLayout(LayoutKind.Sequential)]
    private struct LastInput { public uint Size, Time; }

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetLastInputInfo(ref LastInput info);

    // How long since the last key press or mouse move.
    internal static TimeSpan Idle
    {
        get
        {
            var info = new LastInput { Size = (uint)Marshal.SizeOf<LastInput>() };
            return GetLastInputInfo(ref info) ? TimeSpan.FromMilliseconds(unchecked((uint)Environment.TickCount - info.Time)) : TimeSpan.Zero;
        }
    }
}
