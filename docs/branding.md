# 品牌与界面资源

QuotaMate 的应用图标采用蓝色圆角底、米白沙漏和青色余量。图标及账号卡片的浅色 / 深色弧面背景为本项目使用 ImageGen 生成并选用的位图；文字、图标控件、数值、圆环和交互由 Flutter 实现。

- 图标母版：[quotamate-hourglass-master.png](../assets/branding/quotamate-hourglass-master.png)
- 运行资源位于 [assets/branding](../assets/branding)，导出尺寸和 SHA256 见 [资源清单](../assets/branding/export-manifest.json)。
- `python3 scripts/make_app_icon.py` 使用 macOS 的 `sips` 从母版导出 macOS 图标和 Windows ICO，不需要重新生成图片。
- 界面预览见 [screenshots/preview](../screenshots/preview)，均由生产组件使用合成账号及统计数据渲染。

本项目资源随仓库 MIT 许可分发；第三方图标和依赖继续遵守各自许可证，见 [第三方声明](../THIRD_PARTY_NOTICES.md)。设计迭代、聊天附件和历史验收截图不包含在公开仓库。

界面风格参考 FlClash，但没有引入其代理内核或界面源码。QuotaMate 是独立项目，与 FlClash、OpenAI、Anthropic 均无官方隶属或背书关系。
