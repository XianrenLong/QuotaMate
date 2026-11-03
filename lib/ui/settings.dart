import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app_info.dart';
import '../controller.dart';
import '../l10n/strings.dart';
import '../data/appearance.dart';
import '../data/claude_pricing.dart';
import 'overview_account.dart';
import '../data/models.dart';
import '../data/native_bridge.dart';
import '../data/reference_pricing.dart';
import 'widgets.dart';
import 'localized.dart';
import 'maintenance.dart';

class AlertsPage extends StatelessWidget {
  final AppController c;
  const AlertsPage(this.c, {super.key});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MiniHeading('额度提醒', icon: LucideIcons.bell),
              SizedBox(height: 20),
              settingRow(
                '低额度通知',
                '额度低于阈值时，通过系统通知提醒。',
                trailing: Toggle(c.notifications, (v) => c.setNotifications(v)),
              ),
              Divider(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        label('剩余额度阈值', weight: FontWeight.w500),
                        SizedBox(height: 5),
                        label(
                          '当前窗口和较长窗口分别判断。',
                          size: 12,
                          color: themeColor(context, C.muted),
                        ),
                      ],
                    ),
                  ),
                  Segments(
                    ['10%', '20%', '30%'],
                    [10, 20, 30].indexOf(c.threshold),
                    (i) => c.setting(() => c.threshold = [10, 20, 30][i]),
                  ),
                ],
              ),
              SizedBox(height: 24),
              Container(
                padding: EdgeInsets.all(17),
                decoration: BoxDecoration(
                  color: themeColor(context, C.bg),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.shieldCheck,
                      size: 22,
                      color: themeColor(context, C.muted),
                    ),
                    SizedBox(width: 15),
                    Expanded(
                      child: label(
                        '同一额度窗口只提醒一次。演示数据和过期快照不会触发通知。',
                        size: 12,
                        color: themeColor(context, C.muted),
                        lines: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 14),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MiniHeading('当前恢复时间', icon: LucideIcons.clock3),
              SizedBox(height: 20),
              settingRow(
                '当前窗口',
                c.account?.primary == null
                    ? '尚未获取恢复时间'
                    : '${countdown(c.account!.primary!.resets, c.now)}后重置',
                trailing: ChipLabel(
                  c.quotaValid
                      ? '${c.account!.primary!.remaining}% 剩余'
                      : '暂不可用',
                ),
              ),
              Divider(height: 25),
              settingRow(
                weeklyLabel(c.account?.secondary),
                c.account?.secondary == null
                    ? '尚未获取恢复时间'
                    : countdown(c.account!.secondary!.resets, c.now),
                trailing: ChipLabel(
                  c.account?.secondary == null ||
                          c.account!.secondary!.expired(c.now)
                      ? '暂不可用'
                      : '${c.account!.secondary!.remaining}% 剩余',
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 14),
        Panel(
          child: Row(
            children: [
              Icon(
                LucideIcons.info,
                size: 19,
                color: themeColor(context, C.muted),
              ),
              SizedBox(width: 12),
              Expanded(
                child: label(
                  '提醒以平台返回的额度为准。每分钟读取本机新增记录，账号额度按所设间隔刷新。',
                  size: 12,
                  color: themeColor(context, C.muted),
                  lines: 2,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

String weeklyLabel(QuotaWindow? w) => w?.minutes == 10080 ? '本周窗口' : '较长窗口';
Widget settingRow(
  String title,
  String caption, {
  Widget? trailing,
  bool localizeCaption = true,
}) => Builder(
  builder: (context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label(title, weight: FontWeight.w500),
            SizedBox(height: 6),
            label(
              caption,
              size: 12,
              color: themeColor(context, C.muted),
              lines: 2,
              localize: localizeCaption,
            ),
          ],
        ),
      ),
      if (trailing != null) ...[SizedBox(width: 18), trailing],
    ],
  ),
);

class SettingsPage extends StatelessWidget {
  final AppController c;
  const SettingsPage(this.c, {super.key});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MiniHeading('外观与语言', icon: LucideIcons.languages),
              SizedBox(height: 16),
              settingRow(
                '主题模式',
                '选择浅色、深色，或跟随系统外观。',
                trailing: Segments(
                  ['浅色', '深色', '跟随系统'],
                  AppAppearance.values.indexOf(c.appearance),
                  (i) => c.setAppearance(AppAppearance.values[i]),
                ),
              ),
              Divider(height: 24),
              settingRow(
                '界面语言',
                '即时生效，重启后保持选择。',
                trailing: Segments(
                  ['简体中文', 'English'],
                  c.language == AppLanguage.zh ? 0 : 1,
                  (i) =>
                      c.setLanguage(i == 0 ? AppLanguage.zh : AppLanguage.en),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 14),
        ConnectionHealthPanel(c),
        SizedBox(height: 14),
        if (c.isWindows) ...[WindowsBehaviorPanel(c), SizedBox(height: 14)],
        UpdatesPanel(c),
        SizedBox(height: 14),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MiniHeading('数据与同步', icon: LucideIcons.database),
              SizedBox(height: 20),
              settingRow(
                '自动读取订阅日期',
                c.isClaude
                    ? '从本机配置读取订阅开始时间；缺少周期时不推算到期。'
                    : '本机解析登录缓存的订阅日期；不保存、不上传凭证。',
                trailing: Toggle(
                  c.readSubscriptionDates,
                  c.busy || c.demo ? null : c.setSubscriptionDateReading,
                ),
              ),
              Divider(height: 24),
              if (c.isClaude) ...[
                settingRow(
                  '额度数据来源',
                  '仅读取本地快照，不主动请求 Claude 订阅额度。',
                  trailing: ChipLabel('本地采集'),
                ),
                Divider(height: 24),
                settingRow(
                  'Claude 账号连接',
                  c.claudeSignedIn
                      ? c.account?.authMode == 'claude'
                            ? '账号已连接，仅核对本机登录状态。'
                            : '此认证方式仅提供本机统计，不提供订阅额度。'
                      : '使用 Claude Code 官方登录流程，不保存登录令牌。',
                  trailing: ClaudeConnectButton(c),
                ),
                Divider(height: 24),
                settingRow(
                  '状态栏额度采集',
                  '正常使用终端 Claude Code 时采集；保留原状态栏，可随时关闭。',
                  trailing: Toggle(
                    c.claudeCollectorEnabled,
                    c.busy ||
                            c.demo ||
                            (!c.claudeCollectorEnabled &&
                                (!c.claudeSignedIn ||
                                    c.account?.authMode != 'claude'))
                        ? null
                        : c.setClaudeCollector,
                  ),
                ),
                TextButton(
                  onPressed: () => NativeBridge.call('openClaude'),
                  child: LocalizedText('打开 Claude'),
                ),
                Divider(height: 24),
              ],
              settingRow(
                c.isClaude ? 'Claude 数据目录' : 'Codex 数据目录',
                c.demo ? '演示模式使用独立示例数据' : c.profile.root,
                localizeCaption: c.demo,
                trailing: ActionPill(
                  '选择目录',
                  icon: LucideIcons.folderOpen,
                  onTap: c.demo || c.busy ? null : () => c.addProfile(),
                ),
              ),
              Divider(height: 28),
              settingRow(
                c.isClaude ? 'Claude Code 工具' : 'Codex 工具',
                (c.isClaude ? c.claudeExecutable : c.executable) ??
                    (c.isClaude
                        ? '自动查找 Claude Code 或桌面应用附带工具'
                        : '自动查找已安装的 Codex CLI / 桌面应用'),
                localizeCaption:
                    (c.isClaude ? c.claudeExecutable : c.executable) == null,
                trailing: ActionPill('指定路径', onTap: () => c.chooseExecutable()),
              ),
              Divider(height: 28),
              settingRow(
                '自动刷新',
                c.isClaude ? '每分钟扫描本机记录，并读取已有额度快照。' : '本机记录每分钟扫描，账号额度按以下间隔刷新。',
                trailing: Toggle(
                  c.autoRefresh,
                  (v) => c.setting(() => c.autoRefresh = v),
                ),
              ),
              if (!c.isClaude) ...[
                SizedBox(height: 16),
                Row(
                  children: [
                    label(
                      '额度刷新间隔',
                      size: 13,
                      color: themeColor(context, C.muted),
                    ),
                    Spacer(),
                    Segments(
                      ['5分钟', '10分钟', '30分钟'],
                      [5, 10, 30].indexOf(c.refreshMinutes),
                      (i) => c.setting(() => c.refreshMinutes = [5, 10, 30][i]),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: 14),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MiniHeading(
                '模型参考定价',
                icon: LucideIcons.circleDollarSign,
                trailing: TextButton.icon(
                  onPressed: () => _addPrice(context),
                  icon: Icon(LucideIcons.plus, size: 16),
                  label: LocalizedText('添加单价'),
                ),
              ),
              SizedBox(height: 8),
              label(
                '单位：美元 / 百万 Token。缺少价格时保持未知，估算不代表订阅扣费。',
                size: 12,
                color: themeColor(context, C.muted),
                lines: 2,
              ),
              SizedBox(height: 6),
              label(
                '已内置默认参考单价，首次使用自动填入；同名手动价格优先。',
                size: 12,
                color: themeColor(context, C.muted),
                lines: 2,
              ),
              SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  label(
                    '官方参考价 · ${c.isClaude ? ClaudePricing.checkedOn : ReferencePricing.checkedOn} · Standard 基准档',
                    size: 12,
                    color: themeColor(context, C.muted),
                  ),
                  TextButton(
                    onPressed: () => NativeBridge.call('openUrl', {
                      'url': c.isClaude
                          ? ClaudePricing.sourceUrl
                          : ReferencePricing.sourceUrl,
                    }),
                    child: LocalizedText('价格来源'),
                  ),
                ],
              ),
              label(
                c.isClaude
                    ? 'Claude 估算区分缓存读取与写入，按可用缓存时长计算；未计加速、区域及工具费用。'
                    : '参考估算未计长上下文、加速档、缓存写入和工具费用；手动配置的价格优先。',
                size: 11,
                color: themeColor(context, C.muted),
                lines: 2,
              ),
              if (c.prices.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 22),
                  child: label(
                    '尚未配置模型单价。Token 和额度统计可正常使用。',
                    size: 13,
                    color: themeColor(context, C.muted),
                  ),
                ),
              for (final price in c.prices.where(
                (price) => c.isClaude
                    ? price.model.startsWith('claude-')
                    : !price.model.startsWith('claude-'),
              )) ...[
                Divider(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: label(
                        price.model,
                        weight: FontWeight.w500,
                        localize: false,
                      ),
                    ),
                    label(
                      '输入 ${price.input} · 缓存 ${price.cached} · 输出 ${price.output}',
                      size: 12,
                      color: themeColor(context, C.muted),
                    ),
                    SizedBox(width: 12),
                    IconButton(
                      tooltip: AppLocale.text(context, '删除单价'),
                      onPressed: () => c.removePrice(price.model),
                      icon: Icon(
                        LucideIcons.trash2,
                        size: 17,
                        color: themeColor(context, C.muted),
                      ),
                    ),
                  ],
                ),
                if (c.isClaude)
                  Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: label(
                        '缓存写入：5分钟 ${price.cacheWrite5m ?? price.input * 1.25} · 1小时 ${price.cacheWrite1h ?? price.input * 2}',
                        size: 11,
                        color: themeColor(context, C.muted),
                      ),
                    ),
                  ),
                if (price.hasLongContextRate)
                  Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: label(
                        '输入超过 ${price.longContextThreshold} Token：输入 ${price.longContextInput} · 缓存 ${price.longContextCached} · 输出 ${price.longContextOutput}',
                        size: 11,
                        color: themeColor(context, C.muted),
                        lines: 2,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        SizedBox(height: 14),
        Panel(
          child: Column(
            children: [
              settingRow(
                '演示模式',
                '只在本次打开时生效；重启后恢复真实数据。',
                trailing: Toggle(c.demo, c.busy ? null : (v) => c.setDemo(v)),
              ),
              Divider(height: 28),
              settingRow(
                '本地数据',
                '用量字段保存在这台电脑，不保存对话正文或账号凭证。',
                trailing: ActionPill(
                  '打开文件夹',
                  onTap: () =>
                      NativeBridge.call('reveal', {'path': c.store.path}),
                ),
              ),
              Divider(height: 28),
              settingRow(
                '脱敏诊断',
                '仅复制版本、记录条数与连接状态，不含账号和路径。',
                trailing: ActionPill(
                  '复制诊断',
                  onTap: () async {
                    await Clipboard.setData(
                      ClipboardData(text: c.diagnostics()),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: LocalizedText('已复制脱敏诊断信息。')),
                      );
                    }
                  },
                ),
              ),
              Divider(height: 28),
              settingRow(
                '清除统计缓存',
                '清除已导入的统计，下次同步会从仍保留的本机日志重建。',
                trailing: TextButton(
                  onPressed: c.busy ? null : () => _clear(context),
                  child: LocalizedText(
                    '清除缓存',
                    style: TextStyle(color: themeColor(context, C.amber)),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 14),
        Panel(
          child: Row(
            children: [
              Image.asset(
                'assets/branding/quotamate-hourglass.png',
                width: 34,
                height: 34,
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    label(
                      '${AppInfo.name}  ${AppInfo.version}',
                      weight: FontWeight.w600,
                    ),
                    SizedBox(height: 5),
                    label(
                      '本地优先 · GPT / Claude · macOS / Windows',
                      size: 12,
                      color: themeColor(context, C.muted),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: AppInfo.name,
                  applicationVersion: AppInfo.version,
                ),
                child: LocalizedText('开源许可'),
              ),
            ],
          ),
        ),
        SizedBox(height: 16),
      ],
    ),
  );
  Future<void> _clear(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: LocalizedText('清除本地统计缓存？'),
        content: LocalizedText('原始日志会保留。已从磁盘删除的历史日志无法重新导入。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: LocalizedText('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: LocalizedText('清除缓存'),
          ),
        ],
      ),
    );
    if (yes == true) await c.clear();
  }

  Future<void> _addPrice(BuildContext context) async {
    final fields = List.generate(4, (_) => TextEditingController());
    final form = GlobalKey<FormState>();
    final known = c.demo ? <String>[] : c.store.models(c.profile.scope);
    if (known.isNotEmpty) fields[0].text = known.first;
    ModalRoute<dynamic>? dialogRoute;
    await showDialog<void>(
      context: context,
      builder: (context) {
        dialogRoute = ModalRoute.of(context);
        return AlertDialog(
          title: LocalizedText('添加模型参考价格'),
          content: SizedBox(
            width: 430,
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LocalizedText(
                    '每百万 Token 的美元价格。缓存是输入的一部分，不会重复计费。',
                    style: TextStyle(
                      fontSize: 12,
                      color: themeColor(context, C.muted),
                    ),
                  ),
                  SizedBox(height: 16),
                  for (var i = 0; i < 4; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: 13),
                      child: TextFormField(
                        controller: fields[i],
                        decoration: InputDecoration(
                          labelText: AppLocale.text(
                            context,
                            ['日志中的模型名称', '新增输入单价', '缓存命中单价', '输出单价'][i],
                          ),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return AppLocale.text(context, '请填写此项');
                          }
                          if (i > 0) {
                            final n = double.tryParse(v);
                            if (n == null || !n.isFinite || n < 0) {
                              return AppLocale.text(context, '请填写不小于 0 的数字');
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: LocalizedText('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  c.addPrice(
                    ModelPrice(
                      fields[0].text.trim(),
                      double.parse(fields[1].text),
                      double.parse(fields[2].text),
                      double.parse(fields[3].text),
                    ),
                  );
                  Navigator.pop(context);
                }
              },
              child: LocalizedText('保存'),
            ),
          ],
        );
      },
    );
    await dialogRoute?.completed;
    for (final f in fields) {
      f.dispose();
    }
  }
}
