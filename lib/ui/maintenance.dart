import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app_info.dart';
import '../controller.dart';
import '../data/app_updates.dart';
import '../data/connection_diagnostics.dart';
import '../data/native_bridge.dart';
import 'localized.dart';
import 'widgets.dart';

class ConnectionHealthPanel extends StatelessWidget {
  final AppController c;
  const ConnectionHealthPanel(this.c, {super.key});
  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: MiniHeading('连接诊断', icon: LucideIcons.stethoscope)),
            ActionPill(
              c.checkingConnection ? '正在检测…' : '开始检测',
              onTap: c.busy || c.demo ? null : c.runConnectionChecks,
              primary: true,
            ),
          ],
        ),
        const SizedBox(height: 10),
        label(
          '逐项检查所选工具、配置目录、登录、本机日志和额度来源。',
          size: 12,
          color: themeColor(context, C.muted),
          lines: 3,
        ),
        const SizedBox(height: 12),
        LocalizedText(
          c.profile.root,
          localize: false,
          style: TextStyle(fontSize: 12, color: themeColor(context, C.muted)),
        ),
        if (c.checkingConnection) ...[
          const SizedBox(height: 14),
          const LinearProgressIndicator(),
        ],
        if (c.connectionReport case final report?
            when report.scope == c.profile.scope) ...[
          const SizedBox(height: 14),
          label(
            '检测时间：${report.checkedAt.toLocal().toString().split('.').first}',
            size: 11,
            color: themeColor(context, C.muted),
            lines: 2,
          ),
          if (report.executable != null) ...[
            const SizedBox(height: 6),
            LocalizedText(
              report.executable!,
              localize: false,
              style: TextStyle(
                fontSize: 12,
                color: themeColor(context, C.muted),
              ),
            ),
          ],
          if (report.email != null) ...[
            const SizedBox(height: 6),
            LocalizedText(
              report.email!,
              localize: false,
              style: TextStyle(
                fontSize: 12,
                color: themeColor(context, C.muted),
              ),
            ),
          ],
          if (c.isClaude) ...[
            const SizedBox(height: 10),
            label(
              '今日可计价记录：${c.today.pricedCount}/${c.today.requests}',
              size: 12,
            ),
            if (c.latestUsageDate case final day?)
              label(
                '最近导入记录：${day.toIso8601String().substring(0, 10)}',
                size: 12,
              ),
            LocalizedText('桌面 Code 请核对会话环境。本机使用所选配置目录，SSH 和云端会话需在对应运行环境核对日志。'),
          ],
          for (final check in report.checks) ...[
            const Divider(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  switch (check.state) {
                    CheckState.passed => LucideIcons.circleCheck,
                    CheckState.failed => LucideIcons.circleX,
                    CheckState.warning => LucideIcons.circleAlert,
                    CheckState.skipped => LucideIcons.circleMinus,
                  },
                  size: 18,
                  color: themeColor(context, switch (check.state) {
                    CheckState.passed => C.green,
                    CheckState.failed => Color(0xFFE5484D),
                    CheckState.warning => C.amber,
                    CheckState.skipped => C.muted,
                  }),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      label(check.title, weight: FontWeight.w500),
                      const SizedBox(height: 5),
                      LocalizedText(
                        check.detail,
                        style: TextStyle(
                          fontSize: 12,
                          color: themeColor(context, C.muted),
                        ),
                      ),
                    ],
                  ),
                ),
                if (check.action != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: c.busy
                        ? null
                        : () => _action(context, check.action!),
                    child: LocalizedText(switch (check.action!) {
                      CheckAction.executable => '指定路径',
                      CheckAction.directory => '选择目录',
                      CheckAction.login =>
                        c.isClaude ? '登录 Claude Code' : '登录指引',
                      CheckAction.refresh => '重新检测',
                      CheckAction.collector => '采集设置',
                    }),
                  ),
                ],
              ],
            ),
          ],
        ],
      ],
    ),
  );
  void _action(BuildContext context, CheckAction action) {
    switch (action) {
      case CheckAction.executable:
        c.chooseExecutable();
      case CheckAction.directory:
        c.addProfile();
      case CheckAction.login:
        if (c.isClaude) {
          c.loginClaude();
        } else {
          NativeBridge.call('openUrl', {
            'url':
                'https://github.com/${AppUpdates.repository}/blob/main/docs/quick-start.md#connect-gpt',
          });
        }
      case CheckAction.refresh:
        c.runConnectionChecks();
      case CheckAction.collector:
        showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const LocalizedText('状态栏额度采集'),
            content: const LocalizedText(
              '采集仅用于终端会话，会保留原状态栏。启用后新开 Claude Code 会话并正常使用，再回到这里重新检测。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const LocalizedText('关闭'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  c.setClaudeCollector(true);
                },
                child: const LocalizedText('启用采集'),
              ),
            ],
          ),
        );
    }
  }
}

