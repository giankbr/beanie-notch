using System.Runtime.InteropServices;

namespace Beanotch;

static class Native
{
    [DllImport("user32.dll")]
    internal static extern uint GetDpiForWindow(nint hwnd);

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(nint hwnd, int attribute, ref int value, int size);

    // Windows 11 rounds the island's corners itself (DWMWA_WINDOW_CORNER_PREFERENCE = DWMWCP_ROUND).
    internal static void RoundCorners(nint hwnd)
    {
        var round = 2;
        DwmSetWindowAttribute(hwnd, 33, ref round, sizeof(int));
    }
}
