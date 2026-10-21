using System.Text.Json;

namespace Yuguang.Core;

public interface ILiveService
{
    Task<Schedule> ScheduleAsync(CancellationToken token);
    Task<Match> MatchAsync(string id, CancellationToken token);
    Task<string> KeyAsync(string id, CancellationToken token);
    Task<IReadOnlyList<LiveEntry>> TextAsync(string id, string key, CancellationToken token);
}
/// <summary>Fixed HTTPS endpoints; no arbitrary remote address is accepted from the UI.</summary>
public sealed class HupuApi(HttpClient client) : ILiveService
{
    public static Uri BuildUri(string kind, string id = "", string key = "")
    {
        var (host, method, query) = kind switch
        {
            "schedule" => ("games.mobileapi.hupu.com", "basketballapi/scheduleList", "competitionTag=nba"),
            "match" => ("games.mobileapi.hupu.com", "basketballapi/singleMatch", $"matchId={Uri.EscapeDataString(id)}"),
            "key" => ("live-api.liangle.com", "live/queryLiveActivityKey", $"competitionType=basketball&matchId={Uri.EscapeDataString(id)}"),
            "text" => ("live-api.liangle.com", "live/queryLiveTextList", $"matchId={Uri.EscapeDataString(id)}&liveActivityKeyStr={Uri.EscapeDataString(key)}"),
            _ => throw new ArgumentException("未知赛事接口", nameof(kind))
        };
        return new Uri($"https://{host}/1/7.5.60/{method}?{query}");
    }
    public static JsonElement Decode(string raw)
    {
        using var document = JsonDocument.Parse(raw);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object) throw new InvalidDataException("赛事服务返回无效数据");
        if ((root.TryGetProperty("success", out var success) && success.ValueKind == JsonValueKind.False) ||
            (root.TryGetProperty("status", out var code) && code.ValueKind != JsonValueKind.Null && (!code.TryGetInt32Safe(out var status) || status != 200)))
            throw new InvalidDataException(Json.Text(root, "errorMsg") is { Length: > 0 } error ? error : Json.Text(root, "msg") is { Length: > 0 } message ? message : "直播服务返回异常");
        if (!root.TryGetProperty("result", out var result) || result.ValueKind == JsonValueKind.Null) throw new InvalidDataException("直播服务未返回有效数据");
        return result.Clone();
    }
    private async Task<JsonElement> GetAsync(string kind, string id, string key, CancellationToken token)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token); timeout.CancelAfter(TimeSpan.FromSeconds(12));
        using var request = new HttpRequestMessage(HttpMethod.Get, BuildUri(kind, id, key)); request.Headers.Accept.ParseAdd("application/json");
        using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode) throw new HttpRequestException($"直播服务暂不可用（HTTP {(int)response.StatusCode}）");
        await response.Content.LoadIntoBufferAsync(8 * 1024 * 1024, timeout.Token).ConfigureAwait(false);
        return Decode(await response.Content.ReadAsStringAsync(timeout.Token).ConfigureAwait(false));
    }
    public async Task<Schedule> ScheduleAsync(CancellationToken token)
    {
        var data = await GetAsync("schedule", "", "", token).ConfigureAwait(false);
        var days = data.GetProperty("gameList").EnumerateArray().Select(day => new GameDay(Json.Text(day, "day"), Json.Text(day, "dayBlock") is { Length: > 0 } label ? label : Json.Text(day, "day"), day.GetProperty("matchList").EnumerateArray().Select(Match.Parse).ToArray())).ToArray();
        return new(days, data.TryGetProperty("scheduleListStats", out var stats) && stats.ValueKind == JsonValueKind.Object ? Json.Text(stats, "currentDate") : "");
    }
    public async Task<Match> MatchAsync(string id, CancellationToken token) => Match.Parse(await GetAsync("match", id, "", token).ConfigureAwait(false));
    public async Task<string> KeyAsync(string id, CancellationToken token)
    {
        var key = Json.Text(await GetAsync("key", id, "", token).ConfigureAwait(false), "liveActivityKey");
        return key.Length > 0 ? key : throw new InvalidDataException("直播参数无效");
    }
    public async Task<IReadOnlyList<LiveEntry>> TextAsync(string id, string key, CancellationToken token) => (await GetAsync("text", id, key, token).ConfigureAwait(false)).EnumerateArray().Select(LiveEntry.Parse).ToArray();
}
internal static class ElementExtensions
{
    public static bool TryGetInt32Safe(this JsonElement value, out int number) { number = 0; return value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out number); }
}
