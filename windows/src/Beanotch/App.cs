using Beanotch.Island;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.XamlTypeInfo;

namespace Beanotch;

// The whole UI is built in code, so the app starts here rather than from App.xaml. Without XAML there's no generated
// type info, so the app hands WinUI the controls library's own (IXamlMetadataProvider); otherwise the standard
// controls can't find their styles.
public sealed partial class App : Application, IXamlMetadataProvider
{
    private readonly XamlControlsXamlMetaDataProvider controls = new();
    private IslandWindow? window;

    private static Mutex? single;

    [STAThread]
    private static void Main()
    {
        // One island at a time: a second launch (from the Run key and a shortcut, say) just leaves.
        single = new Mutex(true, @"Local\Beanotch.Island", out var first);
        if (!first) return;
        WinRT.ComWrappersSupport.InitializeComWrappers();
        Start(_ =>
        {
            SynchronizationContext.SetSynchronizationContext(new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread()));
            new App();
        });
    }

    public App() => XamlControlsXamlMetaDataProvider.Initialize();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Resources.MergedDictionaries.Add(new XamlControlsResources());
        window = new IslandWindow();
        window.Activate();
    }

    public IXamlType GetXamlType(Type type) => controls.GetXamlType(type);
    public IXamlType GetXamlType(string fullName) => controls.GetXamlType(fullName);
    public XmlnsDefinition[] GetXmlnsDefinitions() => controls.GetXmlnsDefinitions();
}
