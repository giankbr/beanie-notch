using Microsoft.UI.Xaml;

namespace Beanotch.Pages;

// A page builds its elements once and then updates them in place: Refresh when its data changes or it comes into
// view, Tick a couple of times a second for clocks and progress.
public abstract class PanelPage(Model model)
{
    private FrameworkElement? view;

    protected Model Model { get; } = model;

    // Set by the shell: rebuilds the panel after a theme or accent change.
    public Action Rebuild { get; set; } = () => { };

    public FrameworkElement View => view ??= Build();

    protected abstract FrameworkElement Build();

    public virtual void Refresh() { }

    public virtual void Tick() { }
}
