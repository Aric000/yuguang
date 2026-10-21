# 数据接入

仅参考 [hupumoyu-assistant](https://github.com/chenyaoyi88/hupumoyu-assistant) 的接口调用思路，独立实现跨平台客户端。

按以下顺序请求，所有请求使用 HTTPS GET：

1. `https://games.mobileapi.hupu.com/1/7.5.60/basketballapi/scheduleList?competitionTag=nba`：赛程与比赛 ID。
2. `https://live-api.liangle.com/1/7.5.60/live/queryLiveActivityKey?competitionType=basketball&matchId=…`：直播参数。
3. `https://live-api.liangle.com/1/7.5.60/live/queryLiveTextList?matchId=…&liveActivityKeyStr=…`：近期文字消息。
4. `https://games.mobileapi.hupu.com/1/7.5.60/basketballapi/singleMatch?matchId=…`：比分与状态。

Mac 通过 URLComponents、Windows 通过 Uri.EscapeDataString 编码参数一次，避免直播参数被双重编码。请求超时 12 秒；先检查 HTTP 状态，再检查业务状态，最后解析 result。接口失败时保留服务端错误信息。

赛程每 60 秒刷新；进行中的文字每 5 秒、比分约每 10 秒刷新；未开赛每 30 秒检查；结束后获取最后数据并停止本场轮询。失败指数退避至最多 60 秒，文字请求失败后重新获取直播参数。

消息按服务端顺序去重，不按消息 ID 排序；大整数 ID 使用 Swift 无损整数解码或 C# JsonElement.GetRawText 按字符串保留，避免浮点精度丢失。会话最多保留 500 条。切换比赛会取消旧请求，并通过选择代次检查，防止旧比赛响应覆盖新比赛。

接口只返回近期消息，不承诺完整历史；第三方接口不是稳定的公开 SDK，字段、路径与行为可能变更。运行 Mac 应用的 `--check-api` 或 `dotnet run --project apps/windows/Yuguang.Tests -- --check-api` 可验证实际连通性。
