using System.Runtime.InteropServices;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Shapes;
using Windows.ApplicationModel.DataTransfer;
using Windows.System;
using static Beanotch.Ui.Ui;

namespace Beanotch.Island;

// A ruler over the main screen. Windows can't draw a see-through window cheaply, so the screen is photographed first
// and the ruler works on that still: crosshairs and the pointer's position, and a box with its size in pixels while
// dragging. The size is copied when the drag ends; Esc or a right click closes it.
public sealed partial class RulerWindow : Window
{
    private static RulerWindow? open;
    public static RulerWindow? Showing => open;
    private readonly Canvas overlay = new() { Background = Ui.Theme.Brush(Ui.Theme.Rgb(0, 0, 0, 0.06)) };
    private readonly Line across = new(), down = new();
    private readonly Rectangle box = new() { Visibility = Visibility.Collapsed };
    private readonly Border tag = new() { CornerRadius = new CornerRadius(6), Padding = new Thickness(6, 3, 6, 3) };
    private readonly TextBlock label = new() { FontSize = 12, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold };
    private readonly double scale;
    private Windows.Foundation.Point? start;
    public static Action<string>? Measured;

    public static void ShowRuler()
    {
        if (open is not null) return;
        open = new RulerWindow();
        open.Activate();
    }

    private RulerWindow()
    {
        var (w, h, pixels) = Capture();
        var image = new WriteableBitmap(w, h);
        using (var stream = image.PixelBuffer.AsStream()) stream.Write(pixels);
        image.Invalidate();

        var accent = Ui.Theme.Rgb(1, 0.27, 0.4);
        foreach (var line in new[] { across, down })
        {
            line.Stroke = Ui.Theme.Brush(Ui.Theme.WithAlpha(accent, 0.75));
            line.StrokeThickness = 1;
            overlay.Children.Add(line);
        }
        box.Stroke = Ui.Theme.Brush(accent);
        box.Fill = Ui.Theme.Brush(Ui.Theme.WithAlpha(accent, 0.15));
        overlay.Children.Add(box);
        label.Foreground = Ui.Theme.Brush(Ui.Theme.Rgb(1, 1, 1));
        tag.Background = Ui.Theme.Brush(Ui.Theme.Rgb(0, 0, 0, 0.8));
        tag.Child = label;
        tag.Visibility = Visibility.Collapsed;
        overlay.Children.Add(tag);
        var hint = new Border
        {
            Child = new TextBlock { Text = "Drag to measure · Esc to close", FontSize = 13, Foreground = Ui.Theme.Brush(Ui.Theme.Rgb(1, 1, 1)) },
            Background = Ui.Theme.Brush(Ui.Theme.Rgb(0, 0, 0, 0.8)),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(12, 6, 12, 6),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, 48, 0, 0),
            IsHitTestVisible = false,
        };

