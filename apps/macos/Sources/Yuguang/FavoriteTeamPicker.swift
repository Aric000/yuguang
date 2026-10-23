import SwiftUI

/// Keep selection local to the sheet until Done, so checking multiple teams only refreshes news once.
struct FavoriteTeamPicker: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var scheme
    private var teams: [String] {
        TeamAssets.catalog.keys.sorted().filter {
            model.favoriteTeamSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            $0.localizedStandardContains(model.favoriteTeamSearch.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("选择我的主队").font(.system(size: 20, weight: .semibold))
                    Text("支持多选，完成后统一保存。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("清空") { model.favoriteTeamDraft = [] }
                    .buttonStyle(.plain).font(.system(size: 12)).disabled(model.favoriteTeamDraft.isEmpty)
            }
            TextField("搜索球队", text: $model.favoriteTeamSearch)
                .textFieldStyle(.roundedBorder).font(.system(size: 13))
                .accessibilityLabel("搜索主队")
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(teams, id: \.self) { team in
                        let selected = model.favoriteTeamDraft.contains(team)
                        Button { model.toggleDraftTeam(team) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected ? Color.orange : Color.secondary)
                                Text(team).lineLimit(1)
                                Spacer(minLength: 0)
                            }.font(.system(size: 12)).padding(.horizontal, 9).frame(height: 34)
                                .background(selected ? Color.orange.opacity(0.12) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).accessibilityLabel("\(team) · \(selected ? "已选择" : "未选择")")
                    }
                }.padding(.vertical, 2)
                if teams.isEmpty {
                    Text("未找到球队").font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 24)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Text("已选 \(model.favoriteTeamDraft.count) 支").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("取消", action: model.cancelTeamSelection).keyboardShortcut(.cancelAction)
                Button("完成", action: model.saveTeamSelection).keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent).tint(Color(red: 0.95, green: 0.41, blue: 0.19))
            }.controlSize(.regular)
        }.padding(20).frame(width: 384, height: 480)
            .background(Color(white: scheme == .dark ? 0.105 : 0.98))
            .preferredColorScheme(model.colorScheme)
    }
}
