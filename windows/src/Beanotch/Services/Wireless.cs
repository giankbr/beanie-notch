using System.Runtime.InteropServices;
using System.Runtime.InteropServices.Marshalling;
using Windows.Devices.Bluetooth;
using Windows.Devices.Enumeration;
using Windows.Devices.Radios;
using Windows.Devices.WiFi;
using Windows.Networking.Connectivity;
using Windows.Security.Credentials;

namespace Beanotch.Services;

public sealed record WifiNetwork(string Ssid, int Bars, bool Secured, bool Connected, WiFiAvailableNetwork Network);

public sealed record BluetoothItem(string Name, ulong Address, bool Connected, bool Audio, BluetoothMajorClass Kind);

// Wi-Fi and Bluetooth for the Controls page: each radio on or off, the networks in range to join, and the paired
// devices. Windows has no public call to connect a paired headset; audio devices reconnect through the same
// one-shot request the Sound settings use (KSPROPERTY_ONESHOT_RECONNECT on the Bluetooth audio driver).
public static partial class Wireless
{
    private static WiFiAdapter? adapter;

    public static async Task<Radio?> RadioFor(RadioKind kind)
    {
        try
        {
            if (await Radio.RequestAccessAsync() != RadioAccessStatus.Allowed) return null;
            return (await Radio.GetRadiosAsync()).FirstOrDefault(r => r.Kind == kind);
        }
        catch (Exception) { return null; }
    }

    public static async Task<bool> SetRadio(RadioKind kind, bool on)
    {
        var radio = await RadioFor(kind);
        return radio is not null && await radio.SetStateAsync(on ? RadioState.On : RadioState.Off) == RadioAccessStatus.Allowed;
    }

    // Wi-Fi

    private static async Task<WiFiAdapter?> Adapter()
    {
        if (adapter is not null) return adapter;
        try
        {
            if (await WiFiAdapter.RequestAccessAsync() != WiFiAccessStatus.Allowed) return null;
            return adapter = (await WiFiAdapter.FindAllAdaptersAsync()).FirstOrDefault();
        }
        catch (Exception) { return null; }
    }

    public static async Task<string?> ConnectedSsid()
    {
        try
        {
            var a = await Adapter();
            var profile = a is null ? null : await a.NetworkAdapter.GetConnectedProfileAsync();
            return profile?.IsWlanConnectionProfile == true ? profile.WlanConnectionProfileDetails.GetConnectedSsid() : null;
        }
        catch (Exception) { return null; }
    }

    // Networks in range, strongest first, one row per name. Windows 11 only lists them with location access on.
    public static async Task<List<WifiNetwork>> Scan()
    {
        var a = await Adapter();
        if (a is null) return [];
        try
        {
            await a.ScanAsync();
            var current = await ConnectedSsid();
            return [.. a.NetworkReport.AvailableNetworks
                .Where(n => !string.IsNullOrEmpty(n.Ssid))
                .GroupBy(n => n.Ssid)
                .Select(g => g.MaxBy(n => n.NetworkRssiInDecibelMilliwatts)!)
                .OrderByDescending(n => n.Ssid == current)
                .ThenByDescending(n => n.SignalBars)
                .Select(n => new WifiNetwork(n.Ssid, n.SignalBars,
                    n.SecuritySettings.NetworkAuthenticationType is not (NetworkAuthenticationType.Open80211 or NetworkAuthenticationType.None),
                    n.Ssid == current, n))];
        }
        catch (Exception) { return []; }
    }

    public enum Joined { Ok, NeedsPassword, Failed }

