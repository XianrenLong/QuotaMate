import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../controller.dart';
import '../data/models.dart';
import 'app.dart';
import 'widgets.dart';
import 'localized.dart';
import 'usage_details_table.dart';
import 'subscription_badge.dart';
import 'overview_account.dart';
import '../data/subscription_info.dart';

Widget split(List<Widget> children, {List<int>? flex}) => Row(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    for (var i = 0; i < children.length; i++) ...[
      if (i > 0) SizedBox(width: 14),
      Expanded(flex: flex?[i] ?? 1, child: children[i]),
    ],
  ],
);
Widget canvas(Widget Function(double height) builder, {double minimum = 650}) =>
    LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: SizedBox(
          height: math.max(minimum, c.maxHeight),
          child: builder(math.max(minimum, c.maxHeight)),
        ),
      ),
    );
String money(UsageSummary s) =>
    s.cost == null ? '未配置' : '\$${s.cost!.toStringAsFixed(2)}';
String weeklyLabel(QuotaWindow? w) => w?.minutes == 10080 ? '本周剩余' : '较长窗口剩余';
int? validRemaining(QuotaWindow? w, DateTime now) =>
    w == null || w.expired(now) ? null : w.remaining;

class PeriodStrip extends StatelessWidget {
  final AppController c;
  final bool statistics;
  const PeriodStrip(this.c, {super.key, this.statistics = false});
  @override
  Widget build(BuildContext context) => Panel(
    padding: EdgeInsets.symmetric(horizontal: 19, vertical: 7),
    child: Row(
      children: [
        Icon(
          LucideIcons.calendarDays,
          size: 19,
          color: themeColor(context, C.muted),
        ),
        SizedBox(width: 12),
        label('统计周期', size: 13),
        SizedBox(width: 14),
        Segments(
          ['今日', '近7天', '近30天'],
          [1, 7, 30].indexOf(c.days),
          (i) => c.setDays([1, 7, 30][i]),
        ),
        if (statistics) ...[
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: label(
                _range(),
                size: 11,
                color: themeColor(context, C.muted),
              ),
            ),
          ),
          SizedBox(width: 12),
          IconButton(
            tooltip: AppLocale.text(context, '导出统计'),
            onPressed: () => c.export(),
            icon: Icon(
              LucideIcons.share,
              size: 18,
              color: themeColor(context, C.muted),
            ),
          ),
        ] else ...[
          Spacer(),
          label('自动刷新', size: 13, color: themeColor(context, C.muted)),
          SizedBox(width: 12),
          Toggle(c.autoRefresh, (v) => c.setting(() => c.autoRefresh = v)),
        ],
      ],
    ),
  );
  String _range() {
    final start = DateTime(
      c.now.year,
      c.now.month,
      c.now.day,
    ).subtract(Duration(days: c.days - 1));
    String date(DateTime d) =>
        '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
    return '${date(start)} — ${date(c.now)}';
  }
}