class WindowsBehaviorPanel extends StatelessWidget {
  final AppController c;
  const WindowsBehaviorPanel(this.c, {super.key});
  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MiniHeading('Windows 运行方式', icon: LucideIcons.monitor),
        const SizedBox(height: 18),
        _row(
          context,
          '关闭窗口后继续运行',
          '关闭后保留在系统托盘；右键托盘菜单可彻底退出。',
          Toggle(c.closeToTray, c.startupBusy ? null : c.setCloseToTray),
        ),
        const Divider(height: 26),
        _row(
          context,
          '登录 Windows 时启动',
          '仅在主动开启后生效，以托盘方式启动；可随时关闭。',
          Toggle(c.launchAtLogin, c.startupBusy ? null : c.setLaunchAtLogin),
        ),
      ],
    ),
  );
  Widget _row(
    BuildContext context,
    String title,
    String detail,
    Widget control,
  ) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label(title, weight: FontWeight.w500),
            const SizedBox(height: 6),
            LocalizedText(
              detail,
              style: TextStyle(
                fontSize: 12,
                color: themeColor(context, C.muted),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 14),
      control,
    ],
  );
}

class UpdatesPanel extends StatelessWidget {
  final AppController c;
  const UpdatesPanel(this.c, {super.key});
  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: MiniHeading('软件更新', icon: LucideIcons.download)),
            ActionPill(
              c.checkingUpdates ? '正在检查…' : '检查更新',
              onTap: c.checkingUpdates ? null : c.checkUpdates,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: label('当前版本：${AppInfo.version} Alpha', size: 12, lines: 2),
            ),
            Segments(
              ['Alpha 渠道', '稳定渠道'],
              c.updateChannel.index,
              c.checkingUpdates
                  ? (_) {}
                  : (i) => c.setUpdateChannel(UpdateChannel.values[i]),
            ),
          ],
        ),
        const SizedBox(height: 12),
        label(
          '仅在点击时访问 GitHub 获取版本信息，不发送账号、目录或用量。',
          size: 12,
          color: themeColor(context, C.muted),
          lines: 3,
        ),
        if (c.updateMessage != null) ...[
          const SizedBox(height: 12),
          label(c.updateMessage!, size: 12, lines: 3),
        ],
        if (c.availableUpdate case final update?) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: label(
                  update.tag,
                  localize: false,
                  weight: FontWeight.w600,
                ),
              ),
              TextButton(
                onPressed: () => _notes(context, update),
                child: const LocalizedText('更新说明'),
              ),
              TextButton(
                onPressed: () => NativeBridge.call('openUrl', {
                  'url': (update.download ?? update.page).toString(),
                }),
                child: LocalizedText(update.download == null ? '查看版本' : '下载更新'),
              ),
            ],
          ),
          if (update.download == null)
            label('该版本尚无本平台安装包，可查看版本说明。', size: 12, lines: 2),
        ],
        if (c.updateMessage != null && c.availableUpdate == null)
          TextButton(
            onPressed: () => NativeBridge.call('openUrl', {
              'url': AppUpdates.page.toString(),
            }),
            child: const LocalizedText('打开版本页面'),
          ),
      ],
    ),
  );
  Future<void> _notes(BuildContext context, AppUpdate update) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(update.tag),
          content: SizedBox(
            width: 600,
            height: 340,
            child: SingleChildScrollView(
              child: SelectableText(
                update.notes.isEmpty
                    ? AppLocale.text(context, '此版本未提供更新说明。')
                    : update.notes,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const LocalizedText('关闭'),
            ),
          ],
        ),
      );
}
