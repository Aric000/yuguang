namespace Yuguang.Core;

/// <summary>A frozen reading viewport; positive distances move down the newest-first list.</summary>
public sealed class CompactHistory
{
    private LiveEntry[] snapshot = [];
    public double Position { get; private set; }
    public int Offset => (int)(Position / 32);
    public double Remainder => Position % 32;
    public bool IsReading => Position > 0;
    public IReadOnlyList<LiveEntry> VisibleEntries(IReadOnlyList<LiveEntry> live) => IsReading ? snapshot.Skip(Offset).ToArray() : live;
    public int UnreadCount(IReadOnlyList<LiveEntry> live) => IsReading ? live.Select(entry => entry.Id).Except(snapshot.Select(entry => entry.Id), StringComparer.Ordinal).Count() : 0;
    public void Move(int steps, IReadOnlyList<LiveEntry> live) => Scroll(Math.Clamp(steps, -500, 500) * 32.0, live);
    /// <summary>Preserves fractional points for continuous scrolling and clamps to the viewport.</summary>
    public void Scroll(double distance, IReadOnlyList<LiveEntry> live, int visibleRows = 1)
    {
        if (!double.IsFinite(distance)) return;
        int rows = Math.Max(1, visibleRows);
        if (!IsReading)
        {
            if (distance <= 0 || live.Count <= rows) return;
            snapshot = live.ToArray();
        }
        Position = Math.Clamp(Position + distance, 0, Math.Max(0, snapshot.Length - rows) * 32.0);
        if (Position == 0) Reset();
    }
    public void Reset() { Position = 0; snapshot = []; }
}
