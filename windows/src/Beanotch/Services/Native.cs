using System.Runtime.InteropServices;

namespace Beanotch.Services;

static partial class Native
{
    [LibraryImport("user32.dll")]
    internal static partial uint GetDpiForWindow(nint hwnd);

    [LibraryImport("gdi32.dll")]
    private static partial nint CreateRoundRectRgn(int left, int top, int right, int bottom, int width, int height);

    [LibraryImport("user32.dll")]
    private static partial int SetWindowRgn(nint hwnd, nint region, [MarshalAs(UnmanagedType.Bool)] bool redraw);

    [LibraryImport("kernel32.dll")]
    internal static partial uint SetThreadExecutionState(uint flags);

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
    internal static void Notch(nint hwnd, int width, int height, int ear, int radius)
    {
        var body = CreateRoundRectRgn(ear, -radius, width - ear + 1, height + 1, radius * 2, radius * 2);
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
}
