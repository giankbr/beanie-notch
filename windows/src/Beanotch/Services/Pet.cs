using Windows.System.Power;

namespace Beanotch.Services;

// Things to wear, unlocked by level; the cap for prayer and the focus headband come on by themselves.
public enum PetAccessory { None, Scarf, Glasses, Cap, Sunglasses, Crown, Headphones, Bow, Santa }

// The island's pet, as on the Mac: it reacts to what's done to it and to the PC, gets hungry once a day, earns points
// for focus sessions, meals, petting and days kept company, and every ten points is a level that unlocks something
// to wear. Now and then, with nothing else going on, it strolls across the island and back.
public sealed class Pet(Model model)
{
    public static int LevelFor(PetAccessory a) => a switch
    {
        PetAccessory.Scarf => 2,
        PetAccessory.Glasses => 3,
        PetAccessory.Cap => 4,
        PetAccessory.Sunglasses => 5,
        PetAccessory.Crown => 6,
        PetAccessory.Headphones => 7,
        PetAccessory.Bow => 8,
        PetAccessory.Santa => 9,
        _ => 1,
    };

    private AppSettings S => model.Settings;
    private (Model.PetMood Mood, DateTimeOffset Until)? reaction;
    private readonly List<DateTimeOffset> taps = [];
    private DateTimeOffset walkUntil;
    private bool away;
    private static string Today => DateTime.Now.ToString("yyyy-MM-dd");

    public int Level => Math.Min(S.PetXp / 10 + 1, 9);
    public string Name => string.IsNullOrWhiteSpace(S.PetName) ? S.PetKind.ToString() : S.PetName.Trim();
    // 1 while it's off at the far end of the island, 0 at home; the view walks between them.
    public double Walk => DateTimeOffset.Now < walkUntil ? 1 : 0;
    public event Action<int>? LeveledUp;

    // For ten minutes after each prayer time, it wears its cap.
    public bool Praying => S.PetPrayerCap && model.PrayersToday.Any(e => e.IsPrayer && DateTimeOffset.Now - e.Time is var t && t >= TimeSpan.Zero && t < TimeSpan.FromMinutes(10));

    public Model.PetMood Mood
    {
        get
        {
            var now = DateTimeOffset.Now;
            if (reaction is { } r && now < r.Until) return r.Mood;
            var lowBattery = PowerManager.BatteryStatus != BatteryStatus.NotPresent && PowerManager.RemainingChargePercent < 20
                             && PowerManager.PowerSupplyStatus == PowerSupplyStatus.NotPresent;
            var mood = Busy ? Model.PetMood.Panic
                : lowBattery ? Model.PetMood.Tired
                : model.Focus.Running && !model.Focus.OnBreak ? Model.PetMood.Focus
                : model.Focus.Running ? Model.PetMood.Coffee
                : Native.Idle > TimeSpan.FromMinutes(3) ? Model.PetMood.Sleepy
                : model.Media.Playing ? Model.PetMood.Dancing
                : DateTime.Now.Hour >= 10 && S.PetFedDay != Today ? Model.PetMood.Hungry
                : DateTime.Now.Hour < 4 ? Model.PetMood.Late
                : Model.PetMood.Happy;
            return mood == Model.PetMood.Happy && Walk > 0 ? Model.PetMood.Walking : mood;
        }
    }

    // The processor's load over the last quarter minute: a moment's spike (opening an app, a page loading) isn't the
    // processor running hot.
    private readonly Queue<(DateTimeOffset At, double Load)> loads = [];
    private bool Busy => loads.Count >= 5 && loads.Average(l => l.Load) > 0.9;