class OverviewPage extends StatefulWidget {
  final AppController c;
  const OverviewPage(this.c, {super.key});
  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  bool requests = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final costTrend = c.costValues();
    final todayCost = c.today;
    final primary = c.presentedWindow;
    final secondary = c.account?.secondary;
    final weekly = c.presentedQuota(secondary)?.remaining;
    return canvas(
      (height) => Column(
        children: [
          SizedBox(
            height: 180,
            child: split(
              [
                OverviewAccountCard(c),
                LocalizedTooltip(
                  message: '今日用量按 API 参考价折算，不代表订阅实际扣费；小图显示近7天费用趋势。',
                  child: NumberCard(
                    '等价估算',
                    todayCost.events.isEmpty ? '\$0.00' : money(todayCost),
                    LucideIcons.circleDollarSign,
                    caption:
                        todayCost.events.isNotEmpty && !todayCost.fullyPriced
                        ? '配置模型价格'
                        : '今日 · 参考价折算',
                    onTap: todayCost.events.isNotEmpty && !todayCost.fullyPriced
                        ? () => c.navigate(4)
                        : null,
                    bottom: Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: costTrend == null
                          ? Center(
                              child: label(
                                '部分记录缺少单价',
                                size: 11,
                                color: themeColor(context, C.muted),
                              ),
                            )
                          : UsageChart(costTrend, c.now, mini: true),
                    ),
                  ),
                ),
                NumberCard(
                  '今日 Token',
                  compact(c.today.total),
                  LucideIcons.fileText,
                  caption: '本机记录',
                  bottom: Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: UsageChart(c.values(period: 7), c.now, mini: true),
                  ),
                ),
              ],
              flex: [2, 1, 1],
            ),
          ),
          SizedBox(height: 14),
          SizedBox(height: 51, child: PeriodStrip(c)),
          SizedBox(height: 14),
          SizedBox(
            height: 132,
            child: split([
              if (c.subscription.isPro)
                NumberCard(
                  '今日用量记录',
                  '${c.today.requests}',
                  LucideIcons.activity,
                  caption: '今日 · 本机记录',
                )
              else
                NumberCard(
                  weeklyLabel(secondary),
                  weekly == null ? '—' : '$weekly%',
                  LucideIcons.chartPie,
                  caption: c.isClaude && c.stale && weekly != null
                      ? '历史快照 · ${clockText(c.account!.observed)}'
                      : weekly == null
                      ? '暂无额度信息'
                      : '${countdown(secondary?.resets, c.now)}后重置',
                  bottom: Align(
                    alignment: Alignment.centerLeft,
                    child: QuotaBar(weekly),
                  ),
                ),
              NumberCard(
                '下次恢复',
                primary == null ? '—' : countdown(primary.resets, c.now),
                LucideIcons.clock3,
                caption: c.quotaHistorical ? '历史快照' : '当前额度窗口',
              ),
              NumberCard(
                '活跃项目',
                '${c.summary.projects}',
                LucideIcons.layers,
                caption: c.days == 1 ? '今日有记录' : '近${c.days}天有记录',
              ),
              NumberCard(
                '最近同步',
                clockText(c.account?.observed ?? c.lastScan),
                LucideIcons.link,
                caption: c.stale ? '历史快照，刷新以确认' : c.status,
              ),
            ]),
          ),
          SizedBox(height: 14),
          Expanded(
            child: split(
              [
                Panel(
                  child: Column(
                    children: [
                      MiniHeading(
                        '用量趋势',
                        icon: LucideIcons.chartNoAxesCombined,
                        trailing: Segments(
                          ['Token', '记录数'],
                          requests ? 1 : 0,
                          (i) => setState(() => requests = i == 1),
                        ),
                      ),
                      SizedBox(height: 22),
                      Expanded(
                        child: c.events.isEmpty
                            ? EmptyState(
                                '还没有用量记录',
                                c.isClaude
                                    ? c.claudeEmptyUsageText
                                    : '使用 Codex 后，这里会显示消耗趋势。',
                                onTap: () => c.navigate(4),
                              )
                            : UsageChart(
                                c.values(requests: requests),
                                c.now,
                                requests: requests,
                              ),
                      ),
                    ],
                  ),
                ),
                Panel(
                  child: Column(
                    children: [
                      MiniHeading('近期会话', icon: LucideIcons.clock3),
                      SizedBox(height: 17),
                      Expanded(child: _recent(context, c)),
                    ],
                  ),
                ),
              ],
              flex: [8, 5],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recent(BuildContext context, AppController c) {
    final seen = <String>{};
    final sessionTotals = <String, int>{};
    for (final event in c.events) {
      sessionTotals.update(
        event.session,
        (total) => total + event.tokens.total,
        ifAbsent: () => event.tokens.total,
      );
    }
    final latest = c.events.where((e) => seen.add(e.session)).take(3).toList();
    if (latest.isEmpty) return EmptyState('暂无会话', '只显示含用量的本机记录');
    return Column(
      children: [
        for (var i = 0; i < latest.length; i++) ...[
          if (i > 0) SizedBox(height: 7),
          Expanded(
            child: Material(
              color: themeColor(context, Color(0xFFF0EFF5)),
              borderRadius: BorderRadius.circular(15),
              child: InkWell(
                borderRadius: BorderRadius.circular(15),
                onTap: () =>
                    showSession(context, latest[i], latestInSession: true),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 13),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.folder,
                        size: 19,
                        color: themeColor(context, C.muted),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            label(
                              projectName(latest[i].project),
                              weight: FontWeight.w500,
                              localize: latest[i].project.isEmpty,
                            ),
                            SizedBox(height: 4),
                            label(
                              clockText(latest[i].at),
                              size: 11,
                              color: themeColor(context, C.muted),
                            ),
                          ],
                        ),
                      ),
                      label(
                        compact(sessionTotals[latest[i].session]!),
                        size: 12,
                      ),
                      SizedBox(width: 9),
                      Icon(
                        LucideIcons.chevronRight,
                        size: 15,
                        color: themeColor(context, C.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class AccountsPage extends StatelessWidget {
  final AppController c;
  const AccountsPage(this.c, {super.key});
  @override
  Widget build(BuildContext context) => canvas(
    (height) => split(
      [
        Column(
          children: [
            Expanded(
              flex: 7,
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MiniHeading(
                      '已连接数据源',
                      trailing: ChipLabel('${c.profiles.length}'),
                    ),
                    SizedBox(height: 16),
                    Expanded(
                      child: ListView.separated(
                        itemCount: c.profiles.length,
                        separatorBuilder: (_, i) => SizedBox(height: 10),
                        itemBuilder: (_, i) => InkWell(
                          onTap: c.busy ? null : () => c.selectProfile(i),
                          borderRadius: BorderRadius.circular(17),
                          child: Container(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: i == c.selected
                                  ? themeColor(context, Color(0xFFF0F5FF))
                                  : themeColor(context, C.bg),
                              borderRadius: BorderRadius.circular(17),
                              border: Border.all(
                                color: i == c.selected
                                    ? themeColor(context, Color(0xFFB7CEFF))
                                    : themeColor(context, C.line),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: themeColor(
                                        context,
                                        Color(0xFFE3E6F0),
                                      ),
                                      child: Icon(
                                        LucideIcons.userRound,
                                        size: 22,
                                        color: themeColor(context, C.muted),
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: label(
                                        c.demo ? '演示账号' : c.profiles[i].label,
                                        size: 17,
                                        weight: FontWeight.w600,
                                      ),
                                    ),
                                    if (i == c.selected) ChipLabel('当前查看'),
                                  ],
                                ),
                                SizedBox(height: 9),
                                label(
                                  i == c.selected
                                      ? (c.account?.email ??
                                            (c.isClaude
                                                ? '本机 Claude 数据源'
                                                : '本机 Codex 数据源'))
                                      : '独立数据目录',
                                  size: 12,
                                  color: themeColor(context, C.muted),
                                ),
                                if (i != c.selected) ...[
                                  SizedBox(height: 12),
                                  SubscriptionBadge(
                                    c.subscriptionForProfile(i),
                                    historical: true,
                                  ),
                                ],
                                if (i == c.selected) ...[
                                  SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      SubscriptionBadge(
                                        c.subscription,
                                        historical: c.stale,
                                      ),
                                      ChipLabel(
                                        c.demo
                                            ? '示例账号'
                                            : c.stale
                                            ? '历史快照'
                                            : c.account?.signedIn == true
                                            ? '已连接'
                                            : '本机记录',
                                        green: true,
                                      ),
                                    ],
                                  ),
                                  Padding(
                                    padding: EdgeInsets.symmetric(vertical: 11),
                                    child: Divider(height: 1),
                                  ),
                                  _quota('当前窗口剩余', c.account?.primary),
                                  SizedBox(height: 8),
                                  if (c.subscription.isPro)
                                    Row(
                                      children: [
                                        Expanded(
                                          child: label(
                                            '今日用量记录',
                                            size: 12,
                                            color: themeColor(context, C.muted),
                                          ),
                                        ),
                                        label(
                                          '${c.today.requests}',
                                          size: 20,
                                          weight: FontWeight.w600,
                                        ),
                                      ],
                                    )
                                  else
                                    _quota(
                                      weeklyLabel(c.account?.secondary),
                                      c.account?.secondary,
                                    ),
                                  SizedBox(height: 8),
                                  label(
                                    c.isClaude
                                        ? c.quotaSampleLabel
                                        : '最近同步 · ${clockText(c.account?.observed)}',
                                    size: 11,
                                    color: themeColor(context, C.muted),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    Center(
                      child: TextButton.icon(
                        onPressed: c.demo ? null : () => c.addProfile(),
                        icon: Icon(LucideIcons.circlePlus, size: 17),
                        label: LocalizedText(
                          c.isClaude ? '添加 Claude 数据源' : '添加 GPT 数据源',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 14),
            Expanded(
              flex: 4,
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MiniHeading('数据来源'),
                    SizedBox(height: 14),
                    _source(
                      context,
                      LucideIcons.layers,
                      '账号额度',
                      c.account?.source ?? '等待首次获取',
                    ),
                    Divider(height: 20),
                    _source(context, LucideIcons.clock3, '历史用量', '来自本机会话记录'),
                    Spacer(),
                    label(
                      '账号额度与本机统计分别展示',
                      size: 11,
                      color: themeColor(context, C.muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Panel(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MiniHeading('账号详情'),
                      SizedBox(height: 22),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 25,
                            backgroundColor: themeColor(
                              context,
                              Color(0xFFEBEAF2),
                            ),
                            child: Icon(
                              LucideIcons.userRound,
                              size: 28,
                              color: themeColor(context, C.ink),
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: label(
                              '${c.providerLabel} · ${c.demo ? '演示账号' : c.profile.label}',
                              size: 20,
                              weight: FontWeight.w600,
                            ),
                          ),
                          ChipLabel(
                            c.stale ? '历史快照' : c.status,
                            green: !c.stale,
                          ),
                        ],
                      ),
                      SizedBox(height: 22),
                      for (final pair in [
                        MapEntry('账号', c.account?.email ?? '尚未获取'),
                        MapEntry(
                          '订阅有效期',
                          subscriptionValidityText(c.account, c.now),
                        ),
                        MapEntry('额度重置', quotaResetText(c.account)),
                        MapEntry(
                          '额度范围',
                          c.isClaude ? 'Claude 订阅额度' : 'Codex 订阅额度',
                        ),
                        MapEntry('历史范围', '这台电脑（未按账号归属）'),
                        MapEntry(
                          c.isClaude ? '额度快照' : '最近同步',
                          c.isClaude
                              ? c.quotaSampleLabel
                              : clockText(c.account?.observed),
                        ),
                      ]) ...[_detail(pair.key, pair.value), Divider(height: 1)],
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 110,
                              child: label(
                                '订阅等级',
                                size: 12,
                                color: themeColor(context, C.muted),
                              ),
                            ),
                            SubscriptionBadge(
                              c.subscription,
                              historical: c.stale,
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1),
                      Spacer(),
                      MiniHeading('同步设置'),
                      SizedBox(height: 12),
                      _setting(
                        c.isClaude ? '读取额度快照' : '同步账号额度',
                        c.isClaude ? '仅显示本地已采集的额度与重置时间' : '显示剩余额度与重置时间',
                        LucideIcons.refreshCw,
                        c.quotaEnabled,
                        (v) => c.setting(() => c.quotaEnabled = v),
                      ),
                      SizedBox(height: 7),
                      _setting(
                        '汇总本机用量',
                        '保留模型与项目的用量统计',
                        LucideIcons.chartNoAxesCombined,
                        c.scanEnabled,
                        (v) => c.setting(() => c.scanEnabled = v),
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            LucideIcons.clock3,
                            size: 19,
                            color: themeColor(context, C.muted),
                          ),
                          SizedBox(width: 12),
                          Expanded(child: label('刷新间隔', size: 13)),
                          Segments(
                            [c.isClaude ? '1分钟' : '5分钟', '手动'],
                            c.autoRefresh ? 0 : 1,
                            (i) => c.setting(() {
                              c.autoRefresh = i == 0;
                              c.refreshMinutes = 5;
                            }),
                          ),
                        ],
                      ),
                      SizedBox(height: 14),
                      splitButtons([
                        ActionPill(
                          '立即同步',
                          onTap: c.busy ? null : () => c.refresh(),
                          primary: true,
                        ),
                        ActionPill(
                          '查看数据来源',
                          onTap: () => showSources(context, c),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
      flex: [5, 7],
    ),
    minimum: 650,
  );
  Widget _quota(String title, QuotaWindow? w) => Builder(
    builder: (context) => Column(
      children: [
        Row(
          children: [
            Expanded(
              child: label(
                c.isClaude && c.stale && c.presentedQuota(w) != null
                    ? '$title（快照）'
                    : title,
                size: 12,
                color: themeColor(context, C.muted),
              ),
            ),
            label(
              c.presentedQuota(w) == null ? '—' : '${w!.remaining}%',
              size: 20,
              weight: FontWeight.w600,
            ),
          ],
        ),
        SizedBox(height: 4),
        QuotaBar(c.presentedQuota(w)?.remaining),
      ],
    ),
  );
  Widget _source(
    BuildContext context,
    IconData icon,
    String title,
    String caption,
  ) => InkWell(
    onTap: () => showSources(context, c),
    child: Row(
      children: [
        Icon(icon, size: 21, color: themeColor(context, C.muted)),
        SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label(title, size: 14),
              SizedBox(height: 4),
              label(caption, size: 12, color: themeColor(context, C.muted)),
            ],
          ),
        ),
        Icon(
          LucideIcons.chevronRight,
          size: 16,
          color: themeColor(context, C.muted),
        ),
      ],
    ),
  );
}

Widget _detail(String name, String value, {bool localizeValue = true}) =>
    Builder(
      builder: (context) => Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: label(name, size: 12, color: themeColor(context, C.muted)),
            ),
            Expanded(
              child: LocalizedTooltip(
                message: value,
                localize: localizeValue,
                child: label(
                  value,
                  size: 13,
                  color: themeColor(context, C.muted),
                  localize: localizeValue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
Widget _setting(
  String name,
  String caption,
  IconData icon,
  bool value,
  ValueChanged<bool> onChanged,
) => Builder(
  builder: (context) => Container(
    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: themeColor(context, C.bg),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      children: [
        Icon(icon, size: 20, color: themeColor(context, C.muted)),
        SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label(name, size: 14, weight: FontWeight.w500),
              SizedBox(height: 4),
              label(caption, size: 11, color: themeColor(context, C.muted)),
            ],
          ),
        ),
        SizedBox(width: 10),
        Toggle(value, onChanged),
      ],
    ),
  ),
);
Widget splitButtons(List<Widget> children) => Row(
  children: [
    for (var i = 0; i < children.length; i++) ...[
      if (i > 0) SizedBox(width: 12),
      Expanded(child: children[i]),
    ],
  ],
);
String projectName(String value) => value.isEmpty ? '未记录项目' : p.basename(value);

class StatisticsPage extends StatefulWidget {
  final AppController c;
  const StatisticsPage(this.c, {super.key});
  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  bool sessions = true;
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final s = c.summary;
    return canvas(
      (height) => Column(
        children: [
          SizedBox(height: 51, child: PeriodStrip(c, statistics: true)),
          SizedBox(height: 12),
          SizedBox(
            height: 84,
            child: split([
              NumberCard(
                '成本估算',
                money(s),
                LucideIcons.circleDollarSign,
                compactCentered: true,
                onTap: s.fullyPriced ? null : () => c.navigate(4),
              ),
              NumberCard(
                '记录次数',
                '${s.requests}',
                LucideIcons.activity,
                compactCentered: true,
              ),
              LocalizedTooltip(
                message: '缓存命中率 = 缓存命中 Token ÷ 输入 Token（含缓存），不计输出 Token。没有输入用量时显示 —。',
                child: NumberCard(
                  '缓存命中率',
                  s.cacheHitPercent == null
                      ? '—'
                      : '${s.cacheHitPercent!.toStringAsFixed(1)}%',
                  LucideIcons.database,
                  compactCentered: true,
                ),
              ),
              NumberCard(
                '累计 Token',
                compact(s.total),
                LucideIcons.fileText,
                compactCentered: true,
              ),
            ]),
          ),
          SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: split(
              [
                Panel(
                  padding: EdgeInsets.all(12),
                  child: Column(
                    children: [
                      MiniHeading('每日用量', trailing: ChipLabel('Token')),
                      SizedBox(height: 10),
                      Expanded(
                        child: c.events.isEmpty
                            ? EmptyState(
                                '暂无统计',
                                c.isClaude
                                    ? c.claudeEmptyUsageText
                                    : '选择其他时间范围，或同步本机记录。',
                                onTap: c.isClaude ? () => c.navigate(4) : null,
                              )
                            : UsageChart(c.values(), c.now, showDates: false),
                      ),
                    ],
                  ),
                ),
                Panel(
                  padding: EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MiniHeading('Token 构成'),
                      SizedBox(height: 10),
                      _tokenRow('输入（含缓存）', s.input, s.total),
                      SizedBox(height: 8),
                      _tokenRow('输出', s.output, s.total),
                      Spacer(),
                      Divider(height: 14),
                      Row(
                        children: [
                          label('合计', color: themeColor(context, C.muted)),
                          Spacer(),
                          label(compact(s.total), weight: FontWeight.w600),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              flex: [7, 4],
            ),
          ),
          SizedBox(height: 12),
          Expanded(
            child: Panel(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Segments(
                        ['用量明细', '项目用量 ${s.projects}'],
                        sessions ? 0 : 1,
                        (i) => setState(() => sessions = i == 0),
                      ),
                      Spacer(),
                      TextButton.icon(
                        onPressed: () => c.export(),
                        icon: Icon(LucideIcons.share, size: 16),
                        label: LocalizedText('导出'),
                      ),
                    ],
                  ),
                  SizedBox(height: 7),
                  Expanded(child: _table(context, c, s)),
                ],
              ),
            ),
          ),
        ],
      ),
      minimum: 560,
    );
  }

  Widget _tokenRow(String title, int value, int total) => Builder(
    builder: (context) => Column(
      children: [
        Row(
          children: [
            Expanded(
              child: label(
                title,
                size: 13,
                color: themeColor(context, C.muted),
              ),
            ),
            label(compact(value), size: 17, weight: FontWeight.w600),
          ],
        ),
        SizedBox(height: 5),
        QuotaBar(
          total == 0 ? 0 : (value / total * 100).round(),
          warnLow: false,
        ),
      ],
    ),
  );
  Widget _table(BuildContext context, AppController c, UsageSummary summary) {
    if (sessions) {
      return UsageDetailsTable(
        events: summary.events,
        onSelect: (e) => showSession(context, e),
        emptyMessage: c.isClaude ? c.claudeEmptyUsageText : null,
        onEmptyTap: c.isClaude ? () => c.navigate(4) : null,
      );
    }
    if (summary.events.isEmpty) {
      return EmptyState(
        '暂无记录',
        c.isClaude ? c.claudeEmptyUsageText : '真实用量会在同步后显示。',
        onTap: c.isClaude ? () => c.navigate(4) : null,
      );
    }
    final projects = summary.grouped.entries.toList()
      ..sort(
        (a, b) =>
            UsageSummary(b.value).total.compareTo(UsageSummary(a.value).total),
      );
    final rows = sessions ? summary.events.take(100).toList() : projects;
    Widget cells(List<Widget> children, {bool header = false}) => Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: header ? themeColor(context, C.bg) : null,
        borderRadius: header ? BorderRadius.circular(9) : null,
        border: header
            ? null
            : Border(bottom: BorderSide(color: themeColor(context, C.line))),
      ),
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++)
            Expanded(
              flex: i == 0
                  ? 4
                  : i == 4
                  ? 3
                  : 2,
              child: children[i],
            ),
        ],
      ),
    );
    return Column(
      children: [
        cells([
          for (final t in [
            sessions ? '会话 / 项目' : '项目',
            sessions ? '时间' : '记录次数',
            '输入 Token',
            '输出 Token',
            '成本估算',
          ])
            label(t, size: 11, color: themeColor(context, C.muted)),
        ], header: true),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final e = sessions ? rows[i] as UsageEvent : null;
              final entry = sessions
                  ? null
                  : rows[i] as MapEntry<String, List<UsageEvent>>;
              final s = UsageSummary(e == null ? entry!.value : [e]);
              final name = projectName(e?.project ?? entry!.key);
              return InkWell(
                onTap: () => showSession(context, e ?? entry!.value.first),
                child: cells([
                  Row(
                    children: [
                      Icon(
                        LucideIcons.folder,
                        size: 16,
                        color: themeColor(context, C.muted),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: label(
                          name,
                          size: 12,
                          localize: (e?.project ?? entry!.key).isEmpty,
                        ),
                      ),
                    ],
                  ),
                  label(
                    e == null ? '${s.requests}' : clockText(e.at),
                    size: 12,
                  ),
                  label(compact(s.input), size: 12),
                  label(compact(s.output), size: 12),
                  label(
                    s.cost == null ? '未配置单价' : money(s),
                    size: 12,
                    color: s.cost == null
                        ? themeColor(context, C.muted)
                        : themeColor(context, C.ink),
                  ),
                ]),
              );
            },
          ),
        ),
      ],
    );
  }
}

Future<void> showSession(
  BuildContext context,
  UsageEvent event, {
  bool latestInSession = false,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: LocalizedText(
      projectName(event.project),
      localize: event.project.isEmpty,
    ),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (latestInSession)
            label('最近一条用量记录', size: 12, color: themeColor(context, C.muted)),
          _detail('时间', event.at.toLocal().toString()),
          _detail('模型', event.model, localizeValue: false),
          _detail('新增输入', detailTokenCount(event.freshInput)),
          _detail('输入（含缓存）', compact(event.tokens.input)),
          _detail('其中缓存', compact(event.tokens.cached)),
          if (event.tokens.cacheCreation > 0)
            _detail('其中缓存写入', compact(event.tokens.cacheCreation)),
          _detail('输出', compact(event.tokens.output)),
          _detail('其中推理', compact(event.tokens.reasoning)),
          _detail('速度', speedText(event)),
          _detail('首字时间', firstTokenText(event)),
          _detail(
            '成本估算',
            event.cost == null
                ? '未配置参考价格'
                : '\$${event.cost!.toStringAsFixed(6)}',
          ),
          SizedBox(height: 8),
          label(
            '仅保存统计字段，不显示对话正文。',
            size: 12,
            color: themeColor(context, C.muted),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: LocalizedText('关闭'),
      ),
    ],
  ),
);
