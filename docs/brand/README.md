# 余光 Logo 候选

四款为原创矢量几何，不使用第三方品牌标记作为应用 Logo。SVG、原生界面和对比图共用 `Sources/Yuguang/BrandGeometry.swift`，避免导出与实装走样。

- **A 空心入网**：最直观的篮球落筐，球缝和收拢的网形成篮球识别。
- **B 余光之眼**：眼睛轮廓与篮筐结合，圆形同时读作瞳孔与篮球，更呼应产品名。
- **C Y 形球网**：Yuguang 首字母与球网的 Y，几何最少，适合菜单栏与小尺寸。
- **D 一线入框**：单行窗口的轮廓接住篮球，呼应软件由窗口变成一行。

用户已选定 **B「余光之眼」**。窗口标题、正式 AppIcon、菜单栏均统一使用 B，候选 SVG 留存为设计历史。菜单栏采用单色 template 图，随系统深浅色自动适配；应用图标保留橙色篮球与深色底。

再生成：

```sh
swiftc Sources/Yuguang/BrandGeometry.swift scripts/render-brand.swift -o /tmp/yuguang-brand-board
/tmp/yuguang-brand-board "$PWD/docs/brand"
```

`logo-options.png` 为对比图，四个 SVG 为独立可编辑文件。四款均展示彩色、反白和小尺寸单色效果。
