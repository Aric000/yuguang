import SwiftUI
import YuguangCore

private struct Palette {
    let dark: Bool
    var ground: Color { Color(white: dark ? 0.065 : 0.95) }
    var sheet: Color { Color(white: dark ? 0.105 : 1) }
    var raised: Color { Color(white: dark ? 0.15 : 0.97) }
    var ink: Color { Color(white: dark ? 0.94 : 0.10) }
    var secondary: Color { Color(white: dark ? 0.68 : 0.40) }
    var edge: Color { Color(white: dark ? 0.20 : 0.91) }
    var signal: Color { dark ? Color(red: 0.42, green: 0.72, blue: 0.57) : Color(red: 0.17, green: 0.43, blue: 0.32) }
    var brand: Color { Color(red: 0.95, green: 0.41, blue: 0.19) }
}

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var scheme
    private var p: Palette { Palette(dark: scheme == .dark) }
    var body: some View {
        Group {
            if model.compact {
                if model.showingForum { ForumView(model: model) } else { compactBar }
            }
            else {
                VStack(spacing: 0) {
                    titleBar
                    Group {
                        switch model.page {
                        case .matches: matchList
                        case .live: liveView
                        case .settings: settings
                        case .forum: ForumView(model: model)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(p.sheet, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(p.edge, lineWidth: 1))
                    .padding(.horizontal, 8).padding(.bottom, 8)
                    footer
                }
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(p.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(model.compactChromeVisible ? p.ground : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: model.compact ? 8 : 20))
        .tint(p.ink)
        .preferredColorScheme(model.colorScheme)
        .sheet(isPresented: $model.choosingFavoriteTeams) { FavoriteTeamPicker(model: model) }
    }
    private var titleBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                BrandMark(variant: model.brandVariant).frame(width: 28, height: 28)
                Text("余光").font(.system(size: 16, weight: .semibold))
                if model.demo { Text("演示").font(.system(size: 11)).foregroundStyle(p.secondary) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // SwiftUI hosting consumes background mouse events; use an explicit native drag surface.
            // Keep it within the leading region so title-bar buttons retain their own hit targets.
            .overlay { DragArea().accessibilityHidden(true) }
            QuickMatchButton(model: model).frame(width: 24, height: 26)
            if model.selectedMatch != nil || model.showingForum {
                iconButton("rectangle.compress.vertical", label: "精简模式（\(model.compactRows) 行）") { model.onToggleCompact?() }
            }
            iconButton(model.page == .settings ? "arrow.left" : "slider.horizontal.3", label: model.page == .settings ? "返回" : "设置") {
                model.page = model.page == .settings ? (model.showingForum ? .forum : (model.selectedMatch == nil ? .matches : .live)) : .settings
            }
            iconButton("xmark", label: "隐藏窗口（\(model.shortcut.label)）") { model.onHide?() }
        }.padding(.horizontal, 16).frame(height: 48)
    }
    private var footer: some View {
        HStack {
            Text(model.page == .settings ? "更改自动保存" : (model.showingForum ? "社区浏览 · 来源虎扑" : "文字直播 · 来源虎扑"))
            Spacer()
            Text("\(model.shortcut.label) 隐藏 / 恢复")
        }.font(.system(size: 11)).foregroundStyle(p.secondary)
            .padding(.horizontal, 20).padding(.bottom, 12).padding(.top, 2)
    }
    private var matchList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("比赛日").font(.system(size: 22, weight: .semibold))
                Spacer()
                if model.selectedMatch != nil { Button("继续观看") { model.page = .live }.buttonStyle(.plain) }
                iconButton("arrow.clockwise", label: "刷新赛程") { Task { await model.refreshSchedule() } }
            }
            HStack(spacing: 8) {
                Picker("日期", selection: $model.selectedDay) {
                    ForEach(model.days, id: \.day) { day in Text(day.dayBlock ?? day.day).tag(day.day) }
                }.labelsHidden().accessibilityLabel("比赛日期")
                Picker("球队", selection: $model.teamFilter) {
                    Text("全部球队").tag("全部球队")
                    ForEach(model.teams, id: \.self) { team in Text((model.favoriteTeams.contains(team) ? "★ " : "") + team).tag(team) }
                }.labelsHidden().accessibilityLabel("筛选球队")
            }.controlSize(.regular)
            if model.teamFilter != "全部球队" {
                Button {
                    model.toggleFavorite(model.teamFilter)
                } label: {
                    Label(model.favoriteTeams.contains(model.teamFilter) ? "已关注\(model.teamFilter)" : "关注\(model.teamFilter)", systemImage: model.favoriteTeams.contains(model.teamFilter) ? "star.fill" : "star")
                }.buttonStyle(.plain).foregroundStyle(p.secondary)
            }
            if let error = model.scheduleError {
                errorBlock(error, action: { Task { await model.refreshSchedule() } })
            }
            if model.loadingSchedule && model.days.isEmpty {
                emptyState("正在获取赛程", description: "连接虎扑赛事服务", loading: true)
            } else if model.visibleMatches.isEmpty {
                emptyState("这一天没有相关比赛", description: "换个日期，或查看全部球队。")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.visibleMatches) { match in
                            Button { model.select(match) } label: { matchRow(match) }.buttonStyle(.plain)
                                .accessibilityLabel("\(match.title)，\(match.status)，打开文字直播")
                        }
                    }.padding(.bottom, 4)
                }
            }
        }.padding(20)
    }
    private func matchRow(_ match: Match) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 6) {
                if match.isLive { Circle().fill(p.signal).frame(width: 5, height: 5) }
                Text(match.isUpcoming ? match.startLabel : match.status)
                    .foregroundStyle(match.isLive ? p.signal : p.secondary)
                Spacer()
                if model.favoriteTeams.contains(match.awayTeamName) || model.favoriteTeams.contains(match.homeTeamName) {
                    Image(systemName: "star.fill").foregroundStyle(p.secondary)
                }
                Image(systemName: "arrow.up.right").foregroundStyle(p.secondary)
            }.font(.system(size: 11))
            rowTeam(match.awayTeamName, logo: match.awayTeamLogo, score: match.isUpcoming ? nil : match.awayScore)
            rowTeam(match.homeTeamName, logo: match.homeTeamLogo, score: match.isUpcoming ? nil : match.homeScore)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(p.raised, in: RoundedRectangle(cornerRadius: 8))
    }
    private func rowTeam(_ name: String, logo: String?, score: Int?) -> some View {
        HStack(spacing: 10) {
            if !model.simpleModeEnabled { TeamBadge(name: name, remoteURL: logo, size: 25) }
            Text(name).font(.system(size: 14, weight: .medium))
            Spacer()
            Text(score.map(String.init) ?? "—").font(.system(size: 18, weight: .medium)).monospacedDigit()
        }
    }
    private var liveView: some View {
        VStack(spacing: 0) {
            if let match = model.selectedMatch {
                VStack(spacing: 16) {
                    HStack {
                        Text("NBA").font(.system(size: 12, weight: .bold))
                        Text(match.competitionStageDesc ?? "篮球赛事").foregroundStyle(p.secondary)
                        Spacer()
                        Button { model.page = .matches } label: {
                            HStack(spacing: 4) { Text("赛程"); Image(systemName: "chevron.right").font(.system(size: 10)) }
                        }.buttonStyle(.plain)
                    }.font(.system(size: 12))
                    HStack(alignment: .top, spacing: 8) {
                        scoreboardTeam(match, home: false)
                        VStack(spacing: 6) {
                            Text(match.isUpcoming ? "对阵" : (match.isFinished ? "终场" : "直播"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(match.isLive ? p.signal : p.secondary)
                            Text("VS").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.secondary)
                        }.frame(width: 44).padding(.top, 28)
                        scoreboardTeam(match, home: true)
                    }
                    HStack(spacing: 6) {
                        if match.isLive { Circle().fill(p.signal).frame(width: 5, height: 5) }
                        Text(match.isUpcoming ? match.startLabel : match.status)
                    }.font(.system(size: 12, weight: .medium)).foregroundStyle(p.secondary)
                }.padding(20)
                HStack(spacing: 4) {
                    teamColor(match, home: false).opacity(0.75)
                    teamColor(match, home: true).opacity(0.75)
                }.frame(height: 3).padding(.horizontal, 20)
                HStack {
                    Text("文字直播").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button(model.following ? "阅读历史" : "回到最新\(model.unread > 0 ? " · \(model.unread)" : "")") { model.toggleFollowing() }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(p.secondary)
                }.padding(.horizontal, 20).padding(.vertical, 14)
                if let error = model.connectionError { errorBlock(error) { model.retryLive() }.padding(.horizontal, 20).padding(.bottom, 10) }
                if model.entries.isEmpty {
                    emptyState(model.loadingLive ? "正在连接直播" : (match.isUpcoming ? "等待开赛" : "暂时没有文字内容"),
                               description: match.isUpcoming ? "比赛开始后自动更新" : "有新消息时会自动出现在这里", loading: model.loadingLive)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 20) {
                                Color.clear.frame(height: 0).id("latest")
                                ForEach(model.displayedEntries) { entry in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 6) {
                                            Text(entry.clock).monospacedDigit()
                                            if entry.id == model.entries.first?.id { Text("最新").foregroundStyle(p.signal) }
                                        }.font(.system(size: 11)).foregroundStyle(p.secondary)
                                        Text(entry.content).font(.system(size: 14, weight: entry.id == model.entries.first?.id ? .medium : .regular)).lineSpacing(5).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                    }.frame(maxWidth: .infinity, alignment: .leading).id(entry.id)
                                }
                            }.padding(.horizontal, 20).padding(.bottom, 20)
                        }
                        .onChange(of: model.entries.first?.id) { _, _ in if model.following { proxy.scrollTo("latest", anchor: .top) } }
                        .onChange(of: model.following) { _, following in if following { proxy.scrollTo("latest", anchor: .top) } }
                        .onScrollWheel { if model.following { model.toggleFollowing() } }
                    }
                }
                freshness.padding(.horizontal, 20).padding(.vertical, 12)
            } else { emptyState("选择一场比赛", description: "从赛程中打开文字直播") }
        }
    }
    private func teamColor(_ match: Match, home: Bool) -> Color {
        TeamAssets.color(name: home ? match.homeTeamName : match.awayTeamName,
                         hex: scheme == .dark ? (home ? match.homeTeamNightColor : match.awayTeamNightColor) : (home ? match.homeTeamDayColor : match.awayTeamDayColor), dark: scheme == .dark)
    }
    private func scoreboardTeam(_ match: Match, home: Bool) -> some View {
        let name = home ? match.homeTeamName : match.awayTeamName
        let score = home ? match.homeScore : match.awayScore
        let color = teamColor(match, home: home)
        return VStack(spacing: 9) {
            if !model.simpleModeEnabled {
                TeamBadge(name: name, remoteURL: home ? match.homeTeamLogo : match.awayTeamLogo, size: 58)
                    .frame(width: 90, height: 74)
                    .background(color.opacity(scheme == .dark ? 0.10 : 0.06), in: RoundedRectangle(cornerRadius: 16))
            }
            Text(name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            Text(match.isUpcoming ? "—" : (score.map(String.init) ?? "—"))
                .font(.system(size: 34, weight: .semibold)).monospacedDigit()
                .foregroundStyle(p.ink)
            Button { model.toggleFavorite(name) } label: {
                HStack(spacing: 4) {
                    Text(home ? "主场" : "客场")
                    Image(systemName: model.favoriteTeams.contains(name) ? "star.fill" : "star")
                }.font(.system(size: 11)).foregroundStyle(p.secondary)
            }.buttonStyle(.plain).help("关注或取消关注\(name)")
        }.frame(maxWidth: .infinity)
    }
    private var freshness: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 6) {
                let age = model.scoreUpdatedAt.map { max(0, Int(context.date.timeIntervalSince($0))) }
                Circle().fill(model.connectionError == nil && (age ?? 99) < 30 ? p.signal : p.secondary).frame(width: 5, height: 5)
                Text(age.map { "比分更新于 \($0) 秒前" } ?? "等待比分更新")
                Spacer()
                if model.demo { Text("示例数据") }
                else if model.selectedMatch?.isFinished == true { Text("已结束") }
                else { Text("自动更新") }
            }.font(.system(size: 11)).foregroundStyle(p.secondary)
        }
    }
    private var compactBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let match = model.selectedMatch {
                    HStack(spacing: 5) {
                        Text(match.awayTeamName)
                        Text(match.score).monospacedDigit().fontWeight(.medium)
                        Text(match.homeTeamName)
                    }.fixedSize()
                    if model.compactRows == 1 && (!model.scoreOnly || model.compactHistory.isReading) {
                        Rectangle().fill(p.edge).frame(width: 1, height: 12).opacity(model.compactChromeVisible ? 1 : 0)
                        compactMessages(rows: 1, inline: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer(minLength: 0)
                    }
                    if model.connectionError != nil { Image(systemName: "exclamationmark.circle").help(model.connectionError ?? "") }
                } else { Text("余光 · 选择比赛"); Spacer() }
                if model.compactHistory.isReading {
                    iconButton("arrow.up.to.line", label: "回到最新（\(model.compactUnread) 条新消息）") { model.followCompactLatest() }
                        .opacity(model.compactChromeVisible ? 1 : 0)
                        .allowsHitTesting(model.compactChromeVisible)
                        .accessibilityHidden(!model.compactChromeVisible)
                }
                iconButton("arrow.up.left.and.arrow.down.right", label: "展开直播") { model.onToggleCompact?() }
                    .opacity(model.compactChromeVisible ? 1 : 0)
                    .allowsHitTesting(model.compactChromeVisible)
                    .accessibilityHidden(!model.compactChromeVisible)
                QuickMatchButton(model: model).frame(width: 24, height: 26)
                    .opacity(model.compactChromeVisible ? 1 : 0)
                    .allowsHitTesting(model.compactChromeVisible)
                    .accessibilityHidden(!model.compactChromeVisible)
            }.frame(height: 32)
            if model.compactRows > 1 {
                compactMessages(rows: model.compactRows - 1, inline: false)
            }
        }.font(.system(size: 12)).padding(.horizontal, 12)
            .contentShape(Rectangle())
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    VStack(alignment: .leading, spacing: 0) {
                        DragArea(doubleClick: { model.onToggleCompact?() })
                            .frame(width: max(0, proxy.size.width - (model.compactHistory.isReading ? 108 : 74)), height: 32)
                        if model.compactRows > 1 {
                            DragArea(doubleClick: { model.onToggleCompact?() })
                                .frame(width: proxy.size.width, height: max(0, proxy.size.height - 32))
                        }
                    }.accessibilityHidden(true)
                }
            }
            .background(CompactWheelObserver(action: model.scrollCompactPixels))
            .contextMenu {
                if model.compactHistory.isReading { Button("回到最新", action: model.followCompactLatest) }
                Button("展开直播") { model.onToggleCompact?() }
                Menu("显示行数") {
                    ForEach(1...6, id: \.self) { count in
                        Button("\(count) 行") { model.compactRows = count }
                    }
                }
                Toggle("单行只看比分", isOn: $model.scoreOnly)
                Toggle("窗口置顶", isOn: $model.pinned)
                Button("隐藏（\(model.shortcut.label)）") { model.onHide?() }
            }.help((model.compactEntries.first?.content ?? model.latestText) + "\n滚轮查看历史 · 拖动文字移动 · 双击展开 · " + model.shortcut.label + " 隐藏")
    }
    private func compactMessages(rows: Int, inline: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(model.compactEntries.prefix(rows + 1).enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: 10) {
                    if !inline { Text(entry.clock).font(.system(size: 11)).monospacedDigit().foregroundStyle(p.secondary) }
                    Text(entry.content).lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(inline || index > 0 ? p.secondary : p.ink)
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
            }
            if model.compactEntries.isEmpty {
                Text(model.latestText).foregroundStyle(p.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
            }
        }
        .offset(y: -model.compactHistory.remainder)
        .frame(height: CGFloat(rows) * 32, alignment: .top)
        .clipped()
    }
    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("偏好设置").font(.system(size: 22, weight: .semibold))
                HStack(spacing: 14) {
                    BrandMark(variant: model.brandVariant).frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("品牌标志").fontWeight(.medium)
                        Text("余光之眼").font(.system(size: 14, weight: .medium))
                        Text("眼睛与篮筐，也是一眼就能看见的比赛。")
                            .font(.system(size: 11)).foregroundStyle(p.secondary)
                    }
                }
                favoriteTeamSettings
                VStack(alignment: .leading, spacing: 10) {
                    Text("全局隐藏快捷键").fontWeight(.medium)
                    Text("随时隐藏，再按一次恢复。录制时按 Esc 取消。")
                        .font(.system(size: 12)).foregroundStyle(p.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(model.isRecordingShortcut ? "请按下组合键…" : model.shortcut.label) { model.isRecordingShortcut = true }
                            .buttonStyle(.bordered).controlSize(.large)
                        Spacer()
                        Button("恢复默认") { model.applyShortcut(.standard) }.buttonStyle(.plain).font(.system(size: 12))
                    }
                    if model.isRecordingShortcut {
                        ShortcutRecorder(apply: model.applyShortcut, cancel: { model.isRecordingShortcut = false }).frame(height: 1)
                    }
                    if let error = model.shortcutError { Text(error).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true) }
                }.padding(16).background(p.raised, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 12) {
                    Text("外观").fontWeight(.medium)
                    Picker("外观", selection: $model.theme) {
                        Text("跟随系统").tag("system"); Text("雾白").tag("light"); Text("炭黑").tag("dark")
                    }.pickerStyle(.segmented).labelsHidden()
                    HStack(spacing: 8) {
                        Text("湖人 102 : 99 勇士").monospacedDigit()
                        Text("突破上篮得分").foregroundStyle(p.secondary)
                    }.font(.system(size: 11)).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(p.ground, in: RoundedRectangle(cornerRadius: 8))
                }
                VStack(spacing: 18) {
                    settingToggle("启用简洁模式", detail: "纯文字、不显示队徽；下次启动仍使用。", value: $model.simpleModeEnabled)
                    settingToggle("窗口置顶", detail: "浮在普通窗口之上", value: $model.pinned)
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("精简模式显示行数").font(.system(size: 13, weight: .medium))
                            Text("1–6 行；直播包含比分行，社区显示对应条数（另加工具栏）。")
                                .font(.system(size: 12)).foregroundStyle(p.secondary)
                        }
                        Spacer()
                        Picker("精简模式显示行数", selection: $model.compactRows) {
                            ForEach(1...6, id: \.self) { count in Text("\(count) 行").tag(count) }
                        }.labelsHidden().fixedSize()
                    }
                    settingToggle("单行只看比分", detail: "显示 1 行时省略文字解说", value: $model.scoreOnly)
                    settingToggle("菜单栏显示比分", detail: "窗口隐藏后也能看一眼", value: $model.menuScore)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text("安静地看一场球。").font(.system(size: 14, weight: .medium))
                    Text("余光 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0") · NBA 文字直播\n无声音、无推送、不抢输入焦点。\n数据由虎扑提供，可能存在延迟。")
                        .font(.system(size: 12)).lineSpacing(4).foregroundStyle(p.secondary)
                }.padding(.top, 4)
            }.padding(20)
        }
    }
    private var favoriteTeamSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("我的主队").font(.system(size: 13, weight: .medium))
                    Text(model.favoriteTeams.isEmpty ? "添加主队 · 支持多选" : "已选 \(model.favoriteTeams.count) 支 · 点击更改")
                        .font(.system(size: 12)).foregroundStyle(p.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(action: model.beginTeamSelection) {
                    HStack(spacing: 4) {
                        ForEach(Array(model.favoriteTeams.sorted().prefix(4)), id: \.self) { team in
                            TeamBadge(name: team, size: 24)
                                .frame(width: 30, height: 30)
                                .background(p.sheet, in: Circle())
                        }
                        if model.favoriteTeams.count > 4 {
                            Text("+\(model.favoriteTeams.count - 4)")
                                .font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(p.secondary)
                        }
                        Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                            .foregroundStyle(p.secondary).frame(width: 28, height: 28)
                            .background(p.raised.opacity(0.6), in: Circle())
                            .overlay(Circle().strokeBorder(p.edge, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    }.padding(.vertical, 3).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .help(model.favoriteTeams.isEmpty ? "添加我的主队" : model.favoriteTeams.sorted().joined(separator: "、") + " · 点击添加或更改")
                    .accessibilityLabel(model.favoriteTeams.isEmpty ? "添加主队" : "更改我的主队：" + model.favoriteTeams.sorted().joined(separator: "、"))
            }
            settingToggle("篮球资讯只看主队", detail: "默认开启；匹配所选球队的资讯标题和正文。", value: $model.onlyFavoriteNews)
        }
    }
    private func settingToggle(_ title: String, detail: String, value: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(p.secondary)
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }.frame(maxWidth: .infinity)
    }
    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 12)).frame(width: 24, height: 26).contentShape(Rectangle()) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
    private func emptyState(_ title: String, description: String, loading: Bool = false) -> some View {
        VStack(spacing: 12) {
            if loading { ProgressView().controlSize(.small) }
            Text(title).font(.system(size: 15, weight: .medium))
            Text(description).font(.system(size: 12)).foregroundStyle(p.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
    }
    private func errorBlock(_ message: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
            Text(message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("重试", action: action).buttonStyle(.plain).font(.system(size: 12, weight: .medium))
        }.padding(12).background(p.raised, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct DragArea: NSViewRepresentable {
    var doubleClick: (() -> Void)? = nil
    func makeNSView(context: Context) -> DragView { let view = DragView(); view.doubleClick = doubleClick; return view }
    func updateNSView(_ nsView: DragView, context: Context) { nsView.doubleClick = doubleClick }
}

final class DragView: NSView {
    var doubleClick: (() -> Void)?
    private var dragAnchor: NSPoint?
    private var initialFrame: NSRect?
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let doubleClick { doubleClick(); return }
        guard let window else { return }
        dragAnchor = window.convertPoint(toScreen: event.locationInWindow)
        initialFrame = window.frame
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragAnchor, let initialFrame else { return }
        let location = window.convertPoint(toScreen: event.locationInWindow)
        window.setFrameOrigin(NSPoint(x: initialFrame.minX + location.x - dragAnchor.x,
                                      y: initialFrame.minY + location.y - dragAnchor.y))
    }
    override func mouseUp(with event: NSEvent) {
        dragAnchor = nil; initialFrame = nil
        guard let window else { return }
        guard let screen = window.screen else { return }
        let visible = screen.visibleFrame
        var frame = window.frame
        if abs(frame.minX - visible.minX) < 14 { frame.origin.x = visible.minX + 8 }
        if abs(frame.maxX - visible.maxX) < 14 { frame.origin.x = visible.maxX - frame.width - 8 }
        if abs(frame.minY - visible.minY) < 14 { frame.origin.y = visible.minY + 8 }
        if abs(frame.maxY - visible.maxY) < 14 { frame.origin.y = visible.maxY - frame.height - 8 }
        window.setFrame(frame, display: true)
    }
}

private struct ScrollObserver: NSViewRepresentable {
    let action: () -> Void
    func makeNSView(context: Context) -> ObserverView { let v = ObserverView(); v.action = action; return v }
    func updateNSView(_ view: ObserverView, context: Context) { view.action = action }
    static func dismantleNSView(_ view: ObserverView, coordinator: ()) { view.stopObserving() }
}
private struct CompactWheelObserver: NSViewRepresentable {
    let action: (Double) -> Void
    func makeNSView(context: Context) -> ObserverView { let view = ObserverView(); view.stepAction = action; return view }
    func updateNSView(_ view: ObserverView, context: Context) { view.stepAction = action }
    static func dismantleNSView(_ view: ObserverView, coordinator: ()) { view.stopObserving() }
}
private final class ObserverView: NSView {
    var action: (() -> Void)?
    var stepAction: ((Double) -> Void)?
    private var monitor: Any?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.window === self.window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return false }
                if let stepAction = self.stepAction {
                    // AppKit reports downward wheel/trackpad motion as negative Y.
                    let distance = -Double(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 1 : 32)
                    if distance != 0 { stepAction(max(-96, min(96, distance))) }
                    return true
                }
                if abs(event.scrollingDeltaY) > 0.1 { self.action?() }
                return false
            }
            return consumed ? nil : event
        }
    }
    func stopObserving() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
}
private extension View {
    func onScrollWheel(_ action: @escaping () -> Void) -> some View { background(ScrollObserver(action: action)) }
}
