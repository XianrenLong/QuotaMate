import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app_info.dart';
import '../controller.dart';
import '../data/native_bridge.dart';
import 'pages.dart';
import 'settings.dart';
import 'widgets.dart';
import 'localized.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import '../l10n/strings.dart';
import '../data/appearance.dart';
import '../data/provider.dart';

class QuotaMateApp extends StatelessWidget {
  final AppController controller;
  const QuotaMateApp({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => AppLocale(
      strings: controller.strings,
      child: MaterialApp(
        locale: controller.language == AppLanguage.en
            ? Locale('en', 'US')
            : Locale('zh', 'CN'),
        supportedLocales: [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        debugShowCheckedModeBanner: false,
        title: AppInfo.name,
        theme: createAppTheme(Brightness.light),
        darkTheme: createAppTheme(Brightness.dark),
        themeMode: switch (controller.appearance) {
          AppAppearance.light => ThemeMode.light,
          AppAppearance.dark => ThemeMode.dark,
          AppAppearance.system => ThemeMode.system,
        },
        themeAnimationDuration: Duration(milliseconds: 180),
        home: AppShell(controller),
      ),
    ),
  );
}

class AppShell extends StatefulWidget {
  final AppController c;
  const AppShell(this.c, {super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool collapsed = false;
  static const names = ['统计', '总览', '账号', '提醒', '设置'];
  static const icons = [
    LucideIcons.chartNoAxesCombined,
    LucideIcons.layoutGrid,
    LucideIcons.userRound,
    LucideIcons.bell,
    LucideIcons.settings,
  ];
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) => CallbackShortcuts(
        bindings: {
          SingleActivator(
            LogicalKeyboardKey.digit1,
            meta: Platform.isMacOS,
            control: !Platform.isMacOS,
          ): () =>
              c.navigate(0),
          SingleActivator(
            LogicalKeyboardKey.digit2,
            meta: Platform.isMacOS,
            control: !Platform.isMacOS,
          ): () =>
              c.navigate(1),
          SingleActivator(
            LogicalKeyboardKey.digit3,
            meta: Platform.isMacOS,
            control: !Platform.isMacOS,
          ): () =>
              c.navigate(2),
          SingleActivator(
            LogicalKeyboardKey.comma,
            meta: Platform.isMacOS,
            control: !Platform.isMacOS,
          ): () =>
              c.navigate(4),
          SingleActivator(
            LogicalKeyboardKey.keyR,
            meta: Platform.isMacOS,
            control: !Platform.isMacOS,
          ): () =>
              c.refresh(),
          SingleActivator(
            LogicalKeyboardKey.keyE,
            meta: Platform.isMacOS,
            control: !Platform.isMacOS,
          ): () =>
              c.export(),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Column(
              children: [
                if (Platform.isMacOS)
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanStart: (_) => NativeBridge.call('dragWindow'),
                    child: SizedBox(
                      height: 32,
                      child: Center(
                        child: label(
                          AppInfo.name,
                          size: 11,
                          color: themeColor(context, C.muted),
                          localize: false,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: Duration(milliseconds: 170),
                        width: collapsed ? 70 : 202,
                        decoration: BoxDecoration(
                          color: themeColor(context, C.side),
                          border: Border(
                            right: BorderSide(
                              color: themeColor(context, Color(0xFFDAD8E2)),
                              width: .5,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: EdgeInsets.only(
                                left: 16,
                                top: 8,
                                bottom: 19,
                              ),
                              child: IconButton(
                                tooltip: AppLocale.text(
                                  context,
                                  collapsed ? '展开侧栏' : '收起侧栏',
                                ),
                                onPressed: () =>
                                    setState(() => collapsed = !collapsed),
                                icon: Icon(
                                  LucideIcons.panelLeft,
                                  size: 18,
                                  color: themeColor(context, C.muted),
                                ),
                              ),
                            ),
                            for (var i = 0; i < names.length; i++)
                              Padding(
                                padding: EdgeInsets.fromLTRB(10, 0, 10, 7),
                                child: Semantics(
                                  selected: c.page == i,
                                  button: true,
                                  label: AppLocale.text(context, names[i]),
                                  child: Material(
                                    color: c.page == i
                                        ? themeColor(context, Color(0xFFD8D6E1))
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () => c.navigate(i),
                                      child: Container(
                                        height: 45,
                                        decoration: BoxDecoration(
                                          border: c.page == i
                                              ? Border(
                                                  left: BorderSide(
                                                    color: themeColor(
                                                      context,
                                                      C.blue,
                                                    ),
                                                    width: 3,
                                                  ),
                                                )
                                              : null,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        padding: EdgeInsets.symmetric(
                                          horizontal: collapsed ? 11 : 16,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              icons[i],
                                              size: 20,
                                              color: themeColor(context, C.ink),
                                            ),
                                            if (!collapsed) ...[
                                              SizedBox(width: 14),
                                              Expanded(
                                                child: label(
                                                  names[i],
                                                  weight: c.page == i
                                                      ? FontWeight.w600
                                                      : FontWeight.w400,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Spacer(),
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                collapsed ? 4 : 18,
                                0,
                                collapsed ? 4 : 10,
                                20,
                              ),
                              child: LayoutBuilder(
                                builder: (context, box) {
                                  final compact =
                                      collapsed || box.maxWidth < 135;
                                  final storage = InkWell(
                                    onTap: () => c.navigate(4),
                                    child: SizedBox(
                                      height: 36,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            LucideIcons.hardDrive,
                                            size: 18,
                                            color: themeColor(context, C.muted),
                                          ),
                                          if (!compact) ...[
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: label(
                                                '本地保存',
                                                size: 12,
                                                color: themeColor(
                                                  context,
                                                  C.muted,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                  final update = c.availableUpdate;
                                  final download = update == null
                                      ? null
                                      : Tooltip(
                                          message:
                                              '${c.strings.text("下载更新")} ${update.tag}',
                                          child: SizedBox(
                                            width: compact ? 34 : 62,
                                            height: 34,
                                            child: TextButton(
                                              key: const ValueKey(
                                                'sidebar-update',
                                              ),
                                              onPressed: () =>
                                                  NativeBridge.call('openUrl', {
                                                    'url':
                                                        (update.download ??
                                                                update.page)
                                                            .toString(),
                                                  }),
                                              style: TextButton.styleFrom(
                                                backgroundColor: themeColor(
                                                  context,
                                                  C.blue,
                                                ).withValues(alpha: .12),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 5,
                                                    ),
                                              ),
                                              child: FittedBox(
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      LucideIcons.download,
                                                      size: 15,
                                                    ),
                                                    if (!compact) ...[
                                                      const SizedBox(width: 3),
                                                      const LocalizedText('更新'),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                  if (compact)
                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [storage, ?download],
                                    );
                                  return Row(
                                    children: [
                                      Expanded(child: storage),
                                      ?download,
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(22, 0, 22, 0),
                          child: Column(
                            children: [
                              SizedBox(
                                height: 70,
                                child: Row(
                                  children: [
                                    label(
                                      names[c.page],
                                      size: 25,
                                      weight: FontWeight.w600,
                                    ),
                                    Spacer(),
                                    PopupMenuButton<String>(
                                      enabled: !c.busy,
                                      tooltip: AppLocale.text(
                                        context,
                                        '切换显示平台',
                                      ),
                                      color: themeColor(context, C.card),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      onSelected: c.busy
                                          ? null
                                          : (value) => c.selectProvider(
                                              value == 'claude'
                                                  ? AiProvider.claude
                                                  : AiProvider.gpt,
                                            ),
                                      itemBuilder: (_) => [
                                        PopupMenuItem(
                                          value: 'gpt',
                                          child: Row(
                                            children: [
                                              Icon(
                                                c.isClaude
                                                    ? LucideIcons.circle
                                                    : LucideIcons.check,
                                                size: 16,
                                              ),
                                              SizedBox(width: 10),
                                              LocalizedText('GPT'),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'claude',
                                          child: Row(
                                            children: [
                                              Icon(
                                                c.isClaude
                                                    ? LucideIcons.check
                                                    : LucideIcons.circle,
                                                size: 16,
                                              ),
                                              SizedBox(width: 10),
                                              LocalizedText('Claude'),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          enabled: false,
                                          child: LocalizedText('全部平台 · 后续接入'),
                                        ),
                                      ],
                                      child: Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: themeColor(context, C.card),
                                          border: Border.all(
                                            color: themeColor(context, C.line),
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            13,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            label(
                                              c.providerLabel,
                                              weight: FontWeight.w500,
                                            ),
                                            SizedBox(width: 17),
                                            Icon(
                                              LucideIcons.chevronDown,
                                              size: 16,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    IconButton.filledTonal(
                                      tooltip: AppLocale.text(
                                        context,
                                        Platform.isMacOS
                                            ? '刷新额度（⌘R）'
                                            : '刷新额度（Ctrl+R）',
                                      ),
                                      onPressed: c.busy
                                          ? null
                                          : () => c.refresh(),
                                      style: IconButton.styleFrom(
                                        backgroundColor: themeColor(
                                          context,
                                          C.card,
                                        ),
                                      ),
                                      icon: c.busy
                                          ? SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Icon(
                                              LucideIcons.refreshCw,
                                              size: 19,
                                            ),
                                    ),
                                    SizedBox(width: 10),
                                    LocalizedTooltip(
                                      message: c.status,
                                      child: InkWell(
                                        onTap: () => showSources(context, c),
                                        borderRadius: BorderRadius.circular(30),
                                        child: Container(
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            color: c.error != null
                                                ? themeColor(
                                                    context,
                                                    Color(0xFFFFEACD),
                                                  )
                                                : themeColor(
                                                    context,
                                                    Color(0xFFD7F2D2),
                                                  ),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            c.error != null
                                                ? LucideIcons.info
                                                : LucideIcons.check,
                                            size: 18,
                                            color: c.error != null
                                                ? themeColor(context, C.amber)
                                                : themeColor(
                                                    context,
                                                    Color(0xFF269B37),
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (c.error != null || c.message != null)
                                Padding(
                                  padding: EdgeInsets.only(bottom: 10),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 9,
                                    ),
                                    decoration: BoxDecoration(
                                      color: themeColor(
                                        context,
                                        Color(0xFFFFF4DF),
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          LucideIcons.info,
                                          size: 16,
                                          color: themeColor(context, C.amber),
                                        ),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: label(
                                            c.error ?? c.message!,
                                            size: 12,
                                            lines: 2,
                                          ),
                                        ),
                                        if (c.error != null)
                                          TextButton(
                                            onPressed: () => c.navigate(4),
                                            child: LocalizedText('查看设置'),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: switch (c.page) {
                                  0 => StatisticsPage(c),
                                  1 => OverviewPage(c),
                                  2 => AccountsPage(c),
                                  3 => AlertsPage(c),
                                  _ => SettingsPage(c),
                                },
                              ),
                              SizedBox(
                                height: 35,
                                child: Row(
                                  children: [
                                    DotLabel(
                                      '${c.providerLabel} · ${c.status}',
                                      color: c.error == null && !c.stale
                                          ? themeColor(context, C.green)
                                          : themeColor(context, C.amber),
                                    ),
                                    Spacer(),
                                    Flexible(
                                      child: label(
                                        c.page == 0
                                            ? '仅统计本机记录 · 估算不代表订阅扣费'
                                            : '本机历史记录与账号额度分别统计',
                                        size: 10,
                                        color: themeColor(context, C.muted),
                                      ),
                                    ),
                                    Spacer(),
                                    if (c.demo)
                                      TextButton(
                                        onPressed: c.busy
                                            ? null
                                            : () => c.setDemo(false),
                                        child: LocalizedText(
                                          '退出演示，读取真实数据',
                                          style: TextStyle(fontSize: 10),
                                        ),
                                      )
                                    else
                                      label(
                                        '本地运行',
                                        size: 10,
                                        color: themeColor(context, C.muted),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showSources(BuildContext context, AppController c) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: LocalizedText('数据来源'),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label('账号额度', weight: FontWeight.w600),
              SizedBox(height: 7),
              label(
                c.account?.source ?? '尚未获取',
                color: themeColor(context, C.muted),
              ),
              SizedBox(height: 7),
              label(
                c.demo
                    ? '这是示例账号，不是你的登录账号。'
                    : c.isClaude
                    ? '读取本机登录状态与已有额度快照，不主动查询 Claude 订阅接口。'
                    : '读取所选目录的 Codex CLI 登录；桌面应用独立切换的账号可能不同。',
                size: 12,
                color: themeColor(context, C.muted),
                lines: 3,
              ),
              label(
                c.account == null
                    ? (c.isClaude ? '请登录 Claude Code 后刷新。' : '请在 Codex 登录后刷新。')
                    : '采集于 ${c.account!.observed.toLocal()}',
                size: 12,
                color: themeColor(context, C.muted),
                lines: 2,
              ),
              SizedBox(height: 20),
              label('本机历史', weight: FontWeight.w600),
              SizedBox(height: 7),
              label(
                c.isClaude
                    ? '从 Claude Code 会话记录汇总，仅保存用量字段。'
                    : '从 Codex 会话记录汇总，仅保存用量字段。',
                color: themeColor(context, C.muted),
                lines: 2,
              ),
              label(
                '其他电脑和云端任务可能没有对应的本机记录。',
                size: 12,
                color: themeColor(context, C.muted),
                lines: 2,
              ),
              SizedBox(height: 20),
              label('费用估算', weight: FontWeight.w600),
              SizedBox(height: 7),
              label(
                '使用你配置的模型参考单价。缺少价格时保持未知；订阅额度不换算为美元。',
                size: 12,
                color: themeColor(context, C.muted),
                lines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: LocalizedText('知道了'),
          ),
        ],
      ),
    );