        var root = new Grid { Children = { new Image { Source = image, Stretch = Microsoft.UI.Xaml.Media.Stretch.Fill }, overlay, hint } };
        root.PointerMoved += Moved;
        root.PointerPressed += Pressed;
        root.PointerReleased += Released;
        root.KeyDown += (_, e) => { if (e.Key == VirtualKey.Escape) Close(); };
        root.Loaded += (_, _) => root.Focus(FocusState.Programmatic);
        root.IsTabStop = true;
        Content = root;

        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        scale = Services.Native.GetDpiForWindow(hwnd) / 96.0;
        AppWindow.SetPresenter(AppWindowPresenterKind.FullScreen);
        AppWindow.IsShownInSwitchers = false;
        Closed += (_, _) => open = null;
    }

    private void Moved(object sender, PointerRoutedEventArgs e)
    {
        var p = e.GetCurrentPoint(overlay).Position;
        tag.Visibility = Visibility.Visible;
        across.X1 = 0; across.X2 = overlay.ActualWidth; across.Y1 = across.Y2 = Math.Round(p.Y) + 0.5;
        down.Y1 = 0; down.Y2 = overlay.ActualHeight; down.X1 = down.X2 = Math.Round(p.X) + 0.5;
        if (start is { } s)
        {
            Canvas.SetLeft(box, Math.Min(s.X, p.X));
            Canvas.SetTop(box, Math.Min(s.Y, p.Y));
            box.Width = Math.Abs(p.X - s.X);
            box.Height = Math.Abs(p.Y - s.Y);
            label.Text = $"{Px(box.Width)} × {Px(box.Height)} px";
        }
        else label.Text = $"{Px(p.X)}, {Px(p.Y)}";
        tag.Measure(new Windows.Foundation.Size(double.PositiveInfinity, double.PositiveInfinity));
        var x = p.X + 14 + tag.DesiredSize.Width > overlay.ActualWidth ? p.X - tag.DesiredSize.Width - 14 : p.X + 14;
        Canvas.SetLeft(tag, x);
        Canvas.SetTop(tag, p.Y + 16);
    }

    private int Px(double dips) => (int)Math.Round(dips * scale);

    private void Pressed(object sender, PointerRoutedEventArgs e)
    {
        var point = e.GetCurrentPoint(overlay);
        if (point.Properties.IsRightButtonPressed) { Close(); return; }
        start = point.Position;
        box.Width = box.Height = 0;
        box.Visibility = Visibility.Visible;
    }

    private void Released(object sender, PointerRoutedEventArgs e)
    {
        if (start is null) return;
        start = null;
        if (box.Width < 2 && box.Height < 2) { box.Visibility = Visibility.Collapsed; return; }
        var size = $"{Px(box.Width)} × {Px(box.Height)}";
        var package = new DataPackage();
        package.SetText(size);
        Clipboard.SetContent(package);
        Measured?.Invoke(size + " px");
    }

    // The main screen, as BGRA pixels, through GDI.
    private static (int W, int H, byte[] Pixels) Capture()
    {
        int w = GetSystemMetrics(0), h = GetSystemMetrics(1);
        var screen = GetDC(0);
        var memory = CreateCompatibleDC(screen);
        var bitmap = CreateCompatibleBitmap(screen, w, h);
        var old = SelectObject(memory, bitmap);
        BitBlt(memory, 0, 0, w, h, screen, 0, 0, 0x00CC0020);
        SelectObject(memory, old);
        var info = new BitmapInfo { Size = 40, Width = w, Height = -h, Planes = 1, BitCount = 32 };
        var pixels = new byte[w * h * 4];
        GetDIBits(memory, bitmap, 0, (uint)h, pixels, ref info, 0);
        for (var i = 3; i < pixels.Length; i += 4) pixels[i] = 255;
        DeleteObject(bitmap);
        DeleteDC(memory);
        ReleaseDC(0, screen);
        return (w, h, pixels);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfo
    {
        public uint Size;
        public int Width, Height;
        public ushort Planes, BitCount;
        public uint Compression, SizeImage;
        public int XPelsPerMeter, YPelsPerMeter;
        public uint ClrUsed, ClrImportant;
        public uint Colors;
    }

    [LibraryImport("user32.dll")] private static partial int GetSystemMetrics(int index);
    [LibraryImport("user32.dll")] private static partial nint GetDC(nint hwnd);
    [LibraryImport("user32.dll")] private static partial int ReleaseDC(nint hwnd, nint dc);
    [LibraryImport("gdi32.dll")] private static partial nint CreateCompatibleDC(nint dc);
    [LibraryImport("gdi32.dll")] private static partial nint CreateCompatibleBitmap(nint dc, int w, int h);
    [LibraryImport("gdi32.dll")] private static partial nint SelectObject(nint dc, nint obj);
    [LibraryImport("gdi32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool BitBlt(nint dest, int x, int y, int w, int h, nint src, int sx, int sy, uint rop);
    [LibraryImport("gdi32.dll")] private static partial int GetDIBits(nint dc, nint bitmap, uint start, uint lines, [Out] byte[] bits, ref BitmapInfo info, uint usage);
    [LibraryImport("gdi32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool DeleteObject(nint obj);
    [LibraryImport("gdi32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool DeleteDC(nint dc);
}
