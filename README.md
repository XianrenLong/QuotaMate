# QuotaMate

[![CI](https://github.com/liuzilong200049-bot/QuotaMate/actions/workflows/ci.yml/badge.svg)](https://github.com/liuzilong200049-bot/QuotaMate/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[English](README.en.md) · [下载与版本说明](https://github.com/liuzilong200049-bot/QuotaMate/releases) · [问题反馈](https://github.com/liuzilong200049-bot/QuotaMate/issues)

本地优先的 AI 额度与用量管理工具，当前为 **macOS Alpha**。分别查看 GPT / Codex 与 Claude 的账号信息、本机用量和参考成本，帮助理解额度使用情况。

QuotaMate 是独立社区项目，与 OpenAI、Anthropic、FlClash 无官方隶属或背书关系。

![统计页：合成数据预览](screenshots/preview/statistics-gpt-dark-zh.png)

## 支持范围

| 能力 | GPT / Codex | Claude |
| --- | --- | --- |
| 本机用量明细与项目汇总 | 读取 Codex 本机日志 | 读取 Claude Code 终端日志 |
| 订阅额度 | 通过用户安装的官方 Codex App Server 查询 | 仅读取已有状态栏或匹配账号的桌面本地快照 |
| 账号信息 | 核对所选 Codex 配置目录的登录 | 核对官方 Claude Code 的本机登录状态 |
| 额度重置 | 用户有可用权益时手动点击 | 不提供 |
| 普通网页聊天的完整 Token 明细 | 不提供 | 不提供 |

**平台：** macOS 提供开发测试包，支持 Apple Silicon 和 Intel。Windows 只有工程脚手架，原生桥接及打包未完成；暂无 Windows 或 Linux 可用发行版。

Claude 不主动轮询订阅额度接口，不提取订阅令牌或代理模型请求。启用状态栏采集后，快照随正常 Claude Code 终端使用产生；刷新不会凭空补齐历史。桌面 Code、Cowork、远程任务及其他设备记录尚未完整覆盖。详见 [Claude 连接说明](docs/claude-connection.md)。

## 功能

- 默认打开今日统计，可切换近 7 天 / 近 30 天；两平台数据与选择独立保存。
- 用量明细显示模型、输入、输出、缓存、参考成本和可用计时字段，支持项目汇总与 CSV 导出。
- 中英文界面，浅色、深色及跟随系统主题，macOS 菜单栏和可选低额度提醒。
- 手动配置模型价格；费用和部分计时为参考估算，缺失字段保持未知。
- 快照保留来源和采集时间，过期数据不冒充实时额度；历史记录不强行归属到当前账号。

![Claude 总览：合成数据预览](screenshots/preview/overview-claude-light-zh.png)

所有预览图均由生产 Flutter 组件使用合成账号、虚构路径和假数据生成，不包含真实账号或会话。它们是组件渲染预览，不是安装版原生窗口的手工操作截图。

## 安装与使用

从 [Releases](https://github.com/liuzilong200049-bot/QuotaMate/releases) 下载最新 macOS Alpha 包，退出旧版后覆盖安装。当前下载包仅有本地 ad-hoc 开发签名，未做 Apple Developer ID 签名和公证，不是正式签名发行版；也可按下文自行编译。

1. 本机安装并登录官方 Codex 或 Claude Code；历史日志的读取不要求当前登录。
2. 右上角选择 GPT / Claude。数据目录或工具路径不同时，可在设置中指定。
3. 使用原工具产生正常用量记录，再回到 QuotaMate 刷新。
4. Claude 额度采集需要在设置主动启用状态栏转发器。该采集方式针对终端会话，并非普通桌面聊天。关闭可恢复原状态栏。

若统计为空，先核对时间范围、所选数据目录以及是否存在对应本机日志。只登录账号不会同步云端 Token 历史。费用估算不代表订阅实际扣费；完整口径见 [数据来源](docs/data-sources.md)。

快捷键：⌘1 统计、⌘2 总览、⌘3 账号、⌘R 刷新、⌘E 导出、⌘, 设置。

## 从源码运行

已验证基准：Flutter **3.47.7** / Dart **3.13.5**，macOS、Xcode。Python 3 仅用于开发检查及打包，不是应用运行依赖。

```sh
git clone https://github.com/liuzilong200049-bot/QuotaMate.git
cd QuotaMate
flutter pub get --enforce-lockfile
flutter run -d macos
```

应用不会捆绑 Codex 或 Claude Code。开发运行时若尚未构建原生状态栏转发器，该采集功能会提示组件不可用；完整打包脚本会构建并放入转发器。普通统计与界面开发不需要它。

## 验证与打包

```sh
dart format --output=none --set-exit-if-changed lib test tool
dart analyze
flutter test
python3 -m unittest discover -s scripts -p 'test_*.py'
python3 scripts/check_public_files.py
bash scripts/package_macos.sh
```

公开文件检查读取 Git 索引；首次提交前应先暂存计划公开的文件。原生采集器测试、截图生成和贡献流程见 [CONTRIBUTING.md](CONTRIBUTING.md)。CI 使用模拟数据，不调用真实账号诊断或消耗额度。

打包产物位于 `dist/`，包含 DMG、ZIP 和 SHA256。新包校验通过后，脚本将本机旧版本安装包移至废纸篓，只保留最新版本；失败时保留旧包。安装包通过 Releases 分发，不提交到源码仓库。

## 隐私与问题报告

本机数据库位于 `~/Library/Application Support/QuotaMate/usage.sqlite3`，包含账号显示信息和项目路径，请勿公开。应用不保存对话正文、模型回答、工具参数或 OAuth 凭证，也没有自己的云端服务或遥测端点；官方 CLI 的服务商网络访问按其自身行为执行。

提交 Issue 前检查截图和文本，移除邮箱、真实路径和凭证。漏洞通过 [私密安全报告](https://github.com/liuzilong200049-bot/QuotaMate/security/advisories/new) 提交，不要公开上传数据库或原始日志。更多说明见 [SECURITY.md](SECURITY.md)。

## 贡献与许可

欢迎贡献解析兼容性、文档、界面和 Windows 支持。请先阅读 [贡献指南](CONTRIBUTING.md)、[版本记录](CHANGELOG.md) 和 [第三方声明](THIRD_PARTY_NOTICES.md)。

项目自有代码与资源采用 [MIT](LICENSE)，依赖继续遵守各自许可。视觉风格参考 [FlClash](https://github.com/chen08209/FlClash)，日志计时参考 [CC Switch](https://github.com/farion1231/cc-switch) 并保留 MIT 声明；未引入 FlClash 的界面源码或代理内核。图标及背景来源见 [品牌资源](docs/branding.md)。
