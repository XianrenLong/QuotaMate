# 参与贡献

欢迎提交问题、文档改进和 Pull Request。当前提供 macOS 与 Windows x64 Alpha；Windows 的构建、测试和兼容范围见 [Windows 指南](docs/windows.md)。

## 本机开发

基准环境：Flutter 3.47.7（Dart 3.13.5）、macOS、Xcode 和 Python 3。应用运行不依赖 Python；它只用于开发和打包检查。

```sh
flutter pub get --enforce-lockfile
flutter run -d macos
```

真实连接需要自行安装 Codex 或 Claude Code。普通单元和界面测试使用临时目录及模拟数据，无需登录模型账号。不要在 CI 中运行 `tool/connection_check.dart`、`tool/claude_connection_check.dart` 或 `tool/timing_check.dart`，它们用于用户主动发起的本机诊断。

## 提交前验证

```sh
dart format --output=none --set-exit-if-changed lib test tool
dart analyze
flutter test
python3 -m unittest discover -s scripts -p 'test_*.py'
python3 scripts/check_public_files.py
```

公开文件检查读取 Git 索引。先暂存计划公开的文件再执行检查；检查结果不会打印匹配到的密钥内容。

原生状态栏采集器需要额外编译并测试：

```sh
mkdir -p build
xcrun swiftc -O scripts/claude_statusline.swift -o build/quotamate-claude-statusline
python3 scripts/test_claude_statusline.py build/quotamate-claude-statusline
```

Python 测试发现命令会跳过未提供可执行文件的原生采集器测试；上面的独立命令和 CI 会实际运行这些测试。提交 `pubspec.lock`，避免同时混入无关的依赖升级。

## 数据与测试样本

- 日志解析只保留统计所需元数据，不把对话正文、工具参数、附件或凭证写入数据库和解析状态。
- 使用临时目录构造合成样本；不要提交真实 JSONL、数据库、邮箱、项目路径或完整诊断导出。
- 本地日志与当前登录身份分别展示，不能推断历史记录必然属于当前账号。
- 缺失额度、价格和计时保持未知；估算必须说明口径，不能冒充账单或实时读数。
- 不添加令牌导出、复用凭证代理模型请求、自动轮换账号绕过限制的功能。本机订阅日期解析只能提取必要日期与身份校验字段，不得保存、日志输出或上传原始凭证。Claude 保持本地被动采集；接入新能力需附官方接口依据并说明授权边界。

## Pull Request

描述具体问题、最终行为和验证结果。界面变化请附合成数据截图，并检查中英文、浅色/深色以及紧凑窗口。新增依赖或引入参考代码时说明用途、来源和许可证。

安全问题通过 [私密漏洞报告](https://github.com/XianrenLong/QuotaMate/security/advisories/new) 联系维护者，不要创建包含真实凭证的公开 Issue。详情见 [SECURITY.md](SECURITY.md)。

## 主分支保护

`main` 要求通过 Pull Request 合并，禁止删除与强制推送，且 macOS / Windows 两个 CI 检查均须成功、分支须与主分支保持同步。规则也适用于管理员。个人项目不强制其他人的审批，避免维护者无法自行合并；依赖的大版本更新仍应逐项审阅并回归验证。
