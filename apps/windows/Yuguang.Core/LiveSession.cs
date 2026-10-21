namespace Yuguang.Core;

public sealed class LiveState
{
    public IReadOnlyList<GameDay> Days { get; internal set; } = [];
    public string SelectedDay { get; internal set; } = "";
    public string TeamFilter { get; internal set; } = "全部球队";
    public Match? SelectedMatch { get; internal set; }
    public IReadOnlyList<LiveEntry> Entries { get; internal set; } = [];
    public IReadOnlyList<LiveEntry> FrozenEntries { get; internal set; } = [];
    public bool Following { get; internal set; } = true;
    public int Unread { get; internal set; }
    public string ScheduleError { get; internal set; } = "";
    public string MatchError { get; internal set; } = "";
    public string TextError { get; internal set; } = "";
    public string PreferencesError { get; internal set; } = "";
    public bool LoadingSchedule { get; internal set; }
    public bool LoadingLive { get; internal set; }
    public DateTimeOffset? ScoreUpdatedAt { get; internal set; }
    public DateTimeOffset? TextUpdatedAt { get; internal set; }
    public UserSettings Settings { get; internal set; } = new();
    public bool Demo { get; internal set; }
    public string LatestText => Entries.FirstOrDefault()?.Content ?? (SelectedMatch?.IsUpcoming == true ? $"等待开赛 · {SelectedMatch.Start}" : "等待文字直播");
    public string ConnectionError => MatchError.Length > 0 ? MatchError : TextError;
}
/// <summary>UI-thread-owned session; awaits preserve its caller's synchronization context.</summary>
public sealed class LiveSession(ILiveService service, UserSettings settings, Action<UserSettings>? persist = null) : IDisposable
{
    public LiveState State { get; } = new() { Settings = settings.Normalize() };
    public event Action? Changed;
    private CancellationTokenSource? liveCancellation;
    private CancellationTokenSource? scheduleCancellation;
    private readonly CancellationTokenSource lifetime = new();
    private int generation;
    private int scheduleGeneration;
    private string? liveKey;
    private DateTimeOffset lastScore = DateTimeOffset.MinValue;
    private bool disposed;
    public void Notify() => Changed?.Invoke();
    public IReadOnlyList<Match> SwitchableMatches => (State.Days.FirstOrDefault(day => day.Day == State.SelectedDay)?.Matches ?? []).OrderByDescending(match => State.Settings.Favorites.Contains(match.Home) || State.Settings.Favorites.Contains(match.Away)).ThenByDescending(match => match.IsLive).ThenBy(match => match.Time, StringComparer.Ordinal).ToArray();
    public IReadOnlyList<Match> VisibleMatches => SwitchableMatches.Where(match => State.TeamFilter == "全部球队" || match.Home == State.TeamFilter || match.Away == State.TeamFilter).ToArray();
    public void ChangeDay(string day) { if (State.Days.Any(item => item.Day == day)) { State.SelectedDay = day; Notify(); } }
    public void Filter(string team) { State.TeamFilter = team; Notify(); }
    public void UpdateSettings(UserSettings value)
    {
        State.Settings = value.Normalize();
        try { if (!State.Demo) persist?.Invoke(State.Settings); State.PreferencesError = ""; }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { State.PreferencesError = $"偏好保存失败：{error.Message}"; }
        Notify();
    }
    public void ToggleFavorite(string team) => UpdateSettings(State.Settings with { Favorites = State.Settings.Favorites.Contains(team) ? State.Settings.Favorites.Where(value => value != team).ToArray() : [.. State.Settings.Favorites, team] });
    public async Task StartAsync()
    {
        if (State.Demo || disposed) return;
        try { await RefreshScheduleAsync(true); while (!lifetime.IsCancellationRequested) { await Task.Delay(TimeSpan.FromSeconds(60), lifetime.Token); await RefreshScheduleAsync(); } }
        catch (OperationCanceledException) when (lifetime.IsCancellationRequested) { }
    }
    public async Task RefreshScheduleAsync(bool restore = false)
    {
        if (State.Demo || disposed) return;
        scheduleCancellation?.Cancel(); scheduleCancellation?.Dispose(); scheduleCancellation = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
        var token = scheduleCancellation.Token; var current = ++scheduleGeneration;
        State.LoadingSchedule = true; Notify();
        try
        {
            var schedule = await service.ScheduleAsync(token);
            if (disposed || token.IsCancellationRequested || current != scheduleGeneration) return;
            State.Days = schedule.Days;
            if (!State.Days.Any(day => day.Day == State.SelectedDay)) State.SelectedDay = State.Days.FirstOrDefault(day => day.Day == schedule.CurrentDate)?.Day ?? State.Days.FirstOrDefault()?.Day ?? "";
            State.ScheduleError = "";
            if (restore && State.Days.SelectMany(day => day.Matches).FirstOrDefault(match => match.Id == State.Settings.LastMatch) is { } saved) Select(saved);
        }
        catch (Exception error) { if (!token.IsCancellationRequested && current == scheduleGeneration && !disposed) State.ScheduleError = error.Message; }
        finally { if (current == scheduleGeneration && !disposed) { State.LoadingSchedule = false; Notify(); } }
    }
    public void Select(Match match)
    {
        if (disposed) return;
        if (State.SelectedMatch?.Id == match.Id) { Notify(); return; }
        CancelLive();
        State.SelectedMatch = match; State.Entries = []; State.FrozenEntries = []; State.Following = true; State.Unread = 0;
        State.MatchError = ""; State.TextError = ""; State.ScoreUpdatedAt = null; State.TextUpdatedAt = null; State.LoadingLive = true;
        liveKey = null; lastScore = DateTimeOffset.MinValue;
        UpdateSettings(State.Settings with { LastMatch = match.Id });
        if (State.Demo) { State.LoadingLive = false; Notify(); return; }
        liveCancellation = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
        _ = PollLoopAsync(generation, liveCancellation.Token);
    }
    public void Retry()
    {
        if (State.SelectedMatch is null || State.Demo || disposed) return;
        CancelLive(); liveKey = null; lastScore = DateTimeOffset.MinValue;
        liveCancellation = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
        _ = PollLoopAsync(generation, liveCancellation.Token);
    }
    private void CancelLive() { generation++; liveCancellation?.Cancel(); liveCancellation?.Dispose(); liveCancellation = null; }
    private async Task PollLoopAsync(int current, CancellationToken token)
    {
        var failures = 0;
        bool IsCurrent() => !disposed && !token.IsCancellationRequested && current == generation;
        try
        {
            while (IsCurrent())
            {
                var id = State.SelectedMatch!.Id;
                if ((DateTimeOffset.UtcNow - lastScore).TotalSeconds >= 9)
                {
                    try
                    {
                        var match = await service.MatchAsync(id, token); if (!IsCurrent()) return;
                        State.SelectedMatch = match; State.ScoreUpdatedAt = lastScore = DateTimeOffset.UtcNow; State.MatchError = ""; Notify();
                    }
                    catch (Exception error) { if (!IsCurrent()) return; State.MatchError = error.Message; }
                }
                if (!IsCurrent()) return;
                if (State.SelectedMatch!.IsUpcoming) State.TextError = "";
                else if (State.SelectedMatch.OpenLive == false) State.TextError = "本场暂未提供文字直播";
                else
                {
                    try
                    {
                        var key = liveKey ?? await service.KeyAsync(id, token); if (!IsCurrent()) return; liveKey = key;
                        var entries = await service.TextAsync(id, key, token); if (!IsCurrent()) return;
                        var known = State.Entries.Select(entry => entry.Id).ToHashSet(StringComparer.Ordinal);
                        if (!State.Following) State.Unread += entries.Where(entry => !known.Contains(entry.Id)).Select(entry => entry.Id).Distinct(StringComparer.Ordinal).Count();
                        State.Entries = LiveEntry.Merge(entries, State.Entries); State.TextUpdatedAt = DateTimeOffset.UtcNow; State.TextError = "";
                    }
                    catch (Exception error) { if (!IsCurrent()) return; State.TextError = error.Message; liveKey = null; }
                }
                if (!IsCurrent()) return;
                State.LoadingLive = false;
                failures = State.MatchError.Length > 0 || (State.TextError.Length > 0 && State.SelectedMatch.OpenLive != false) ? failures + 1 : 0;
                Notify();
                if (State.SelectedMatch.IsFinished && failures == 0) return;
                var seconds = failures > 0 ? Math.Min(60, 5 * (1 << Math.Min(failures, 4))) : State.SelectedMatch.IsUpcoming ? 30 : 5;
                await Task.Delay(TimeSpan.FromSeconds(seconds), token);
            }
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
    }
    public void ToggleFollowing()
    {
        State.Following = !State.Following;
        State.FrozenEntries = State.Following ? [] : State.Entries.ToArray();
        if (State.Following) State.Unread = 0;
        Notify();
    }
    public void LoadDemo()
    {
        State.Demo = true;
        var match = new Match("demo", "勇士", "湖人", "INPROGRESS", 99, 102, Description: "第四节 剩2:18", OpenLive: true);
        State.Days = [new("demo", "演示比赛日", [match, new("demo-2", "尼克斯", "76人", "COMPLETED", 100, 106), new("demo-3", "马刺", "雷霆", "NOTSTARTED", Time: "2026-10-21 11:00:00")])];
        State.SelectedDay = "demo"; State.SelectedMatch = match;
        State.Entries = new[] { "詹姆斯突破上篮得分，湖人领先三分。", "库里借掩护三分出手，球弹筐而出。", "湖人拿下防守篮板，准备发动反击。", "暂停结束，比赛继续。" }.Select((text, index) => new LiveEntry($"demo-{index}", text, $"2026-10-21 10:18:{32 - index * 5:00}")).ToArray();
        State.ScoreUpdatedAt = State.TextUpdatedAt = DateTimeOffset.UtcNow; Notify();
    }
    public void Dispose()
    {
        if (disposed) return; disposed = true; CancelLive(); lifetime.Cancel(); scheduleCancellation?.Cancel(); scheduleCancellation?.Dispose(); lifetime.Dispose();
    }
}
