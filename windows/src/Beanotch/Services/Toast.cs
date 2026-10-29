using Microsoft.UI.Dispatching;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

namespace Beanotch.Services;

// Windows notifications, for a new version that's out, with an Update button that comes back here while the
// island runs.
public static class Toast
{
    private static bool registered;
    public static Action<string>? Invoked;

    public static void Register(DispatcherQueue ui)
    {
        try
        {
            AppNotificationManager.Default.NotificationInvoked += (_, e) =>
            {
                if (e.Arguments.TryGetValue("action", out var action)) ui.TryEnqueue(() => Invoked?.Invoke(action));
            };
            AppNotificationManager.Default.Register();
            registered = true;
        }
        catch (Exception e) { App.Log(e); }
    }

    public static void Show(string title, string body, string button, string action)
    {
        if (!registered) return;
        try
        {
            var note = new AppNotificationBuilder()
                .AddArgument("action", action)
                .AddText(title)
                .AddText(body)
                .AddButton(new AppNotificationButton(button).AddArgument("action", action))
                .BuildNotification();
            AppNotificationManager.Default.Show(note);
        }
        catch (Exception e) { App.Log(e); }
    }
}
