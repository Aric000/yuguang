<div align="center">

<img src="docs/brand/B-余光之眼.svg" width="104" alt="余光之眼" />

# 余光 · Yuguang

### 让比赛留在余光里，让灵感留在屏幕上。

**使用余光关注比赛，一边用 AI 编程，一边观看比赛。**

Mac / Windows NBA 文字直播助手 · 轻盈悬浮 · 透明文字 · 一键隐现

[下载安装](https://github.com/Aric000/yuguang/releases/latest) · [开始使用](#开始使用) · [本地开发](#本地开发)

</div>

余光诞生于一个很日常的瞬间：AI 正在生成代码，比赛恰好打到关键回合。你想知道发生了什么，却不想把整个桌面交给直播。

于是，我们把球场收进一小行文字里。它可以安静地停在编辑器旁，也可以展开成一扇完整的赛事窗口。在代码、思考与比赛之间，留一点恰到好处的余地。

从 **v0.2.0** 起，Mac 和 Windows 共用同一套 Electron + React + TypeScript 代码：相同的界面、赛事逻辑和交互，由各平台构建安装包。

## 为专注而设计

| 特点 | 体验 |
| --- | --- |
| **一行，也可以更多** | 精简视图支持 1–6 行，包含比分行；多行显示最新解说，按你的桌面空间取舍。 |
| **移开鼠标，只留文字** | 自动隐去精简窗口的底色、阴影和按钮；移入恢复操作，文字位置保持不变。 |
| **一键隐现** | 默认 Control + 反引号全局隐藏，再按恢复；快捷键可在设置中录制。 |
| **切换比赛，保持轻盈** | 精简视图右上角直接切换比赛、选择日期，无需展开窗口。 |
| **展开，认真看球** | 完整比分、30 支球队的队徽、球队配色和文字时间线，支持雾白、炭黑和系统主题。 |
| **你的球队，优先出现** | 按球队筛选、星标关注，关注球队的比赛优先展示。 |
| **纯文字的克制** | 启用简洁模式后不显示球队 Logo，记住偏好，下次启动继续使用。 |
| **桌面上的一瞥** | Mac 菜单栏 / Windows 系统托盘入口，菜单首行展示比分与状态；Mac 可显示菜单栏比分。 |

没有声音和通知，没有账号注册，也不因比分更新弹出窗口。比赛在继续，你也可以继续手上的事情。

## 界面预览

<table><tr>
<td align="center"><img src="docs/screenshots/live-light.png" width="360" alt="雾白主题完整赛事窗口" /><br/>雾白 · 完整赛事窗口</td>
<td align="center"><img src="docs/screenshots/live-dark.png" width="360" alt="炭黑主题完整赛事窗口" /><br/>炭黑 · 夜间阅读</td>
</tr></table>

**收起窗口，把比赛放在余光里。**

![精简视图](docs/screenshots/compact.png)

**需要更多上下文时，多留几行。**

![多行视图](docs/screenshots/compact-multiline.png)

截图来自应用演示模式，比分和文字为示例数据；正常启动使用实际赛事接口，不回退到假数据。

## 下载安装

前往 [GitHub Releases](https://github.com/Aric000/yuguang/releases/latest)，选择对应安装包：

| 系统 | 文件 | 安装方式 |
| --- | --- | --- |
| macOS 14+，Apple Silicon | `Yuguang-版本-mac-arm64.dmg` | 打开后拖到 Applications |
| macOS 14+，Apple Silicon | `Yuguang-版本-mac-arm64.zip` | 解压后运行 |
| Windows 10 / 11，64 位 | `Yuguang-版本-windows-x64-setup.exe` | 运行安装向导，支持选择安装目录 |
| Windows 10 / 11，64 位 | `Yuguang-版本-windows-x64-portable.exe` | 免安装运行 |

当前发布流程提供 Apple Silicon 和 Windows x64 安装包；Intel Mac 可在对应机器使用同一源码构建。Linux 暂未列入支持范围。

安装包尚未配置付费发行证书：Mac 使用 ad-hoc 签名、未经过 Apple 公证；Windows 未使用 Authenticode 签名。首次运行可能出现系统验证提示。确认安装包来自本仓库后，Mac 可在「系统设置 → 隐私与安全性」中选择「仍要打开」。

## 开始使用

1. 在赛程中选择日期、球队，点击比赛进入文字直播。
2. 拖动窗口顶部 Logo、标题或空白移动完整窗口，右上角收起按钮进入精简视图。
3. 精简视图文字和空白处均可拖动，双击展开。右下角 / 精简视图右边缘可拖动调整大小。
4. 移开鼠标后，精简视图只保留文字。移回窗口，点击右上角双向箭头切换比赛。
5. 按 **Control + 反引号（⌃ + &#96;）** 隐藏 / 恢复。关闭按钮只隐藏，退出请使用菜单栏 / 托盘「退出余光」。

通过菜单栏、托盘或 Mac `⌘ ,` / Windows `Ctrl+,` 打开设置，调整主题、置顶、显示行数和快捷键。Windows 托盘图标可能被系统收进隐藏区域，可点击任务栏的小箭头查看。

「启用简洁模式」立即进入精简视图并保存启动偏好；临时展开不关闭该偏好，完整窗口和赛程也省略队徽。关闭开关后恢复完整窗口与队徽。

滚动解说或点「阅读历史」暂停跟随，点「回到最新」恢复。隐藏窗口后仍更新当前比赛。

Mac 升级自原生 v0.1.x 时，首次启动尝试导入原有主题、行数、关注球队等偏好；自定义快捷键和窗口位置需重新设置。

## 本地开发

需要 Node.js 24+ 与 npm。Mac 和 Windows 使用相同命令：

```sh
git clone https://github.com/Aric000/yuguang.git
cd yuguang
npm ci
npm start
```

```sh
npm test                 # 数据 / 轮询 / 几何与 React 界面测试
npm run check-api        # 实际验证四个赛事接口
npm run desktop-check    # 演示模式下验证原生窗口与托盘；先退出已有余光以释放快捷键
npm run pack             # 生成当前平台的应用目录
npm run dist             # 生成当前平台安装包，位于 release/
```

开发浏览器预览：`npm run dev`，访问 `http://127.0.0.1:5173/?demo=1`。仅显式演示模式使用示例数据，浏览器不具备托盘、透明窗口和全局快捷键。

```sh
# 实际 Electron 窗口截图，演示数据，不改动正式偏好
npx electron . --demo --capture "$PWD/docs/screenshots"
```

安装时首次运行 Electron CLI 会下载运行时；网络受限可按 Electron 官方下载说明配置镜像。本地安装包体积比旧 Swift 原生版更大，换来两个平台共用界面与业务逻辑。

## 自动构建与发布

`Build desktop` 在主分支提交或 PR 时分别运行 Mac / Windows 测试、桌面自检和打包，安装包可从运行记录的 Artifacts 下载。

正式发布：在 [Releases](https://github.com/Aric000/yuguang/releases) 创建新版本，例如 `v0.2.0`，Target 选择 `main`，点击 **Publish release**。`Release desktop` 会同步应用内部版本，分别构建 DMG、ZIP、Windows 安装版与免安装版，并将安装包和 SHA-256 校验文件上传到该版本 Assets。无需在 Mac 上交叉编译 Windows。

旧的 Swift 原生实现保留在 Git 标签 [`v0.1.1`](https://github.com/Aric000/yuguang/tree/v0.1.1) 中，当前主分支只维护跨平台实现。

## 项目结构

| 目录 | 职责 |
| --- | --- |
| `desktop/core.cjs` | 接口、精确 ID 解析、状态与轮询、消息去重 |
| `desktop/main.cjs` | 窗口、托盘、快捷键、持久化与受限 IPC |
| `desktop/preload.cjs` | 隔离渲染进程的最小通信接口 |
| `src` | 共用 React + TypeScript 界面与样式 |
| `public/teams` | 30 队本地队徽与来源、配色目录 |
| `tests` | 业务和 React 回归测试 |
| `.github/workflows` | 双平台构建与 Release 自动上传 |

## 数据与隐私

数据来自虎扑相关赛事接口，可能有延迟；比分和文字独立更新，可能短暂不同步。错误时保留最近成功内容并显示提示。消息按服务端顺序去重，每次会话最多保留 500 条，不承诺补全整场历史。第三方接口可能变化，当前仅接入 NBA 文字直播。

偏好保存在本机 `preferences.json`，不包含账号或凭据。Mac 位于 `~/Library/Application Support/余光/`，Windows 位于 `%APPDATA%/余光/`。无内置分析统计，不上传偏好。网络请求在桌面主进程中完成，渲染进程启用沙箱、上下文隔离且禁用 Node 集成，远程直播内容只按纯文字显示。

接口细节见 [数据接入说明](docs/API.md)，迁移和验证记录见 [跨平台迁移记录](docs/CROSS_PLATFORM.md)。

## 致谢

感谢 [hupumoyu-assistant](https://github.com/chenyaoyi88/hupumoyu-assistant) 提供接口调用思路。余光独立实现客户端与视觉设计。

「余光之眼」将眼睛、篮球与篮筐融为一个标志。球队队徽和标识的权利归各自权利人；本项目与 NBA、各球队及虎扑无官方隶属关系。

---

<div align="center">安静地看一场球。<br/>Build with AI. Follow with Yuguang.</div>
