# 双原生客户端

余光在一个 Git 仓库中维护两个原生客户端。macOS 的系统字体和 SwiftUI 排版是产品体验的一部分，Windows 也使用自身的原生文字与窗口技术。

| 内容 | macOS | Windows |
| --- | --- | --- |
| 界面与窗口 | SwiftUI、AppKit | C#、WPF |
| 菜单与快捷键 | NSStatusItem、Carbon | NotifyIcon、RegisterHotKey |
| 网络 | URLSession | HttpClient |
| 字体 | macOS 系统字体 | Segoe UI / Microsoft YaHei UI |
| 数据逻辑 | YuguangCore | Yuguang.Core |
| 安装包 | DMG、ZIP | 自包含单文件 EXE、Inno Setup |

接口调用规范、球队颜色目录、球队图标与品牌资源共用；本次不在 Swift 与 C# 之间增加 Rust/C++ 桥接层。两个客户端各自实现相同的数据契约与行为，避免为当前规模引入运行时桥接的复杂度。

`shared/assets` 是资源唯一来源，Mac 构建前复制资源，Windows 编译时嵌入。Mac 保持原应用标识及 UserDefaults；Windows 偏好位于 `%LOCALAPPDATA%/Yuguang/settings.json`。迁移用的 Electron 原型保留在本地 `codex/electron-prototype` 分支，生产主线不再依赖 Node 或浏览器运行时。

比赛请求使用取消令牌及选择代次校验，过期结果不能覆盖新选择。比分与文字刷新失败独立记录；已显示文字保留，错误后重试并重新获取直播 key。单条 ID 保持十进制字符串，避免大整数精度丢失；比分按客队、主队排序，缺失分数以破折号呈现。

Windows 的透明窗口使用 WPF 逻辑单位；鼠标命中使用同一设备像素坐标系的 GetCursorPos / GetWindowRect。精简窗口不受标准标题栏最小高度限制。快捷键重新注册成功后才释放旧键，冲突时保持原绑定。

## 验证范围

Mac：Swift 核心测试、原生窗口诊断、实际本机启动与打包签名校验。

Windows：C# 核心检查（可在 Mac 执行）、交叉编译、GitHub Windows Runner 的 WPF 窗口与资源诊断、便携版及安装包构建。自动诊断不等同于真实多显示器、多 DPI 与不同 Windows 主题的完整人工验收。
