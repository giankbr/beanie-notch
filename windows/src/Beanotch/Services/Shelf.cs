using System.Collections.ObjectModel;

namespace Beanotch.Services;

// Files kept at hand: dropped on the island, or screenshots as they're taken. Only the paths are remembered.
public sealed class Shelf
{
    private readonly AppSettings settings;

    public ObservableCollection<string> Items { get; } = [];
    public bool Grid { get; set; } = true;

    public Shelf(AppSettings settings)
    {
        this.settings = settings;
        foreach (var path in settings.Shelf.Where(File.Exists)) Items.Add(path);
    }

    public void Add(IEnumerable<string> paths)
    {
        foreach (var path in paths)
            if (!Items.Contains(path)) Items.Add(path);
        Save();
    }

    public void Remove(string path)
    {
        Items.Remove(path);
        Save();
    }

    public void Clear()
    {
        Items.Clear();
        Save();
    }

    private void Save()
    {
        settings.Shelf = [.. Items];
        settings.Save();
    }
}
