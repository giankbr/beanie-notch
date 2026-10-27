using Windows.Media.Core;
using Windows.Media.Playback;

namespace Beanotch.Services;

public enum AmbientSound { Rain, Waves, Brown, White }

// Background sound for focusing, made on the fly as on the Mac: half a minute of it is written once to a WAV file
// (it loops without a seam) and played on repeat, so nothing is added to the download.
public sealed class Ambient
{
    private MediaPlayer? player;
    public AmbientSound? Playing { get; private set; }

    public static string Title(AmbientSound s) => s switch
    {
        AmbientSound.Brown => "Brown noise", AmbientSound.White => "White noise", _ => s.ToString(),
    };

    public void Play(AmbientSound sound)
    {
        if (Playing == sound) return;
        Stop();
        try
        {
            var path = Path.Combine(Path.GetTempPath(), "Beanotch", $"ambient-{sound.ToString().ToLowerInvariant()}.wav");
            if (!File.Exists(path)) Write(sound, path);
            player = new MediaPlayer { IsLoopingEnabled = true, Volume = 0.5, Source = MediaSource.CreateFromUri(new Uri(path)) };
            player.Play();
            Playing = sound;
        }
        catch (Exception) { Stop(); }
    }

    public void Stop()
    {
        player?.Pause();
        player?.Dispose();
        player = null;
        Playing = null;
    }

    // Three swells of the waves long, and the end blended into the start so the loop doesn't click.
    private static void Write(AmbientSound sound, string path)
    {
        const int rate = 22050, seconds = 25, fade = rate;
        var total = rate * seconds;
        var generator = new Generator(sound, rate);
        var samples = new float[total + fade];
        for (var i = 0; i < samples.Length; i++) samples[i] = generator.Next();
        for (var i = 0; i < fade; i++)
        {
            var t = (float)i / fade;
            samples[i] = samples[i] * t + samples[total + i] * (1 - t);
        }
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        using var file = new BinaryWriter(File.Create(path));
        file.Write("RIFF"u8); file.Write(36 + total * 2); file.Write("WAVE"u8);
        file.Write("fmt "u8); file.Write(16); file.Write((short)1); file.Write((short)1); file.Write(rate); file.Write(rate * 2);
        file.Write((short)2); file.Write((short)16);
        file.Write("data"u8); file.Write(total * 2);
        for (var i = 0; i < total; i++) file.Write((short)Math.Clamp(samples[i] * 0.5f * short.MaxValue, short.MinValue, short.MaxValue));
    }

    private sealed class Generator(AmbientSound sound, double rate)
    {
        private ulong seed = 0x9E3779B97F4A7C15;
        private float b0, b1, b2, b3, b4, b5, b6, brown, drop, dropTone, dropPhase, low;
        private double t;

        private float White()
        {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17;
            return (float)(seed % 2_000_001) / 1_000_000 - 1;
        }

        private float Pink()
        {
            var w = White();
            b0 = 0.99886f * b0 + w * 0.0555179f; b1 = 0.99332f * b1 + w * 0.0750759f;
            b2 = 0.96900f * b2 + w * 0.1538520f; b3 = 0.86650f * b3 + w * 0.3104856f;
            b4 = 0.55000f * b4 + w * 0.5329522f; b5 = -0.7616f * b5 - w * 0.0168980f;
            var p = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362f;
            b6 = w * 0.115926f;
            return p * 0.11f;
        }

        private float Brown()
        {
            brown = (brown + 0.02f * White()) / 1.02f;
            return brown * 3.5f;
        }

        public float Next()
        {
            t += 1 / rate;
            switch (sound)
            {
                case AmbientSound.White: return White() * 0.25f;
                case AmbientSound.Brown: return Brown();
                case AmbientSound.Waves:
                    var swell = (float)(0.5 + 0.5 * Math.Sin(2 * Math.PI * t / (25.0 / 3)));
                    low += 0.04f * (Pink() - low);
                    return Brown() * (0.25f + 0.75f * swell * swell) + low * 0.6f * swell;
                default:
                    if (White() > 0.9993f)
                    {
                        drop = 0.25f + 0.35f * Math.Abs(White());
                        dropTone = 0.15f + 0.25f * Math.Abs(White());
                    }
                    dropPhase += dropTone;
                    var tick = drop * MathF.Sin(dropPhase);
                    drop *= 0.9965f;
                    var hiss = Pink() - low;
                    low += 0.02f * (hiss - low);
                    return hiss * 0.55f + tick * 0.35f + Brown() * 0.25f;
            }
        }
    }
}