    // Once a second or so: a point for each day kept company, the processor's load, and the odd stroll.
    public void Tick(bool islandFree)
    {
        var at = DateTimeOffset.Now;
        if (loads.Count == 0 || at - loads.Last().At >= TimeSpan.FromSeconds(2)) loads.Enqueue((at, model.Stats.Cpu));
        while (loads.Count > 0 && at - loads.Peek().At > TimeSpan.FromSeconds(16)) loads.Dequeue();
        if (!S.NotchPet) return;
        if (S.PetSeenDay != Today) { S.PetSeenDay = Today; Gain(1); }
        var now = DateTimeOffset.Now;
        // Back after five minutes away: a wave hello.
        var idle = Native.Idle;
        if (idle > TimeSpan.FromMinutes(5)) away = true;
        else if (away && idle < TimeSpan.FromSeconds(5)) { away = false; React(Model.PetMood.Wave, 2.6); }
        if (islandFree && Walk == 0 && Mood == Model.PetMood.Happy && idle < TimeSpan.FromMinutes(1) && Random.Shared.Next(180) == 0)
            walkUntil = now.AddSeconds(6);
        // Left to itself a while (you're reading, say), it now and then plays with its ball.
        else if (Mood == Model.PetMood.Happy && idle > TimeSpan.FromSeconds(15) && idle < TimeSpan.FromSeconds(150) && Random.Shared.Next(300) == 0)
            React(Model.PetMood.Ball, 5);
    }

    // A click: it hops and shows a heart, takes its meal if it was hungry, and gets dizzy from five in a row.
    public void Tap()
    {
        var now = DateTimeOffset.Now;
        taps.RemoveAll(t => now - t > TimeSpan.FromSeconds(1.5));
        taps.Add(now);
        if (taps.Count >= 5) { taps.Clear(); React(Model.PetMood.Dizzy, 3); }
        else if (taps.Count == 2 && now - taps[0] < TimeSpan.FromSeconds(0.45)) React(Model.PetMood.Spin, 0.9);
        else if (Mood == Model.PetMood.Hungry) { S.PetFedDay = Today; Gain(1); React(Model.PetMood.Eating, 3); }
        else React(Model.PetMood.Love, 1.6);
    }

    // The pointer resting on it for a moment; a point for it once an hour.
    public void Stroke()
    {
        React(Model.PetMood.Love, 2.5);
        var hour = (int)(DateTimeOffset.Now.ToUnixTimeSeconds() / 3600);
        if (S.PetStrokedHour != hour) { S.PetStrokedHour = hour; Gain(1); }
    }

    public void Sway() => React(Model.PetMood.Sway, 1.5);
    public void SongChanged() => React(Model.PetMood.Groove, 2.2);
    public void Thirst() => React(Model.PetMood.Thirsty, 60);
    public void Shake() => React(Model.PetMood.Dizzy, 3);

    // A file dropped on the island, which lands on the Shelf.
    public void Feed()
    {
        if (S.PetFedDay != Today) { S.PetFedDay = Today; Gain(1); }
        React(Model.PetMood.Eating, 4);
    }

    // What a notice means to it: a failed command makes it sad, a finished one or a finished focus session is a
    // party, a quake shakes it, a charger gives it a jolt. Anything else but the volume startles it.
    public void React(Notice n)
    {
        if (n.Key == "volume") return;
        if (n.Left.StartsWith("Failed")) React(Model.PetMood.Sad, 6);
        else if (n.Left.StartsWith("Done")) { React(Model.PetMood.Party, 4); Gain(1); }
        else if (n.Left == "Time for a break") { React(Model.PetMood.Party, 4); Gain(2); }
        else if (n.Left.StartsWith("Earthquake") || n.Left.StartsWith("Tsunami")) React(Model.PetMood.Panic, 8);
        else if (n.Left == "Charging") React(Model.PetMood.Charged, 4);
        else React(Model.PetMood.Surprised, 2.5);
    }

    private void React(Model.PetMood mood, double seconds)
    {
        if (!S.NotchPet) return;
        reaction = (mood, DateTimeOffset.Now.AddSeconds(seconds));
    }

    private void Gain(int points)
    {
        var before = Level;
        S.PetXp += points;
        S.Save();
        if (Level > before) LeveledUp?.Invoke(Level);
    }
}
