# Claude 内置参考单价

核对日期：2026-11-02。来源：[Claude 官方价格表](https://platform.claude.com/docs/en/about-claude/pricing)。单位均为 **美元 / 百万 Token**，采用标准速度、全局路由的基准价格。

这些价格内置于源码 `ClaudePricing.presets`，随安装包分发。全新安装自动加载以下 20 个型号；旧版升级只补充新型号，保留同名手动价格与已删除的旧条目。完成初始化后，删除的条目不会每次重启被重新加入。

| 模型 / 日志基础名称 | 新增输入 | 缓存读取 | 输出 |
| --- | ---: | ---: | ---: |
| claude-fable-5-1 | 10 | 0.25 | 50 |
| claude-fable-5 | 10 | 1 | 50 |
| claude-mythos-5-1 | 10 | 0.25 | 50 |
| claude-mythos-5 | 10 | 1 | 50 |
| claude-opus-5-5 | 4 | 0.20 | 20 |
| claude-opus-5 | 5 | 0.50 | 25 |
| claude-opus-4-8 | 5 | 0.50 | 25 |
| claude-opus-4-7 | 5 | 0.50 | 25 |
| claude-opus-4-6 | 5 | 0.50 | 25 |
| claude-opus-4-5 | 5 | 0.50 | 25 |
| claude-opus-4-1 | 15 | 1.50 | 75 |
| claude-opus-4 | 15 | 1.50 | 75 |
| claude-sonnet-5-5 | 2 | 0.10 | 10 |
| claude-sonnet-5 | 2 | 0.20 | 10 |
| claude-sonnet-4-6 | 3 | 0.30 | 15 |
| claude-sonnet-4-5 | 3 | 0.30 | 15 |
| claude-sonnet-4 | 3 | 0.30 | 15 |
| claude-haiku-5-5（输入不超过 100,000） | 0.10 | 0.01 | 0.50 |
| claude-haiku-4-5 | 1 | 0.10 | 5 |
| claude-3-5-haiku | 0.80 | 0.08 | 4 |

缓存写入分别采用输入单价的 **1.25 倍（5 分钟）**、**2 倍（1 小时）**，按日志中的缓存时长区分。Haiku 5.5 单条记录的输入超过 100,000 Token 时，整条记录改用输入 **0.50**、缓存读取 **0.05**、输出 **2.50**；写入倍率也随选中的输入档位计算。阈值包含缓存读取与写入，不按整天或所有会话的总量选档。

基础名称可匹配日期后缀和 `-latest` 日志名称，精确匹配的手动条目优先。历史型号的价格用于旧日志估算，配置价格不代表模型仍可调用。模型状态及命名见 [官方模型列表](https://platform.claude.com/docs/en/about-claude/model-deprecations) 和 [模型 ID 说明](https://platform.claude.com/docs/en/about-claude/models/model-ids-and-versions)。

这些是固定参考价，不自动联网更新，也不替代订阅账单。加速、区域、Batch、工具等额外价格不包含在本次基准估算中；未知模型保持未配置。手动覆盖某个型号的三项单价后，采用用户设置的统一参考价格。

GPT 原有的 5 项默认值保持不变，见 [GPT 参考价格](reference-pricing.md)。
