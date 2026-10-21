using System.Text.Json;

namespace Yuguang.Core;

public sealed record WindowBounds(double X, double Y, double Width, double Height)
{
    public bool IsValid => double.IsFinite(X) && double.IsFinite(Y) && double.IsFinite(Width) && double.IsFinite(Height) && Width is >= 360 and <= 2000 && Height is >= 32 and <= 1600;
    public WindowBounds Clamp(WindowBounds area) => new(Math.Clamp(X, area.X, area.X + area.Width - Math.Min(Width, area.Width)), Math.Clamp(Y, area.Y, area.Y + area.Height - Math.Min(Height, area.Height)), Math.Min(Width, area.Width), Math.Min(Height, area.Height));
    public WindowBounds Snap(WindowBounds area)
    {
        var x = X; var y = Y;
        if (Math.Abs(X - area.X) < 14) x = area.X + 8;
        if (Math.Abs(X + Width - area.X - area.Width) < 14) x = area.X + area.Width - Width - 8;
        if (Math.Abs(Y - area.Y) < 14) y = area.Y + 8;
        if (Math.Abs(Y + Height - area.Y - area.Height) < 14) y = area.Y + area.Height - Height - 8;
        return this with { X = x, Y = y };
    }
}
public sealed record UserSettings
{
    public string Theme { get; init; } = "system";
    public bool Pinned { get; init; } = true;
    public bool SimpleMode { get; init; }
    public bool ScoreOnly { get; init; }
    public bool MenuScore { get; init; } = true;
    public int Rows { get; init; } = 1;
    public uint ShortcutModifiers { get; init; } = 2;
    public uint ShortcutKey { get; init; } = 0xC0;
    public string[] Favorites { get; init; } = [];
    public string LastMatch { get; init; } = "";
    public WindowBounds? ExpandedFrame { get; init; }
    public WindowBounds? CompactFrame { get; init; }
    public UserSettings Normalize() => this with
    {
        Theme = Theme is "system" or "light" or "dark" ? Theme : "system", Rows = Math.Clamp(Rows, 1, 6),
        Favorites = (Favorites ?? []).Where(name => !string.IsNullOrWhiteSpace(name) && name.Length < 40).Distinct(StringComparer.Ordinal).Take(60).ToArray(),
        LastMatch = LastMatch is { Length: < 100 } ? LastMatch : "",
        ShortcutModifiers = (ShortcutModifiers & ~15u) == 0 && (ShortcutModifiers & 11u) != 0 ? ShortcutModifiers : 2,
        ShortcutKey = ShortcutKey is >= 8 and <= 254 ? ShortcutKey : 0xC0,
        ExpandedFrame = ExpandedFrame is { IsValid: true, Height: >= 460 } ? ExpandedFrame : null,
        CompactFrame = CompactFrame is { IsValid: true } ? CompactFrame : null
    };
    public string ShortcutLabel => string.Join(" + ", new[] { (ShortcutModifiers & 2) != 0 ? "Ctrl" : "", (ShortcutModifiers & 1) != 0 ? "Alt" : "", (ShortcutModifiers & 4) != 0 ? "Shift" : "", (ShortcutModifiers & 8) != 0 ? "Win" : "", ShortcutKey == 0xC0 ? "`" : ShortcutKey is >= 65 and <= 90 or >= 48 and <= 57 ? ((char)ShortcutKey).ToString() : ShortcutKey is >= 112 and <= 135 ? $"F{ShortcutKey - 111}" : $"Key {ShortcutKey}" }.Where(part => part.Length > 0));
}
public sealed class SettingsStore(string path)
{
    public UserSettings Load()
    {
        try { if (!File.Exists(path) || new FileInfo(path).Length > 1024 * 1024) return new(); return (JsonSerializer.Deserialize<UserSettings>(File.ReadAllText(path)) ?? new()).Normalize(); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException) { return new(); }
    }
    public void Save(UserSettings settings)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(settings.Normalize(), new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temporary, path, true);
    }
}