    // Without a password, Windows uses the saved profile if there is one.
    public static async Task<Joined> Join(WifiNetwork network, string? password = null)
    {
        var a = await Adapter();
        if (a is null) return Joined.Failed;
        try
        {
            var result = password is null
                ? await a.ConnectAsync(network.Network, WiFiReconnectionKind.Automatic)
                : await a.ConnectAsync(network.Network, WiFiReconnectionKind.Automatic, new PasswordCredential { Password = password });
            return result.ConnectionStatus switch
            {
                WiFiConnectionStatus.Success => Joined.Ok,
                WiFiConnectionStatus.InvalidCredential when network.Secured => Joined.NeedsPassword,
                _ when network.Secured && password is null => Joined.NeedsPassword,
                _ => Joined.Failed,
            };
        }
        catch (Exception) { return network.Secured && password is null ? Joined.NeedsPassword : Joined.Failed; }
    }

    public static async Task Leave()
    {
        try { (await Adapter())?.Disconnect(); } catch (Exception) { }
    }

    // Bluetooth

    public static async Task<List<BluetoothItem>> Paired()
    {
        var list = new List<BluetoothItem>();
        try
        {
            var audio = AudioDeviceIds();
            foreach (var info in await DeviceInformation.FindAllAsync(BluetoothDevice.GetDeviceSelectorFromPairingState(true)))
            {
                using var device = await BluetoothDevice.FromIdAsync(info.Id);
                if (device is null) continue;
                var hex = device.BluetoothAddress.ToString("X12");
                list.Add(new BluetoothItem(device.Name, device.BluetoothAddress, device.ConnectionStatus == BluetoothConnectionStatus.Connected,
                                           audio.Any(id => id.Contains(hex, StringComparison.OrdinalIgnoreCase)), device.ClassOfDevice.MajorClass));
            }
        }
        catch (Exception) { }
        return [.. list.OrderByDescending(d => d.Connected).ThenBy(d => d.Name)];
    }

    public static Task<bool> Connect(BluetoothItem device) => Task.Run(() => OneShot(device.Address, 0));

    public static Task<bool> Disconnect(BluetoothItem device) => Task.Run(() => OneShot(device.Address, 1));

    // The Bluetooth audio driver's property set: 0 reconnects, 1 disconnects.
    private static readonly Guid BtAudio = new("7FA06C40-B8F6-4C7E-8556-E8C33A12E54D");

