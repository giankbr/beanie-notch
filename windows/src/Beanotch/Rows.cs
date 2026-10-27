namespace Beanotch;

public sealed record PrayerRow(string Name, string Time, double Opacity, bool IsNext);

public sealed record ModelRow(string Model, string Tokens, string Cost);
