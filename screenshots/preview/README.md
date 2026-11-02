# 公开预览图

这些图片通过 `tool/render_account_card_test.dart` 渲染生产 Flutter 组件生成，只使用 `alex@example.com`、`/sample/codex`、`/sample/claude` 和人工构造的七天 Token / 额度样本。

不读取真实账号或日志，不包含真实邮箱、个人目录或系统字体文件。使用本机字体仅用于渲染，不随仓库分发字体。图片不是原生窗口手工操作截图，不能作为真实账号连接情况的证明。

验证和生成方式：设置 `QUOTA_QA_CJK_FONT` 指向本机中文字体文件，再运行 `flutter test tool/render_account_card_test.dart`。工具输出到被 Git 忽略的版本截图目录；公开前只选择所需图片复制到本目录并逐张检查。

生成版本：0.1.24 Alpha。界面预览使用近 7 天范围以展示趋势；应用启动默认仍是今日。Claude 不支持的计时字段在预览中也保持未知。
