# 第三方许可与参考来源

QuotaMate 自有代码及资源采用 [MIT](LICENSE)。以下组件与参考实现保留原有许可；本文件不替代依赖包自身的完整许可证。

| 组件或来源 | 用途 | 许可文件 |
| --- | --- | --- |
| Flutter / flutter_localizations | 应用框架与本地化 | [Flutter BSD](docs/licenses/flutter.txt) |
| cupertino_icons | 图标字体依赖 | [MIT](docs/licenses/cupertino_icons.txt) |
| fl_chart | 图表 | [MIT](docs/licenses/fl_chart.txt) |
| lucide_icons_flutter | Flutter 图标封装 | [MIT](docs/lucide-icons-LICENSE.txt) |
| Lucide / Feather | 图标设计与字体来源 | [ISC / MIT](docs/licenses/lucide.txt) |
| SQLite engine（Windows） | 随包附带的固定版本数据库引擎 | [Public domain](docs/licenses/sqlite-engine.txt) |
| sqlite3（Dart 包） | 本机数据库绑定 | [MIT](docs/licenses/sqlite3.txt) |
| crypto | 指纹计算 | [BSD](docs/licenses/crypto.txt) |
| path | 路径处理 | [BSD](docs/licenses/path.txt) |
| CC Switch RequestTimer | Codex 日志计时逻辑参考，以 Dart 独立实现并持久化游标状态 | [MIT](docs/cc-switch-LICENSE.txt) |

运行时依赖的完整版本由 [pubspec.lock](pubspec.lock) 记录。Flutter 构建会汇总其依赖通知，应用设置中的开源许可页提供查看入口。升级依赖时应同步核对许可证和本声明。

[CC Switch 参考实现](https://github.com/farion1231/cc-switch/blob/main/src-tauri/src/services/session_usage_codex.rs) 的计时口径及本项目差异见 [数据来源](docs/data-sources.md)。[FlClash](https://github.com/chen08209/FlClash) 仅作为界面风格参考，其源码、代理内核和原始截图不包含在本仓库。

Codex、Claude Code、macOS 字体及系统组件由用户自己的环境提供，不随本仓库捆绑。本项目不声称取得服务商背书；MIT 源码许可不会替代使用这些产品所需遵守的条款。

Windows 包随附应用本地 Visual C++ Runtime，来自构建所用 Visual Studio 的可再发行目录，适用其 Microsoft Visual Studio 许可，不适用本项目 MIT；未包含 Visual Studio 开发工具。Windows 安装程序使用 Inno Setup 6 构建，其安装引擎适用 [Inno Setup License](https://jrsoftware.org/files/is/license.txt)。
