namespace Beanotch.Services;

public sealed record FocusPreset(int Work, int Rest)
{
    public string Label => $"{Work}/{Rest}";
    public static readonly FocusPreset[] All = [new(25, 5), new(50, 10), new(15, 3)];
}

// Pomodoro: work, then a break, then work again, counted from the wall clock so it survives sleep.
public sealed class FocusTimer
{
    public FocusPreset Preset { get; private set; } = FocusPreset.All[0];
    public bool Running { get; private set; }
    public bool OnBreak { get; private set; }
    public int Rounds { get; private set; }
    private DateTimeOffset endsAt;
    private TimeSpan left;

    public event Action<string>? Finished;

    public FocusTimer() => left = TimeSpan.FromMinutes(Preset.Work);

    public TimeSpan Total => TimeSpan.FromMinutes(OnBreak ? Preset.Rest : Preset.Work);

    public TimeSpan Left => Running ? Max(endsAt - DateTimeOffset.Now) : left;

    public double Progress => 1 - Left / Total;

    public void Choose(FocusPreset preset)
    {
        Preset = preset;
        Reset();
    }

    public void Toggle()
    {
        if (Running) { left = Left; Running = false; }
        else { endsAt = DateTimeOffset.Now + left; Running = true; }
    }

    public void Reset()
    {
        Running = false;
        OnBreak = false;
        left = TimeSpan.FromMinutes(Preset.Work);
    }

    public void Skip()
    {
        OnBreak = !OnBreak;
        left = Total;
        if (Running) endsAt = DateTimeOffset.Now + left;
    }

    // Called on each tick: moves from work to break and back when a stretch runs out.
    public void Tick()
    {
        if (!Running || Left > TimeSpan.Zero) return;
        if (!OnBreak) Rounds++;
        Finished?.Invoke(OnBreak ? "Break's over" : "Time for a break");
        OnBreak = !OnBreak;
        left = Total;
        endsAt = DateTimeOffset.Now + left;
    }

    private static TimeSpan Max(TimeSpan t) => t < TimeSpan.Zero ? TimeSpan.Zero : t;
}

public sealed class CountdownTimer
{
    public static readonly int[] Presets = [1, 3, 5, 10, 15, 30, 60];
    public TimeSpan Length { get; private set; } = TimeSpan.FromMinutes(5);
    public bool Running { get; private set; }
    private DateTimeOffset endsAt;
    private TimeSpan left = TimeSpan.FromMinutes(5);

    public event Action? Finished;

    public TimeSpan Left => Running ? (endsAt - DateTimeOffset.Now is var t && t > TimeSpan.Zero ? t : TimeSpan.Zero) : left;

    public void Set(int minutes)
    {
        Length = TimeSpan.FromMinutes(minutes);
        left = Length;
        Running = false;
    }

    public void Toggle()
    {
        if (Running) { left = Left; Running = false; }
        else
        {
            if (left <= TimeSpan.Zero) left = Length;
            endsAt = DateTimeOffset.Now + left;
            Running = true;
        }
    }

    public void Tick()
    {
        if (!Running || Left > TimeSpan.Zero) return;
        Running = false;
        left = TimeSpan.Zero;
        Finished?.Invoke();
    }
}

public sealed class TaskItem
{
    public string Title { get; set; } = "";
    public bool Done { get; set; }
    // A time today (or later) to be reminded at, in the closed island.
    public DateTimeOffset? Remind { get; set; }
    public bool Reminded { get; set; }
}
