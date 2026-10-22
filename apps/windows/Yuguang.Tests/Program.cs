using System.Net;
using System.Text.Json;
using Yuguang.Core;

int passed = 0;
void Check(bool condition, string message) { if (!condition) throw new Exception(message); passed++; }
using (var json = JsonDocument.Parse("""{"matchId":9007199254740993,"homeTeamName":"勇士","awayTeamName":"湖人","matchStatus":"INPROGRESS","homeScore":0,"awayScore":2}"""))
{
    var match = Match.Parse(json.RootElement); Check(match.Id == "9007199254740993", "numeric ID retains precision"); Check(match.Score == "2 : 0", "away/home score order and zero"); Check(match.Heading.StartsWith("湖人 2 : 0 勇士"), "tray score direction");
}
Check(new Match("1", "A", "B", "INPROGRESS").Score == "— : —", "missing is not zero");
Check(new Match("1", "A", "B", "NOTSTARTED", 0, 0).Score == "vs", "upcoming not misleading 0:0");
Check(LiveEntry.PlainText("<b>进球</b><br/>A &amp; B") == "进球 A & B", "HTML rendered as plain text");
Check(LiveEntry.Merge([new("a", "new", ""), new("a", "duplicate", "")], [new("b", "old", "")]).Select(e => e.Content).SequenceEqual(["new", "old"]), "merge dedupes in newest order");
Check(LiveEntry.Merge(Enumerable.Range(0, 600).Select(i => new LiveEntry(i.ToString(), "", "")), []).Count == 500, "history bounded");
Check(HupuApi.BuildUri("text", "1&2", "a+b%/=?").Query == "?matchId=1%262&liveActivityKeyStr=a%2Bb%25%2F%3D%3F", "query encoded exactly once");
try { HupuApi.Decode("""{"status":500,"result":[]}"""); throw new Exception("error accepted"); } catch (InvalidDataException) { passed++; }
Check(HupuApi.Decode("""{"status":200,"result":{"x":1}}""").GetProperty("x").GetInt32() == 1, "result remains alive after document disposal");
Check((new UserSettings { Rows = 99, Theme = "invalid", Favorites = ["湖人", "湖人"], ExpandedFrame = new(double.NaN, 0, 500, 600) }).Normalize() is { Rows: 6, Theme: "system", Favorites.Length: 1, ExpandedFrame: null }, "corrupt preferences normalized");
var directory = Path.Combine(Path.GetTempPath(), "yuguang-test-" + Guid.NewGuid()); var path = Path.Combine(directory, "settings.json");
try { var store = new SettingsStore(path); store.Save(new UserSettings { Rows = 4, SimpleMode = true }); Check(store.Load() is { Rows: 4, SimpleMode: true }, "settings roundtrip"); File.WriteAllText(path, "broken"); Check(store.Load().Rows == 1, "invalid settings recover"); } finally { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
// A deliberately cancellation-ignoring old request must never replace the new selection.
var fake = new RaceService(); using (var session = new LiveSession(fake, new()))
{
    session.Select(new("old", "A", "B", "INPROGRESS")); session.Select(new("new", "C", "D", "INPROGRESS"));
    fake.Old.SetResult(new("old", "A", "B", "COMPLETED", 100, 99)); await Task.Delay(40);
    Check(session.State.SelectedMatch?.Id == "new", "late old response cannot overwrite selected match");
    Check(session.State.Entries.Single().Content == "new text", "late request cannot contaminate text");
    session.ToggleFollowing(); Check(!session.State.Following && session.State.FrozenEntries.Count == 1, "pause freezes snapshot"); session.ToggleFollowing(); Check(session.State.Following && session.State.Unread == 0, "resume resets unread");
}
int writes = 0; using (var demo = new LiveSession(fake, new(), _ => writes++)) { demo.LoadDemo(); demo.UpdateSettings(new() { Rows = 6 }); Check(writes == 0, "diagnostics never persist preferences"); }
var original = Enumerable.Range(0, 5).Select(i => new LiveEntry(i.ToString(), "message " + i, "")).ToArray();
var history = new CompactHistory(); history.Move(1, original);
Check(history.IsReading && history.VisibleEntries(original)[0].Id == "1", "compact scroll enters history");
var incoming = new[] { new LiveEntry("new", "new message", "") }.Concat(original).ToArray();
Check(history.VisibleEntries(incoming)[0].Id == "1" && history.UnreadCount(incoming) == 1, "new messages do not move compact history");
history.Move(500, incoming); Check(history.VisibleEntries(incoming)[0].Id == "4", "compact oldest boundary");
history.Move(-500, incoming); Check(!history.IsReading && history.VisibleEntries(incoming)[0].Id == "new" && history.UnreadCount(incoming) == 0, "scroll to live resumes latest");
history.Scroll(5.5, original, 3); Check(history.Position == 5.5 && history.Offset == 0 && history.Remainder == 5.5, "fractional continuous history scroll");
Check(history.VisibleEntries(incoming)[0].Id == "0", "fractional scroll also freezes incoming batches");
history.Scroll(500, incoming, 3); Check(history.Position == 64 && history.VisibleEntries(incoming).Count == 3, "oldest boundary fills viewport");
history.Scroll(-500, incoming, 3); Check(!history.IsReading, "scroll up to top resumes follow");
history.Scroll(10, original, 6); Check(!history.IsReading, "no scrolling when messages fit viewport");
history.Move(1, []); Check(!history.IsReading, "empty compact history");
history.Move(1, original.Take(1).ToArray()); Check(!history.IsReading, "single-message compact history");
using (var compactSession = new LiveSession(fake, new())) {
    compactSession.LoadDemo(); compactSession.ScrollCompact(1);
    Check(compactSession.State.CompactHistory.IsReading && compactSession.State.Following, "compact history independent of expanded follow mode");
    compactSession.Select(compactSession.SwitchableMatches.First(m => m.Id != "demo"));
    Check(!compactSession.State.CompactHistory.IsReading, "match switch resets compact cursor");
}
if (args.Contains("--check-api"))
{
    using var client = new HttpClient(); var api = new HupuApi(client); using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(45)); var schedule = await api.ScheduleAsync(timeout.Token); Check(schedule.Days.Count > 0, "live schedule"); var match = schedule.Days.SelectMany(day => day.Matches).FirstOrDefault(m => !m.IsUpcoming && m.OpenLive != false); if (match != null) { var latest = await api.MatchAsync(match.Id, timeout.Token); Check(latest.Id == match.Id, "live match"); var key = await api.KeyAsync(match.Id, timeout.Token); var entries = await api.TextAsync(match.Id, key, timeout.Token); Check(entries.Count > 0, "live text"); Console.WriteLine(latest.Heading + " · " + entries.Count + " text entries"); }
}
Console.WriteLine($"PASS {passed} core checks");
sealed class RaceService : ILiveService
{
    public TaskCompletionSource<Match> Old { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
    public Task<Schedule> ScheduleAsync(CancellationToken token) => Task.FromResult(new Schedule([], ""));
    public Task<Match> MatchAsync(string id, CancellationToken token) => id == "old" ? Old.Task : Task.FromResult(new Match("new", "C", "D", "COMPLETED", 2, 3));
    public Task<string> KeyAsync(string id, CancellationToken token) => Task.FromResult("key");
    public Task<IReadOnlyList<LiveEntry>> TextAsync(string id, string key, CancellationToken token) => Task.FromResult<IReadOnlyList<LiveEntry>>([new("new", "new text", "")]);
}
