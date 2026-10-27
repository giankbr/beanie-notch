using System.Globalization;
using Beanotch.Core;
using Beanotch.Ui;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using static Beanotch.Ui.Ui;

namespace Beanotch.Pages;

// AI usage: Claude Code's tokens and what they would cost on the API, from its local logs; other tools are detected.
public sealed class AiPage(Model model) : PanelPage(model)
{
    private readonly Grid strip = new();
    private readonly Grid chart = new() { ColumnSpacing = S(6) };
    private readonly StackPanel models = V(4);
    private readonly StackPanel others = V(6);
    private UsageSummary usage = UsageSummary.Empty;
    private DateTime readAt;
    private bool reading;

    protected override FrameworkElement Build()
    {
        var claude = Card(V(8,
            V(2, Text("Claude Code", 13, weight: FontWeights.SemiBold),
                 Text("From .claude logs · what the tokens would cost on the API", 9, Theme.Faint)),
            Columns(16, (chart, null), (models, 1))), 12, 12);
        var tools = Card(V(8, Text("Other tools", 13, weight: FontWeights.SemiBold), others), 12, 12);
        tools.Width = S(210);
        return Scroll(V(10, Card(strip, 0, 12), Columns(10, (claude, 1), (tools, null))));
    }

    public override void Refresh()
    {
        Draw();
        if (reading || DateTime.UtcNow - readAt < TimeSpan.FromSeconds(20)) return;
        reading = true;
        _ = Task.Run(() => ClaudeUsage.Read(ClaudeUsage.DefaultRoot, DateTimeOffset.Now)).ContinueWith(task =>
        {
            Dispatch(() =>
            {
                reading = false;
                readAt = DateTime.UtcNow;
                if (task.IsCompletedSuccessfully) usage = task.Result;
                Draw();
            });
        }, TaskScheduler.Default);
    }

    private void Draw()
    {
        var u = usage;
        strip.Children.Clear();
        strip.ColumnDefinitions.Clear();
        var cells = new (string, string, string, Windows.UI.Color)[]
        {
            ("Today", Money(u.CostToday), $"{Tokens(u.TokensToday)} tokens · API rates", Theme.Accent),
            ("Last 5 hours", Tokens(u.TokensLast5Hours), $"{u.RequestsLast5Hours} requests", Theme.Accent2),
            ("This week", Money(u.CostWeek), $"{Tokens(u.TokensWeek)} tokens", Theme.Amber),
            ("Requests today", $"{u.RequestsToday}", "Claude Code", Theme.Good),
        };
        for (var i = 0; i < cells.Length; i++)
        {
            strip.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var (label, value, caption, dot) = cells[i];
            var cell = Stat(label, value, caption, dot);
            cell.Padding = new Thickness(S(12), S(9), S(12), S(9));
            var border = new Border { Child = cell, BorderBrush = Theme.Brush(Theme.Stroke), BorderThickness = new Thickness(i == 0 ? 0 : 1, 0, 0, 0) };
            Grid.SetColumn(border, i);
            strip.Children.Add(border);
        }

        chart.Children.Clear();
        chart.ColumnDefinitions.Clear();
        var max = Math.Max(u.DailyCost.DefaultIfEmpty(0).Max(), 0.01);
        for (var i = 0; i < u.DailyCost.Count; i++)
        {
            var today = i == u.DailyCost.Count - 1;
            var height = Math.Max(S(4), S(64) * u.DailyCost[i] / max);
            var bar = new Border
            {
                Width = S(14),
                Height = height,
                CornerRadius = new CornerRadius(S(3), S(3), S(1), S(1)),
                Background = Theme.Brush(today ? Theme.Accent : Theme.WithAlpha(Theme.Accent, 0.35)),
                VerticalAlignment = VerticalAlignment.Bottom,
            };
            ToolTipService.SetToolTip(bar, Money(u.DailyCost[i]));
            var day = DateTime.Now.Date.AddDays(i - 6).ToString("ddd", CultureInfo.InvariantCulture)[..1];
            var label = Text(day, 8, today ? Theme.Ink : Theme.Faint, FontWeights.SemiBold);
            label.HorizontalAlignment = HorizontalAlignment.Center;
            var column = Rows(4, (new Grid { Height = S(64), Children = { bar } }, null), (label, null));
            chart.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            Grid.SetColumn(column, i);
            chart.Children.Add(column);
        }

        models.Children.Clear();
        if (u.ModelsToday.Count == 0) models.Children.Add(Text(readAt == default ? "Reading logs…" : "No Claude Code use today", 10, Theme.Faint));
        foreach (var m in u.ModelsToday.Take(4))
            models.Children.Add(Columns(10, (Text(m.Model, 11, weight: FontWeights.SemiBold), 1), (Text(Tokens(m.Tokens), 9.5, Theme.Faint, mono: true), null),
                                        (Text(Money(m.Cost), 10.5, weight: FontWeights.SemiBold, mono: true), null)));

        others.Children.Clear();
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        Tool("Codex", Directory.Exists(Path.Combine(home, ".codex")), "Found");
        Tool("Cursor", Directory.Exists(Path.Combine(roaming, "Cursor")), "Usage kept online");
        Tool("Antigravity", Directory.Exists(Path.Combine(local, "Programs", "Antigravity")) || Directory.Exists(Path.Combine(roaming, "Antigravity")), "Found");
        Tool("Gemini CLI", Directory.Exists(Path.Combine(home, ".gemini")), "Found");
    }

    private void Tool(string name, bool found, string detail) =>
        others.Children.Add(Columns(8, (Text(name, 11, weight: FontWeights.SemiBold), 1), (Text(found ? detail : "Not found", 9, Theme.Faint, mono: true), null)));

    private static string Money(double v) => v >= 100 ? v.ToString("$0", CultureInfo.InvariantCulture) : v.ToString("$0.00", CultureInfo.InvariantCulture);

    private static string Tokens(long count) => count switch
    {
        >= 1_000_000_000 => (count / 1e9).ToString("0.0#", CultureInfo.InvariantCulture) + "B",
        >= 1_000_000 => (count / 1e6).ToString("0.#", CultureInfo.InvariantCulture) + "M",
        >= 1_000 => (count / 1e3).ToString("0", CultureInfo.InvariantCulture) + "K",
        _ => count.ToString(CultureInfo.InvariantCulture),
    };
}
