# 夜间模式

在「设置 → 外观与语言 → 主题模式」选择 **浅色 / 深色 / 跟随系统**，即时生效并保存。旧版没有该偏好时默认浅色，已有数据、语言、所选账号、当前筛选周期和价格保持不变。每次启动仍按既有规则默认显示今日统计。

深色沿用当前窗口的灰紫/蓝色设计语言：底色 #161821、侧栏 #1D1F2B、卡片 #252836，主文字 #F0F1F8、次要文字 #ABB0C4，图表和链接使用较柔和的蓝色。主操作使用深蓝底白字；订阅等级继续保留灰、蓝、金三种语义，并适配深色底。

## 实现

- `lib/data/appearance.dart` 定义 light / dark / system；偏好保存在本地 preferences.appearance。切换不调用 Codex，也不会使用额度重置权益。
- `lib/ui/palette.dart` 提供 ThemeExtension 配色，通过上下文解析原有颜色角色并插值过渡；不使用全局可变颜色状态。五个页面、导航、表格、图表、空状态、弹窗、按钮和标签按当前主题渲染。
- 深色账号底图使用 `assets/branding/account-card-soft-curve-dark.png`。它只包含弧面背景；数据、文字、圆环和操作仍为真实 Flutter 控件。
- macOS 通过 setAppearance 设置 Aqua / Dark Aqua / 继承系统，原生文件面板等跟随应用外观；Flutter 的 system 模式响应系统亮度变化。Windows 当前仍为工程脚手架，不能据此声称完成原生 Windows 桥接。
- 浅色配色保留已有外观；深色模式降低大面积亮度，提高文字与卡片对比。测试要求正文/卡片对比大于 7、次要文字大于 4.5、主要操作白字/按钮底色至少 4.5。

## 验证与截图

验证包括主题和语言独立保存、重启恢复、切换不改动数据/筛选、两种语言下的五页大小窗口、暗色弹窗、缺少浅色背景残留，以及跟随系统时动态切换亮度。渲染使用独立样例数据，不读取真实账号，不消耗重置机会。

生产 Flutter 组件示例预览：[深色统计](../screenshots/preview/statistics-gpt-dark-zh.png)、[浅色 Claude 总览](../screenshots/preview/overview-claude-light-zh.png)、[深色设置](../screenshots/preview/settings-claude-dark-zh.png)。均使用合成账号及虚构目录；不是运行中原生窗口的手工操作截图。

资源来源见 [品牌资源](branding.md)。
