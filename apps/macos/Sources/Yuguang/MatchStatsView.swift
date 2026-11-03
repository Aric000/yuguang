import SwiftUI
import YuguangCore

struct MatchStatsView: View {
    @Bindable var model: AppModel
    private var teamID: String? { model.statsHome ? model.selectedMatch?.homeTeamId : model.selectedMatch?.awayTeamId }
    private var requestID: String { "\(model.selectedMatch?.id ?? "")|\(teamID ?? "")|\(model.statsRefresh)" }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("数据统计").fontWeight(.medium)
                    .overlay { DragArea().accessibilityHidden(true) }
                Spacer(minLength: 0)
                Group {
                    Menu(model.statsHome ? model.selectedMatch?.homeTeamName ?? "主队" : model.selectedMatch?.awayTeamName ?? "客队") {
                        Button(model.selectedMatch?.awayTeamName ?? "客队") { model.statsHome = false }
                        Button(model.selectedMatch?.homeTeamName ?? "主队") { model.statsHome = true }
                    }.menuStyle(.borderlessButton).fixedSize().help("切换统计球队")
                    Button { model.statsRefresh += 1 } label: { Image(systemName: "arrow.clockwise") }
                        .help("刷新数据统计").disabled(model.statsLoading)
                    Button { model.showingStats = false } label: { Image(systemName: "text.alignleft") }
                        .help("回到文字直播")
                    QuickMatchButton(model: model).frame(width: 24, height: 26)
                }.opacity(model.compactChromeVisible ? 1 : 0)
                    .allowsHitTesting(model.compactChromeVisible)
            }.frame(height: 32).padding(.horizontal, 12)
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    row(["球员", "时间", "得分", "篮板", "助攻", "抢断", "盖帽", "+/−"], heading: true)
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            ForEach(model.statsPlayers) { player in
                                row([player.name, player.mins ?? "—", number(player.pts), number(player.reb), number(player.asts), number(player.stl), number(player.blk), player.plusMinus ?? "—"])
                            }
                            if let error = model.statsError {
                                Button("\(error) · 点击重试") { model.statsRefresh += 1 }.buttonStyle(.plain).padding(8)
                            } else if model.statsPlayers.isEmpty {
                                Text(model.statsLoading ? "正在获取统计…" : "暂无球员统计，开赛后可刷新")
                                    .foregroundStyle(.secondary).frame(height: 32)
                            }
                        }.frame(maxWidth: .infinity, alignment: .topLeading)
                    }.defaultScrollAnchor(.topLeading).id(requestID)
                }.frame(width: 455).padding(.horizontal, 12)
            }

        }.font(.system(size: 12)).buttonStyle(.plain)
        .task(id: requestID) {
            guard !model.demo, !Task.isCancelled else { return }
            let requestID = UUID()
            model.statsRequestID = requestID
            model.statsPlayers = []; model.statsError = nil
            guard let match = model.selectedMatch, let teamID else { model.statsError = "请先选择有统计数据的比赛"; return }
            model.statsLoading = true
            defer { if model.statsRequestID == requestID { model.statsLoading = false } }
            while !Task.isCancelled {
                model.statsLoading = true
                do {
                    let result = try await HupuAPI().playerStats(matchID: match.id, teamID: teamID)
                    try Task.checkCancellation()
                    guard model.statsRequestID == requestID else { return }
                    model.statsPlayers = result.players.compactMap(\.stats); model.statsError = nil
                } catch {
                    guard !Task.isCancelled, model.statsRequestID == requestID else { return }
                    model.statsError = "统计加载失败"
                }
                model.statsLoading = false
                if model.selectedMatch?.isFinished == true && model.statsError == nil { return }
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
        .contextMenu {
            Menu("显示行数") {
                ForEach(3...6, id: \.self) { count in Button("\(count) 行") { model.compactRows = count } }
            }
            Button("回到文字直播") { model.showingStats = false }
        }
    }
    private func number(_ value: Int?) -> String { value.map(String.init) ?? "—" }
    private func row(_ values: [String], heading: Bool = false) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Text(value).lineLimit(1)
                    .frame(width: index == 0 ? 105 : 42, alignment: index == 0 ? .leading : .trailing)
            }
        }.monospacedDigit().fontWeight(heading ? .medium : .regular)
            .foregroundStyle(heading ? .secondary : .primary).frame(height: 32)
    }
}
