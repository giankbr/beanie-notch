using Beanotch.Core;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Media.Control;
using Windows.Storage.Streams;

namespace Beanotch.Services;

// Whatever Windows shows in its media flyout (Spotify, browsers, the Media Player app), through the system media
// transport controls, plus synced lyrics for it.
public sealed class MediaWatcher
{
    private readonly DispatcherQueue ui;
    private readonly Lyrics lyrics = new(new HttpClient { Timeout = TimeSpan.FromSeconds(10) });
    private GlobalSystemMediaTransportControlsSessionManager? manager;
    private GlobalSystemMediaTransportControlsSession? session;
    private TimeSpan basePosition;
    private DateTimeOffset baseTime;

    public string Title { get; private set; } = "";
    public string Artist { get; private set; } = "";
    // "Spotify", "Chrome": the player, from its app id.
    public string Source { get; private set; } = "";
    public bool Playing { get; private set; }
    public TimeSpan Duration { get; private set; }
    public BitmapImage? Art { get; private set; }
    public IReadOnlyList<LyricLine> Lines { get; private set; } = [];
    public bool HasTrack => Title.Length > 0;

    public event Action? Changed;

    public MediaWatcher(DispatcherQueue ui) => this.ui = ui;

    // Timelines are stamped when the player last reported; in between, playing time moves on with the clock.
    public TimeSpan Position
    {
        get
        {
            var position = basePosition;
            if (Playing && baseTime.Year > 2000) position += DateTimeOffset.Now - baseTime;
            return Duration > TimeSpan.Zero && position > Duration ? Duration : position;
        }
    }

    public LyricLine? CurrentLine => Lyrics.At(Lines, Position);

    public async Task StartAsync()
    {
        try
        {
            manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
            manager.CurrentSessionChanged += (_, _) => ui.TryEnqueue(Attach);
            Attach();
        }
        catch (Exception) { }
    }

    private void Attach()
    {
        if (session is not null)
        {
            session.MediaPropertiesChanged -= OnSessionChanged;
            session.PlaybackInfoChanged -= OnSessionChanged;
            session.TimelinePropertiesChanged -= OnSessionChanged;
        }
        session = manager?.GetCurrentSession();
        if (session is not null)
        {
            session.MediaPropertiesChanged += OnSessionChanged;
            session.PlaybackInfoChanged += OnSessionChanged;
            session.TimelinePropertiesChanged += OnSessionChanged;
        }
        _ = RefreshAsync();
    }

    private void OnSessionChanged(GlobalSystemMediaTransportControlsSession sender, object args) => ui.TryEnqueue(() => _ = RefreshAsync());

    private async Task RefreshAsync()
    {
        if (session is null)
        {
            Title = Artist = "";
            Playing = false;
            Art = null;
            Lines = [];
            Changed?.Invoke();
            return;
        }
        try
        {
            var props = await session.TryGetMediaPropertiesAsync();
            var info = session.GetPlaybackInfo();
            var timeline = session.GetTimelineProperties();
            Playing = info.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing;
            Duration = timeline.EndTime - timeline.StartTime;
            basePosition = timeline.Position;
            baseTime = timeline.LastUpdatedTime;
            Source = AppName(session.SourceAppUserModelId);
            var title = props.Title ?? "";
            var artist = props.Artist ?? "";
            if (title != Title || artist != Artist)
            {
                Title = title;
                Artist = artist;
                Lines = [];
                Art = await LoadArtAsync(props.Thumbnail);
                _ = LoadLyricsAsync(title, artist, Duration);
            }
        }
        // A session can close while it is being read.
        catch (Exception) { }
        Changed?.Invoke();
    }

    private async Task LoadLyricsAsync(string title, string artist, TimeSpan duration)
    {
        if (title.Length == 0) return;
        var lines = await lyrics.FetchAsync(title, artist, duration);
        ui.TryEnqueue(() =>
        {
            if (title != Title || artist != Artist) return;
            Lines = lines;
            Changed?.Invoke();
        });
    }

    private static async Task<BitmapImage?> LoadArtAsync(IRandomAccessStreamReference? thumbnail)
    {
        if (thumbnail is null) return null;
        try
        {
            using var stream = await thumbnail.OpenReadAsync();
            var image = new BitmapImage();
            await image.SetSourceAsync(stream);
            return image;
        }
        catch (Exception) { return null; }
    }

    private static string AppName(string id)
    {
        var name = id.Split('!')[0].Split('\\').Last();
        if (name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) name = name[..^4];
        name = name.Split('_')[0].Split('.').Last();
        return name.Length == 0 ? "" : char.ToUpperInvariant(name[0]) + name[1..];
    }

    public void TogglePlay() => _ = session?.TryTogglePlayPauseAsync();
    public void Next() => _ = session?.TrySkipNextAsync();
    public void Previous() => _ = session?.TrySkipPreviousAsync();
}