    [GeneratedComInterface]
    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
    internal partial interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, uint stateMask, out IMMDeviceCollection devices);
    }

    [GeneratedComInterface]
    [Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E")]
    internal partial interface IMMDeviceCollection
    {
        [PreserveSig] int GetCount(out uint count);
        [PreserveSig] int Item(uint index, out IMMDevice device);
    }

    [GeneratedComInterface]
    [Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    internal partial interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid iid, uint clsCtx, nint activationParams, out IDeviceTopology topology);
    }

    [GeneratedComInterface]
    [Guid("2A07407E-6497-4A18-9787-32F79BD0D98F")]
    internal partial interface IDeviceTopology
    {
        [PreserveSig] int GetConnectorCount(out uint count);
        [PreserveSig] int GetConnector(uint index, out IConnector connector);
    }

    [GeneratedComInterface]
    [Guid("9C2C4058-23F5-41DE-877A-DF3AF236A09E")]
    internal partial interface IConnector
    {
        [PreserveSig] int GetKind(out int type);
        [PreserveSig] int GetDataFlow(out int flow);
        [PreserveSig] int ConnectTo(nint other);
        [PreserveSig] int Disconnect();
        [PreserveSig] int IsConnected(out int connected);
        [PreserveSig] int GetConnectedTo(out IConnector other);
        [PreserveSig] int GetConnectorIdConnectedTo(out nint id);
        [PreserveSig] int GetDeviceIdConnectedTo(out nint id);
    }

    [GeneratedComInterface]
    [Guid("AE2DE0E4-5BCA-4F2D-AA46-5D13F8FDB3A9")]
    internal partial interface IPart
    {
        [PreserveSig] int GetName(out nint name);
        [PreserveSig] int GetLocalId(out uint id);
        [PreserveSig] int GetGlobalId(out nint id);
        [PreserveSig] int GetPartType(out int type);
        [PreserveSig] int GetSubType(out Guid subType);
        [PreserveSig] int GetControlInterfaceCount(out uint count);
        [PreserveSig] int GetControlInterface(uint index, out nint control);
        [PreserveSig] int EnumPartsIncoming(out nint parts);
        [PreserveSig] int EnumPartsOutgoing(out nint parts);
        [PreserveSig] int GetTopologyObject(out nint topology);
        [PreserveSig] int Activate(uint clsCtx, ref Guid iid, out IKsControl control);
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct KsProperty
    {
        public Guid Set;
        public uint Id, Flags;
    }

    [GeneratedComInterface]
    [Guid("28F54685-06FD-11D2-B27A-00A0C9223196")]
    internal partial interface IKsControl
    {
        [PreserveSig] int KsProperty(ref KsProperty property, uint propertyLength, nint data, uint dataLength, out uint returned);
    }

    [LibraryImport("ole32.dll")]
    private static partial int CoCreateInstance(ref Guid clsid, nint outer, uint context, ref Guid iid, out nint instance);

    private static readonly StrategyBasedComWrappers Wrappers = new();

    // Every speaker and headset endpoint, present or not, with the driver it hangs off: (device id, that driver's part).
    private static List<(string Id, IConnector Driver)> AudioEndpoints()
    {
        var found = new List<(string, IConnector)>();
        var clsid = new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E");
        var iid = typeof(IMMDeviceEnumerator).GUID;
        if (CoCreateInstance(ref clsid, 0, 1, ref iid, out var pointer) != 0 || pointer == 0) return found;
        try
        {
            var enumerator = (IMMDeviceEnumerator)Wrappers.GetOrCreateObjectForComInstance(pointer, CreateObjectFlags.None);
            // eAll, and every state: a headset that isn't connected has an unplugged endpoint.
            if (enumerator.EnumAudioEndpoints(2, 0xF, out var devices) != 0) return found;
            devices.GetCount(out var count);
            var topologyIid = typeof(IDeviceTopology).GUID;
            for (uint i = 0; i < count; i++)
            {
                try
                {
                    if (devices.Item(i, out var device) != 0) continue;
                    if (device.Activate(ref topologyIid, 23, 0, out var topology) != 0) continue;
                    if (topology.GetConnector(0, out var connector) != 0) continue;
                    if (connector.GetConnectedTo(out var driver) != 0) continue;
                    if (connector.GetDeviceIdConnectedTo(out var idPointer) != 0 || idPointer == 0) continue;
                    var id = Marshal.PtrToStringUni(idPointer) ?? "";
                    Marshal.FreeCoTaskMem(idPointer);
                    found.Add((id, driver));
                }
                catch (Exception) { }
            }
        }
        catch (Exception) { }
        finally { Marshal.Release(pointer); }
        return found;
    }

    private static List<string> AudioDeviceIds() => [.. AudioEndpoints().Select(e => e.Id).Where(id => id.Contains("BTHENUM", StringComparison.OrdinalIgnoreCase) || id.Contains("BTHHFENUM", StringComparison.OrdinalIgnoreCase))];

    private static bool OneShot(ulong address, uint request)
    {
        var hex = address.ToString("X12");
        var ksIid = typeof(IKsControl).GUID;
        var done = false;
        foreach (var (id, driver) in AudioEndpoints().Where(e => e.Id.Contains(hex, StringComparison.OrdinalIgnoreCase)))
        {
            try
            {
                var part = (IPart)driver;
                if (part.Activate(23, ref ksIid, out var control) != 0) continue;
                var property = new KsProperty { Set = BtAudio, Id = request, Flags = 1 /* KSPROPERTY_TYPE_GET */ };
                control.KsProperty(ref property, (uint)Marshal.SizeOf<KsProperty>(), 0, 0, out _);
                done = true;
            }
            catch (Exception) { }
        }
        return done;
    }
}
