# Windows 使用与构建指南

[返回首页](../README.md) · [Windows 安装程序](https://github.com/liuzilong200049-bot/QuotaMate/releases/download/v0.1.30-alpha/QuotaMate-0.1.30-windows-x64-setup.exe) · [便携 ZIP](https://github.com/liuzilong200049-bot/QuotaMate/releases/download/v0.1.30-alpha/QuotaMate-0.1.30-windows-x64.zip)

## 安装与首次使用

首版为 **Windows x64 Alpha**。推荐 Windows 11；最低目标为 Windows 10 1809，原客户端的系统要求另行适用。目前不提供原生 ARM64 或 32 位安装包。

1. 下载 `QuotaMate-0.1.30-windows-x64-setup.exe` 并运行。安装到当前用户目录，不请求管理员权限。
2. 从开始菜单打开 **QuotaMate**。首次启动默认进入统计，显示今日数据；语言、主题和模型参考价格都已内置。
3. 在右上角选择 **GPT** 或 **Claude**，按下面步骤核对本机连接。
4. 用原客户端正常工作后回到 QuotaMate 刷新。仅登录账号不会生成 Token 历史。

便携版请先将 ZIP **全部解压**到同一个文件夹，再运行 `quota_mate.exe`；不要只拖出一个 EXE。数据库、Flutter 引擎和 VC++ 运行库已随包附带，无需安装 Flutter、Python 或 Visual Studio。便携版同样将个人数据写入用户目录，而非程序目录。

此 Alpha 暂无 Authenticode 发布者签名，Windows 可能显示未知发布者。请核对仓库来源和校验值，按自己的设备或组织策略决定是否试用；安装程序不会修改安全策略。

## 连接 GPT / Codex

- 在 Windows **原生** Codex CLI 或桌面应用中登录。项目不代替官方登录、不提供模型服务。
- 默认日志目录为 `%USERPROFILE%\.codex`；显式 `CODEX_HOME` 优先。在「设置 → Codex 数据目录」可以选其他配置根目录。
- 工具查找优先采用已指定路径、PATH 中的 `codex.exe`，并识别常见 npm 包内的原生 Codex 二进制。
- 如果只看到 `codex.cmd`，它是启动包装脚本。在「设置 → 指定路径」选择实际的 `codex.exe`；常见 npm 目录下的原生二进制会自动发现。
- Microsoft Store / 企业定制安装或其他非标准布局可能需要手动选择可执行文件。工具与日志目录必须指向同一套配置。

额度由官方 Codex App Server 提供；网页聊天、其他设备和未下载到本机的历史不在日志统计范围内。Windows 原生支持说明见 [OpenAI 官方文档](https://learn.chatgpt.com/docs/windows/windows-sandbox)。

## 连接 Claude Code

1. 安装 Windows 原生 [Claude Code](https://code.claude.com/docs/en/setup)，正常登录。默认查找 PATH 和 `%USERPROFILE%\.local\bin\claude.exe`；也可在设置手动指定。
2. 切换到 **Claude** 并刷新。默认日志目录是 `%USERPROFILE%\.claude`，显式 `CLAUDE_CONFIG_DIR` 优先。
3. 需要在 QuotaMate 发起登录时点击 **连接 Claude**，软件打开系统 PowerShell，由官方 `claude auth login` 完成登录，不修改脚本执行策略。
4. 需要额度快照时，开启 **设置 → 状态栏额度采集**，新开 Claude Code 会话并正常使用，之后回来刷新。

状态栏采集器是随包附带的独立 Windows EXE，不依赖 Dart / Python / Node 运行时；只接收官方状态栏交付的元数据，保留原状态栏输出和账号身份隔离，不主动轮询订阅接口。如果原工具没有交付 `rate_limits`，额度仍显示未知。Windows 状态栏的 Git Bash / PowerShell 行为见 [Claude 官方说明](https://code.claude.com/docs/en/statusline#windows-configuration)。

若已有定制状态栏，启用时会备份原设置，关闭采集后恢复。卸载 QuotaMate **不会**删掉 Claude 配置；卸载前可在设置关闭采集。

## 数据位置、快捷键与托盘

| 项目 | Windows 行为 |
| --- | --- |
| 本机数据库 / 偏好 | `%APPDATA%\QuotaMate\usage.sqlite3` |
| 默认 Codex 数据 | `%USERPROFILE%\.codex` |
| 默认 Claude 数据 | `%USERPROFILE%\.claude` |
| Claude 快照及原状态栏备份 | 所选 Claude 配置根目录下的 `quotamate` |
| 页面快捷键 | Ctrl+1 统计、Ctrl+2 总览、Ctrl+3 账号、Ctrl+, 设置 |
| 操作快捷键 | Ctrl+R 刷新、Ctrl+E 导出 |
| 系统托盘 | 单击弹出速览面板（额度、消耗预测、今日用量）；双击打开窗口；右键可刷新或退出；剩余额度在图标提示中显示 |
| 关闭窗口 | 默认退出；可在设置开启「关闭窗口后继续运行」，托盘菜单提供彻底退出 |
| 登录启动 | 默认不登记；在设置主动开启后以托盘方式启动，Windows 启动应用设置仍可禁用 |
| 再次打开 | 唤回已有实例，避免重复扫描与提醒 |
| 提醒 | Windows 托盘通知；系统通知设置、勿扰模式可能抑制提示 |

中文用户目录和含空格的安装路径属于自动测试覆盖范围。本机应用数据及采集目录限制为当前用户 / SYSTEM 访问；CSV 导出包含用量信息，请按个人数据保护。模型参考价格与 macOS 同源，用户自定义价格不会被覆盖。

## 常驻与登录启动

在 **设置 → Windows 运行方式** 中可分别开启关闭到托盘和登录启动。两项默认关闭。关闭到托盘需要系统托盘可用；托盘不可用时，关闭仍退出，后台启动也会显示窗口，避免出现无法访问的隐藏进程。

登录启动只登记当前用户的 `Run` 启动项，命令为已运行的本机 EXE 加 `--background`，不要求管理员权限，也不覆盖 Windows 的启动应用禁用策略。程序目录搬迁后，应在新位置重新开启；便携包同样适用。卸载仅删除指向该次安装目录的 QuotaMate 启动项，保留指向其他位置的登记和个人数据库。

设置中还提供 [连接诊断与手动检查更新](connection-checks.md)。

## WSL 与已知范围

首版不自动调用 `wsl.exe`，也不复用 WSL 的 Linux 登录。Windows 与 WSL 的 HOME、CLI、权限和日志格式路径属于不同环境。仅将 Windows 工具指向 Linux 配置目录可能查不到当前账号。

这一版本通过 Windows CI 进行编译、协议测试、采集器测试及安装包启动检查。真实账号切换、不同厂商桌面安装布局、系统托盘和通知体验仍欢迎 Windows 用户反馈。自动测试不能代替各种真实设备的完整验收。

## 从源码构建

需要 Windows、Flutter **3.47.7** / Dart **3.13.5**、Visual Studio 的 **Desktop development with C++**、Python 3（构建检查）和 Inno Setup 6（安装程序）。Flutter 的 Windows 编译需在 Windows 上进行：[官方构建指南](https://docs.flutter.dev/platform-integration/windows/building)。

```powershell
flutter pub get --enforce-lockfile
python scripts/prepare_windows.py
$env:PATH = "$pwd\build\windows-dependencies;$env:PATH"
flutter run -d windows
```

运行完整 Windows 测试前，先编译不访问真实账号的 CLI 夹具和采集器：

```powershell
dart compile exe tool/windows_cli_fixture.dart -o build/windows-dependencies/official-cli-fixture.exe
dart compile exe scripts/claude_statusline.dart -o build/windows-dependencies/quotamate-claude-statusline.exe
$env:QUOTAMATE_TEST_CLI = (Resolve-Path build/windows-dependencies/official-cli-fixture.exe).Path
$env:QUOTAMATE_TEST_RELAY = (Resolve-Path build/windows-dependencies/quotamate-claude-statusline.exe).Path
flutter test
```

生成完整安装程序与便携 ZIP：

```powershell
./scripts/package_windows.ps1
```

如果本机策略不允许直接运行脚本，可在允许的 PowerShell 会话中加载并执行脚本内容，或按组织的脚本签名流程处理；项目不要求关闭系统安全策略。输出位于 `dist/windows`。构建会下载固定版本的 SQLite 官方 DLL 并核对固定哈希，应用运行时不会下载数据库组件。新包成功生成后，仅将同目录中匹配本项目命名且版本更旧的 Windows 安装包移入回收站，保留较新版本及其他文件。

CI 不读取真实账号，使用合成 CLI 与隔离数据目录。安装包启动检查会解压便携包并验证进程、原生窗口和数据库；目前没有把真实订阅调用当作 CI 测试。

## 校验与排错

```powershell
Get-FileHash .\QuotaMate-0.1.30-windows-x64-setup.exe -Algorithm SHA256
```

与同一个 Release 中的 `SHA256SUMS-windows` 比较。缺数据先检查时间范围、数据目录和 Windows / WSL 环境；缺额度先检查官方工具的当前登录和状态栏快照。

反馈请提供 Windows 版本、系统架构、QuotaMate 版本、原客户端安装方式和脱敏截图。不要上传真实日志、数据库、邮箱或凭证。
