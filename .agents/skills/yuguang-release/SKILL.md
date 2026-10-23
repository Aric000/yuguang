---
name: yuguang-release
description: 审查余光 Yuguang 项目改动、执行原生客户端验证、提交推送，并在用户要求发版时发布 GitHub Release、核实安装包和校验文件。仅适用于本仓库的 review、提交或发布请求。
---

# 余光审查与发版

从仓库根目录执行。以当前 `origin`、工作流和用户本次要求为准；仓库通常为 `Aric000/yuguang`。这是一个仓库内两套原生客户端：Mac 为 SwiftUI/AppKit，Windows 为 WPF/.NET。不要把只在 Mac 实现的功能写成双端已支持。

## 确定范围与审查

- 先查看 `git status -sb`、`git diff`、未跟踪文件、远端主分支、标签和现有 Release。保留任务外改动；不要直接 `git add .` 或强推。
- 用户只要求 review 时止于审查；只要求提交时不要自动发布。明确要求“review + 提交 + release”时，修复、验证、提交、发布均已授权，不重复索要确认。
- 按真实触发条件审查异步请求失效保护、分页去重、筛选空批次、滚动位置、原生窗口拖动与隐藏、偏好保存及外部 HTML。修复可确认的问题，并补充能复现问题的检查。不要仅根据已有测试通过就认定滚动正常。
- 社区当前读取公开 SSR 页面，没有稳定的官方开放 API。主队新闻按标题与正文中的球队名匹配；回复/评论排序仅针对已加载数据，说明中保留这一边界。

## 本地验证与打包

读取 `scripts/` 和 `.github/workflows/` 中当前入口，不复制过时构建逻辑。Mac 发布通常运行：

```sh
bash scripts/test-macos.sh
bash scripts/build-macos.sh X.Y.Z
apps/macos/dist/余光.app/Contents/MacOS/Yuguang --check-forum-model
apps/macos/dist/余光.app/Contents/MacOS/Yuguang --demo --self-test
```

原生窗口检查需要退出另一份正在运行的余光以释放全局快捷键；测试结束恢复用户偏好。CLI 流程用 `set -e`，防止构建失败后误用旧二进制继续验证。

涉及社区加载或外观时，运行 `--forum-capture /tmp/<task-specific-directory>`：核实连续三次滚到底部确实进入下一页、详情返回保持位置、主队弹窗可显示，并查看实际截图。捕获日志出现 `FAIL` 或页码不增长时继续修复。`--check-forum` 可抽查真实数据，但不作为 CI 必须通过的联网测试。

Windows 核心可在 Mac 上跑 `dotnet run --project apps/windows/Yuguang.Tests`；WPF 窗口、安装和卸载验证由 Windows runner 执行。没有跑过的验证不写成已通过。

## 版本、文档与提交

- 依据现有标签选择未占用的 `vX.Y.Z`；新增功能通常升级次版本。所有打包命令、默认版本、CI 示例、README 和发布标题保持一致。
- 更新 README 的功能范围、入口与已知限制，写面向使用者的中文发布说明。签名/公证状态必须据实说明。
- `git diff --check` 后精确暂存已审查文件，提交并推送。推送前重新核对远端；远端改变时整合后重新验证，不覆盖他人提交。
- 优先使用已有 Git/GitHub 工具。GitHub 连接器可创建 tree、commit 和更新分支；如果 Git 命令没有凭据，可使用这些受权 API。随后 fetch 同步本地到相同提交，核实工作区干净。不要把令牌写入仓库、脚本或输出。

## 发布与核实

查看当前 `release.yml`。目前通过 `release: published` 触发 Mac/Windows 打包和附件上传：仅推标签或保存草稿不会触发它。

1. 提交推送后先确认目标提交的 Build 工作流成功。出现失败时读取对应 job 日志，修复后重跑受影响验证。
2. 使用 GitHub 工具或已登录的 GitHub Release 页面，创建指向**已验证提交**的新标签和正式 Release。优先绑定已有精确标签；若从 main 创建标签，发布前再次确认 main SHA 没有变化。不要重用或移动已发布标签。
3. GitHub 连接器可能只提供 Release 读取能力。缺少写接口时可使用本机已登录浏览器；远程浏览器未登录不等于本机未登录。不要提取浏览器 Cookie/令牌。若确实需要登录，由用户完成必要的登录步骤，保留可审阅的发布说明。
4. 跟踪 `Release native clients` 到结束。不要把“创建了 Release”当成“安装包已发布”。允许在确认暂态错误后重试失败 job；若发现产品错误或标签需改变，停止覆盖旧标签并说明应发修订版本。
5. 用下面的只读脚本验证标签 SHA、发版工作流、六个安装/校验附件及其 SHA-256 一致性：

```sh
python3 .agents/skills/yuguang-release/scripts/verify_release.py \
  --repo Aric000/yuguang --tag vX.Y.Z --commit <verified-commit-sha>
```

脚本退出码 2 表示工作流或附件仍未齐备，1 表示验证失败，0 才可报告完成。API 受限时用 GitHub 连接器读取同样信息，不伪造成功状态。

最终给出：审查结论、重要修复、实际验证结果、提交 SHA、Release 链接和安装包状态。若有阻塞，明确停在哪一步。提及本 skill 的调用方式 `$yuguang-release`。
