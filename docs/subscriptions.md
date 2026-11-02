# 订阅等级显示

Claude 自 v0.1.19 使用独立计划命名空间：Free 灰色、Pro 蓝色、Max / Max X5 / Max X20 / Ultra 金色、Team / Enterprise 蓝色。仅在官方状态信息给出倍率时显示 X5 / X20，不猜测。Claude Pro 不触发 OpenAI Pro 的“隐藏较长窗口”规则；Claude 也不使用 GPT 的重置机会。以下表格与规则保留用于 GPT / Codex。

个人账号等级根据 Codex CLI App Server 的 planType 识别。查询到额度接口同时提供 planType 时优先采用该服务端结果，否则采用 account/read 的账号等级。

| planType | 显示名称 | 颜色 |
| --- | --- | --- |
| free / none | 无订阅 | 灰色 |
| 明确返回 expired / ended，或订阅到期时刻已过 | 订阅过期 | 灰色 |
| go | GO | 蓝色 |
| plus | Plus | 蓝色 |
| prolite | Pro X5 | 金色 |
| pro | Pro X20 | 金色 |
| promax | Pro X50 | 金色 |

兼容 pro_x5、pro_x20、pro_x50 等明确倍率标识。未知的 Pro 变体保留 Pro 身份和金色，但显示档位未知，不猜倍率。

默认 CLI 协议只保证提供 planType，不保证返回订阅过期日期。如果只返回 free，则只能显示无订阅，不能推断用户过去是否订阅过。失去登录、查询失败、额度窗口重置不是订阅过期的证据；取消续费但到期日仍在未来也不直接显示过期。

2026-11-01 再次排查：当前已安装 CLI 的 `GetAccountResponse` schema 中，ChatGPT 账号属性只有 `email`、`planType`、`type`、`workspaceName`。直接调用 `account/read` 的实际账号响应同样仅包含这四个属性，没有任何订阅、续费、到期日期字段；排查过程只输出字段名称和是否存在日期，不输出账号值或凭证。当前程序不是漏显示日期，而是此数据源没有提供。`subscriptionExpiresAt` 的兼容读取仍保留；`account/rateLimits/read` 的 `resetsAt` 表示额度恢复时间，重置权益中的 `expiresAt` 表示那份权益的有效期，都不能作为订阅到期日。参见 [OpenAI 官方账号接口说明](https://learn.chatgpt.com/docs/app-server#1-check-auth-state)。

总览：Pro 系列将原来的较长窗口卡片替换为今日用量记录；Plus 保留较长窗口。账号页同样采用此规则显示对应数据，账号列表和详情以彩色徽章显示订阅等级。非当前选中账号的等级来自该数据目录的已缓存快照，并标明历史状态。

等级仅为展示，不更改订阅或登录。Pro 当前没有五小时限额的说明见 [官方 Codex 价格与用量文档](https://learn.chatgpt.com/docs/pricing#what-are-the-usage-limits-for-my-plan)。本机协议 enum 来自 Codex CLI 导出的 GetAccountResponse，核对日期 2026-11-01。

总览账号卡片显示当前查看账号的邮箱、订阅等级、订阅有效期和额度重置次数，取代原来的账号状态、数据源名称与 Codex 订阅额度文案。接口未提供订阅到期日时显示“接口未提供”，不以额度窗口的重置时间推算。

额度重置次数读取 `account/rateLimits/read` 响应顶层的 `rateLimitResetCredits.availableCount`。正数显示可用次数，零显示暂无可用次数，`null` 或缺失显示接口未提供。详情列表可能被截断，不能用 `credits` 数组长度代替次数。来源：[OpenAI App Server 官方文档](https://learn.chatgpt.com/docs/app-server#auth-endpoints)，核对日期 2026-11-01。

总览的“重置额度”按钮仅在账号已验证、数据新鲜、存在可用次数且没有正在执行的操作时启用。点击后通过 `account/rateLimitResetCredit/consume` 使用一次重置权益，不额外弹窗。接口决定当前窗口是否符合重置条件；`nothingToReset` / `noCredit` 会显示对应提示，不声称重置成功。重置前重新核对登录邮箱，完成后重新查询账号与额度，不自行将百分比改为 100% 或将次数减一。

每次重置操作先生成并保存 UUID 幂等键，再调用接口；网络异常或应用重启后的同次重试沿用原键，避免重复消耗次数。已确认成功但刷新失败时提示成功及刷新失败，并暂停再次重置直到数据重新确认。演示模式不调用真实重置接口。自动测试使用模拟服务，不消耗真实账号权益。

“切换账号”下拉菜单直接选择已经连接的 Codex 配置目录，邮箱、订阅、次数和统计随数据源一起切换。可通过“添加账号数据源”选择另一个已有会话记录的 Codex 配置目录，或进入“管理账号”。它只影响额度管家当前查看的数据源，不更改 Codex / ChatGPT 客户端登录；未提供账号信息的目录显示其名称，不编造邮箱。
