using System.Runtime.InteropServices;
using System.Runtime.InteropServices.Marshalling;

namespace Beanotch.Services;

// The default speaker's and microphone's level and mute, through Core Audio. The COM interfaces are source-generated
// so they survive trimming; only the methods up to the ones used are declared, in vtable order.
public static partial class Audio
{
    private enum Flow { Render = 0, Capture = 1 }

    [GeneratedComInterface]
    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
    internal partial interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, uint stateMask, out nint devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
    }

    [GeneratedComInterface]
    [Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    internal partial interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid iid, uint clsCtx, nint activationParams, out IAudioEndpointVolume endpoint);
    }

    [GeneratedComInterface]
    [Guid("5CDF2C82-841E-4546-9722-0CF74078229A")]
    internal partial interface IAudioEndpointVolume
    {
        [PreserveSig] int RegisterControlChangeNotify(nint notify);
        [PreserveSig] int UnregisterControlChangeNotify(nint notify);
        [PreserveSig] int GetChannelCount(out uint count);
        [PreserveSig] int SetMasterVolumeLevel(float levelDb, ref Guid context);
        [PreserveSig] int SetMasterVolumeLevelScalar(float level, ref Guid context);
        [PreserveSig] int GetMasterVolumeLevel(out float levelDb);
        [PreserveSig] int GetMasterVolumeLevelScalar(out float level);
        [PreserveSig] int SetChannelVolumeLevel(uint channel, float levelDb, ref Guid context);
        [PreserveSig] int SetChannelVolumeLevelScalar(uint channel, float level, ref Guid context);
        [PreserveSig] int GetChannelVolumeLevel(uint channel, out float levelDb);
        [PreserveSig] int GetChannelVolumeLevelScalar(uint channel, out float level);
        [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid context);
        [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
    }

    [LibraryImport("ole32.dll")]
    private static partial int CoCreateInstance(ref Guid clsid, nint outer, uint context, ref Guid iid, out nint instance);

    private static readonly StrategyBasedComWrappers Wrappers = new();

    private static readonly Dictionary<Flow, (IAudioEndpointVolume Endpoint, DateTime At)> Cache = [];

    // Re-resolved every few seconds, so plugging in headphones moves to the new default device.
    private static IAudioEndpointVolume? Endpoint(Flow flow)
    {
        if (Cache.TryGetValue(flow, out var cached) && DateTime.UtcNow - cached.At < TimeSpan.FromSeconds(3)) return cached.Endpoint;
        var endpoint = Resolve(flow);
        if (endpoint is not null) Cache[flow] = (endpoint, DateTime.UtcNow);
        return endpoint;
    }

    private static IAudioEndpointVolume? Resolve(Flow flow)
    {
        var clsid = new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E");
        var iid = typeof(IMMDeviceEnumerator).GUID;
        if (CoCreateInstance(ref clsid, 0, 1 /* CLSCTX_INPROC_SERVER */, ref iid, out var pointer) != 0 || pointer == 0) return null;
        try
        {
            var enumerator = (IMMDeviceEnumerator)Wrappers.GetOrCreateObjectForComInstance(pointer, CreateObjectFlags.None);
            // Role 1: eMultimedia.
            if (enumerator.GetDefaultAudioEndpoint((int)flow, 1, out var device) != 0) return null;
            var volumeIid = typeof(IAudioEndpointVolume).GUID;
            return device.Activate(ref volumeIid, 23 /* CLSCTX_ALL */, 0, out var endpoint) == 0 ? endpoint : null;
        }
        catch (Exception) { return null; }
        finally { Marshal.Release(pointer); }
    }

    public static (double Level, bool Muted)? Speaker() => Read(Flow.Render);

    public static bool? MicrophoneMuted() => Read(Flow.Capture)?.Muted;

    public static void SetSpeaker(double level)
    {
        var endpoint = Endpoint(Flow.Render);
        var context = Guid.Empty;
        endpoint?.SetMasterVolumeLevelScalar((float)Math.Clamp(level, 0, 1), ref context);
    }

    public static void SetMicrophoneMuted(bool muted)
    {
        var endpoint = Endpoint(Flow.Capture);
        var context = Guid.Empty;
        endpoint?.SetMute(muted, ref context);
    }

    private static (double Level, bool Muted)? Read(Flow flow)
    {
        var endpoint = Endpoint(flow);
        if (endpoint is null) return null;
        try
        {
            endpoint.GetMasterVolumeLevelScalar(out var level);
            endpoint.GetMute(out var muted);
            return (level, muted);
        }
        catch (Exception) { return null; }
    }
}
