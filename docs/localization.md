# 中英切换与应用名称

应用名称统一为 **QuotaMate**，不随界面语言改变。Flutter 自绘标题栏使用 AppInfo.name，macOS 窗口及 CFBundleDisplayName、DMG 安装卷均使用 QuotaMate；Windows 工程的窗口标题和产品显示信息同步统一，原生 Windows 功能仍为后续范围。

在「设置 → 外观与语言 → 界面语言」选择「简体中文 / English」，无需重启即可更新。选择写入本地 preferences.language（zh / en），下次启动恢复；旧配置没有该字段时保持简体中文。切换语言不改变当前账号、筛选周期、价格或统计数据，启动仍默认显示今日统计。

## 覆盖范围

- 导航、总览、账号、统计、提醒和设置页，含字段、状态、提示、表头、空状态、表单校验与应用对话框。
- macOS 菜单栏菜单、提示、应用提供的文件选择提示与新通知；操作系统自己提供的系统控件仍按系统规则显示。
- 新导出 CSV 的文件名、表头与是/否字段。原有导出文件不会被改写。
- 英文紧凑数量使用 K / M / B，中文保留万 / 亿；时间间隔按语言显示。
- 邮箱、日志中的模型名、项目名和本地路径作为用户数据原样显示，不通过文案词典翻译。短按钮在英文中采用适合空间的表述，完整操作含义保留在 Tooltip。

## 实现与维护

- `lib/l10n/strings.dart` 集中管理中英资源，中文作为现有文案的稳定键。动态文案使用命名占位符模板，按固定文本的长度优先匹配，先处理具体模板再处理通用时间/状态模板。
- `lib/ui/localized.dart` 的 AppLocale 通过 InheritedWidget 提供当前语言，LocalizedText / LocalizedTooltip 及公共 label 根据该上下文渲染。用户数据应使用 localize: false；带原始数据的表单及表格保持数据不变。
- 直接返回字符串的表单校验、图表提示、原生菜单/通知与导出使用同一个 AppStrings；标准 Material 控件接入 Flutter 官方 flutter_localizations（zh_CN / en_US）。
- 语言仅属于展示偏好，不写入 Codex 配置、凭证或会话日志。退出“添加模型价格”对话框时，等待路由过渡结束后再释放文本控制器，避免界面刷新访问已释放控制器。

## 验证与预览

- 单元测试覆盖动态状态、时间间隔、数值单位、语言持久化、CSV 本地化与原始模型名保留。
- 界面测试在 1320 × 850、1000 × 720 下从设置实际切换语言，检查全部页面和提示未翻译文本、布局溢出、英文表单校验、保存和数据来源对话框，并验证与 UI 文案重名的真实模型/项目（“模型”“设置”）不会被翻译。
- 生产 Flutter 组件样例预览：[中文统计](../screenshots/preview/statistics-gpt-dark-zh.png)、[中文设置](../screenshots/preview/settings-claude-dark-zh.png)、[英文统计](../screenshots/preview/statistics-claude-dark-en.png)、[英文设置](../screenshots/preview/settings-claude-dark-en.png)。这些预览只使用合成账号、虚构目录和假数据，不是运行中原生窗口的手工操作截图。
