using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Yuguang.Core;

/// <summary>A match identifier is always text, including numeric IDs larger than 2^53.</summary>
public sealed record Match(string Id, string Home, string Away, string MatchStatus, int? HomeScore = null, int? AwayScore = null,
    string Time = "", string Description = "", bool? OpenLive = null, string Stage = "")
{
    public bool IsLive => MatchStatus == "INPROGRESS";
    public bool IsUpcoming => MatchStatus == "NOTSTARTED";
    public bool IsFinished => MatchStatus == "COMPLETED";
    public string Score => IsUpcoming ? "vs" : $"{AwayScore?.ToString() ?? "—"} : {HomeScore?.ToString() ?? "—"}";
    public string Status => Description.Length > 0 ? Description : IsLive ? "进行中" : IsFinished ? "已结束" : IsUpcoming ? "未开始" : "赛程待定";
    public string Start => Time.Length >= 16 ? Time.Substring(5, 11) : Time;
    public string Heading => $"{Away} {Score} {Home} · {Status}";
    public static Match Parse(JsonElement json) => new(Json.ReadId(json, "matchId"), Json.Text(json, "homeTeamName"), Json.Text(json, "awayTeamName"), Json.Text(json, "matchStatus"),
        Json.Integer(json, "homeScore"), Json.Integer(json, "awayScore"), Json.Text(json, "matchTime"),
        json.TryGetProperty("frontEndMatchStatus", out var display) && display.ValueKind == JsonValueKind.Object ? Json.Text(display, "desc") : "",
        json.TryGetProperty("openLive", out var live) && live.ValueKind is JsonValueKind.True or JsonValueKind.False ? live.GetBoolean() : null, Json.Text(json, "competitionStageDesc"));
}
public sealed record GameDay(string Day, string Label, IReadOnlyList<Match> Matches);
public sealed record Schedule(IReadOnlyList<GameDay> Days, string CurrentDate);
public sealed record LiveEntry(string Id, string Content, string Time)
{
    public string Clock => Time.Length >= 19 ? Time[^8..] : Time;
    public static LiveEntry Parse(JsonElement json)
    {
        var raw = Json.Text(json, "content"); var time = Json.Text(json, "time");
        var id = json.TryGetProperty("commentId", out var value) && value.ValueKind is JsonValueKind.Number or JsonValueKind.String ? Json.ReadId(json, "commentId") : $"{time}|{raw}";
        return new(id, PlainText(raw), time);
    }
    public static string PlainText(string raw) => WebUtility.HtmlDecode(Regex.Replace(Regex.Replace(raw, @"<br\s*/?>", " ", RegexOptions.IgnoreCase), "<[^>]*>", "")).Trim();
    public static IReadOnlyList<LiveEntry> Merge(IEnumerable<LiveEntry> incoming, IEnumerable<LiveEntry> existing, int limit = 500)
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        return incoming.Concat(existing).Where(entry => seen.Add(entry.Id)).Take(limit).ToArray();
    }
}
internal static class Json
{
    public static string Text(JsonElement json, string key) => json.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() ?? "" : "";
    public static int? Integer(JsonElement json, string key) => json.TryGetProperty(key, out var value) && value.TryGetInt32Safe(out var number) ? number : null;
    public static string ReadId(JsonElement json, string key)
    {
        if (!json.TryGetProperty(key, out var value)) throw new InvalidDataException("赛事数据缺少 ID");
        if (value.ValueKind == JsonValueKind.String) return value.GetString() ?? throw new InvalidDataException("赛事 ID 无效");
        if (value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out _)) return value.GetRawText();
        throw new InvalidDataException("赛事 ID 无效");
    }
}
