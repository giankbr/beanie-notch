using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI;
using static Beanotch.Ui.Ui;

namespace Beanotch.Island;

// The coffee bean that lives in the idle island, drawn pixel by pixel as on the Mac and redrawn eight times a second
// while it shows: it naps, sweats, eats and dances by the model's mood.
public sealed class PetView
{
    private static readonly string[] Shape =
    [
        "....####....",
        "..########..",
        ".##########.",
        ".##########.",
        "############",
        "############",
        "############",
        ".#######-##.",
        "..#####-##..",
        "....##-#....",
    ];
    private static readonly Color Body = Ui.Theme.Rgb(0.62, 0.4, 0.26), Shade = Ui.Theme.Rgb(0.36, 0.22, 0.14);
    private static readonly Color Eye = Ui.Theme.Rgb(1, 1, 1), Blush = Ui.Theme.Rgb(1, 0.5, 0.55, 0.55), Water = Ui.Theme.Rgb(0.4, 0.75, 1);
    private const double Pixel = 1.9;

    private readonly Canvas canvas = new() { Width = S(18 * Pixel), Height = S(14 * Pixel), IsHitTestVisible = false };
    private readonly DispatcherQueueTimer timer;
    private readonly Func<Model.PetMood> mood;
    private int frame;

    public FrameworkElement View => canvas;

    public PetView(Func<Model.PetMood> mood)
    {
        this.mood = mood;
        timer = DispatcherQueue.GetForCurrentThread().CreateTimer();
        timer.Interval = TimeSpan.FromMilliseconds(125);
        timer.Tick += (_, _) => { frame++; Draw(); };
    }

    public void Show(bool on)
    {
        canvas.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
        if (on && !timer.IsRunning) { Draw(); timer.Start(); }
        if (!on) timer.Stop();
    }

    private void Draw()
    {
        canvas.Children.Clear();
        var m = mood();
        double dx = 0, dy = m switch
        {
            Model.PetMood.Dancing => frame % 4 < 2 ? 1 : 3,
            Model.PetMood.Sleepy => frame % 32 < 16 ? 2 : 2.5,
            _ => frame % 24 < 12 ? 2 : 2.3,
        };
        if (m == Model.PetMood.Panic) dx = frame % 2 == 0 ? -0.5 : 0.5;
        void Dot(double x, double y, Color color, double w = 1, double h = 1)
        {
            var r = new Rectangle { Width = S(w * Pixel) + 0.3, Height = S(h * Pixel) + 0.3, Fill = Ui.Theme.Brush(color) };
            Canvas.SetLeft(r, S((x + 3 + dx) * Pixel));
            Canvas.SetTop(r, S((y + dy) * Pixel));
            canvas.Children.Add(r);
        }
        for (var y = 0; y < Shape.Length; y++)
            for (var x = 0; x < Shape[y].Length; x++)
                if (Shape[y][x] != '.') Dot(x, y, Shape[y][x] == '-' ? Shade : Body);
        Dot(2, 2, Ui.Theme.Rgb(1, 1, 1, 0.35));
        switch (m)
        {
            case Model.PetMood.Sleepy:
                Dot(2.5, 4.5, Eye, 2, 0.5); Dot(7.5, 4.5, Eye, 2, 0.5);
                Dot(14.5, 3 - frame % 24 / 8.0, Ui.Theme.Rgb(1, 1, 1, 0.8), 1.5, 0.5);
                break;
            case Model.PetMood.Panic:
                Dot(3, 3.5, Eye, 1, 2); Dot(8, 3.5, Eye, 1, 2);
                Dot(4.5, 7, Shade, 2);
                Dot(12, 1 + frame % 6 / 3.0, Water, 1, 1.5);
                break;
            case Model.PetMood.Eating:
                Dot(3, 4, Eye, 1, 1.5); Dot(8, 4, Eye, 1, 1.5);
                Dot(4.5, 6.5, Shade, 2.5, frame % 4 < 2 ? 1.5 : 0.5);
                if (frame % 4 < 2) Dot(-1, 7, Ui.Theme.Rgb(1, 1, 1, 0.7), 0.7, 0.7);
                break;
            default:
                Dot(1.5, 5.5, Blush, 1.5); Dot(9, 5.5, Blush, 1.5);
                if (frame % 40 == 0) { Dot(3, 4.5, Eye, 1, 0.5); Dot(8, 4.5, Eye, 1, 0.5); }
                else { Dot(3, 3.5, Eye, 1, 2); Dot(8, 3.5, Eye, 1, 2); }
                Dot(4.5, 6.5, Shade, 2, 0.6);
                if (m == Model.PetMood.Dancing) Dot(14.5, 6 - frame % 16 / 4.0, Ui.Theme.Rgb(1, 1, 1, 0.85), 1, 2);
                break;
        }
    }
}
