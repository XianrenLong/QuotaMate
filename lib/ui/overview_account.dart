import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../controller.dart';
import '../data/subscription_info.dart';
import 'subscription_badge.dart';
import 'widgets.dart';
import 'localized.dart';

class OverviewAccountCard extends StatelessWidget {
  final AppController c;
  const OverviewAccountCard(this.c, {super.key});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(22),
    child: Stack(
      fit: StackFit.expand,
      children: [
        FractionallySizedBox(
          widthFactor: 1.055,
          alignment: Alignment.centerLeft,
          child: Image.asset(
            Theme.of(context).brightness == Brightness.dark
                ? 'assets/branding/account-card-soft-curve-dark.png'
                : 'assets/branding/account-card-soft-curve.png',
            fit: BoxFit.fill,
            excludeFromSemantics: true,
            filterQuality: FilterQuality.high,
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 67, child: OverviewAccountDetails(c)),
            Expanded(flex: 33, child: _QuotaRing(c)),
          ],
        ),
      ],
    ),
  );
}

class _QuotaRing extends StatelessWidget {
  final AppController c;
  const _QuotaRing(this.c);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final diameter = math.min(
        constraints.maxWidth - 26,
        constraints.maxHeight - 56,
      );
      final remaining = c.presentedWindow?.remaining;
      final historical = c.quotaHistorical;
      return Center(
        child: LocalizedTooltip(
          message: remaining == null
              ? c.isClaude
                    ? c.quotaSampleDetails
                    : c.stale
                    ? '历史快照，请刷新确认当前额度。'
                    : '当前额度窗口暂不可用。'
              : historical
              ? '历史快照剩余 $remaining% · 记录于 ${c.account!.observed.toLocal()}'
              : '当前额度窗口剩余 $remaining%',
          child: Semantics(
            label: AppLocale.text(
              context,
              remaining == null
                  ? '额度暂不可用'
                  : historical
                  ? '历史快照剩余 $remaining%'
                  : '当前额度窗口剩余 $remaining%',
            ),
            child: SizedBox.square(
              dimension: diameter,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: CircularProgressIndicator(
                      value: remaining == null ? 0 : remaining / 100,
                      strokeWidth: diameter * .045,
                      strokeCap: StrokeCap.round,
                      backgroundColor: Colors.white.withValues(alpha: .17),
                      color: Colors.white,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: remaining?.toString() ?? '—'),
                            if (remaining != null)
                              TextSpan(
                                text: '%',
                                style: TextStyle(fontSize: diameter * .26),
                              ),
                          ],
                        ),
                        style: TextStyle(
                          fontSize: diameter * .36,
                          height: 1.05,
                          color: Colors.white,
                          fontWeight: FontWeight.w300,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      SizedBox(height: 8),
                      label(
                        remaining == null
                            ? '暂不可用'
                            : historical
                            ? '快照剩余'
                            : '剩余',
                        size: 12,
                        color: Colors.white.withValues(alpha: .92),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class OverviewAccountDetails extends StatelessWidget {
  final AppController c;
  const OverviewAccountDetails(this.c, {super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 300;
      final email =
          c.account?.email ??
          (c.account?.authMode == 'apiKey' ? 'API Key 模式' : '尚未获取账号邮箱');
      final identity = LocalizedTooltip(
        message: c.stale ? '$email\n历史快照，请刷新确认当前账号。' : email,
        child: Row(
          children: [
            Container(
              width: compact ? 28 : 34,
              height: compact ? 28 : 34,
              decoration: BoxDecoration(
                color: themeColor(context, Color(0xFFECF0FF)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                LucideIcons.mail,
                size: compact ? 18 : 22,
                color: themeColor(context, C.muted),
              ),
            ),
            SizedBox(width: compact ? 8 : 10),
            Expanded(
              child: compact
                  ? label(
                      email,
                      size: 12,
                      weight: FontWeight.w600,
                      localize: false,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        label(
                          email,
                          size: 14,
                          weight: FontWeight.w600,
                          localize: false,
                        ),
                        SizedBox(height: 5),
                        SubscriptionBadge(
                          c.subscription,
                          historical: c.stale,
                          compact: true,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      );
      return Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 14 : 22,
          16,
          compact ? 10 : 26,
          compact ? 16 : 22,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (compact)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  identity,
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SubscriptionBadge(
                            c.subscription,
                            historical: c.stale,
                            compact: true,
                          ),
                        ),
                      ),
                      SizedBox(width: 4),
                      AccountSwitcher(c),
                    ],
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(child: identity),
                  SizedBox(width: 8),
                  AccountSwitcher(c),
                ],
              ),
            Divider(height: 1),
            LocalizedTooltip(
              message: c.demo
                  ? '演示有效期。'
                  : c.account?.subscriptionExpiresAt != null
                  ? '账号快照提供的订阅有效期；额度恢复时间和重置机会有效期均不代表订阅到期。'
                  : c.isClaude
                  ? 'Claude 未提供订阅到期日，可在官方订阅设置中核对。'
                  : '当前账号查询未提供订阅到期日；可在 ChatGPT 的订阅管理中核对。额度恢复时间和重置机会有效期均不代表订阅到期。',
              child: Row(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: compact ? 116 : 150),
                    child: label(
                      '订阅有效期',
                      size: 12,
                      color: themeColor(context, C.muted),
                    ),
                  ),
                  SizedBox(width: compact ? 10 : 28),
                  Expanded(
                    child: label(
                      subscriptionValidityText(c.account, c.now),
                      size: 12,
                      weight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1),
            if (c.isClaude)
              Row(
                children: [
                  Expanded(
                    child: LocalizedTooltip(
                      message: c.quotaSampleDetails,
                      child: label(
                        c.demo
                            ? '演示数据'
                            : c.claudeSignedIn
                            ? c.quotaSampleLabel
                            : 'Claude Code 未登录',
                        size: compact ? 11 : 12,
                        color: themeColor(context, C.muted),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  ClaudeConnectButton(c),
                ],
              )
            else
              LocalizedTooltip(
                message: '${c.stale ? '历史快照；' : ''}显示当前可用的额度重置次数。接口未提供不代表次数为零。',
                child: Row(
                  children: [
                    if (!compact) ...[
                      Icon(
                        LucideIcons.history,
                        size: 18,
                        color: themeColor(context, C.muted),
                      ),
                      SizedBox(width: 8),
                    ],
                    label(
                      '额度重置',
                      size: compact ? 11 : 12,
                      color: themeColor(context, C.muted),
                    ),
                    SizedBox(width: compact ? 6 : 12),
                    if (!compact) ...[
                      Container(
                        width: 1,
                        height: 15,
                        color: themeColor(context, C.line),
                      ),
                      SizedBox(width: 12),
                    ],
                    Expanded(
                      child: label(
                        quotaResetText(c.account),
                        size: compact ? 11 : 12,
                        weight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 8),
                    QuotaResetButton(c, prominent: true, compact: compact),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}

class ClaudeConnectButton extends StatelessWidget {
  final AppController c;
  const ClaudeConnectButton(this.c, {super.key});
  @override
  Widget build(BuildContext context) => LocalizedTooltip(
    message: c.connectingClaude
        ? '停止等待不会关闭官方登录终端；完成后可手动刷新。'
        : c.claudeSignedIn
        ? '读取已有状态栏或桌面额度快照；不主动查询 Claude 订阅接口。'
        : '在终端打开 Claude Code 官方登录，账号和授权码仅由官方工具处理。',
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 132),
      child: TextButton(
        onPressed: c.demo
            ? null
            : c.connectingClaude
            ? c.cancelClaudeLogin
            : c.busy
            ? null
            : !c.claudeSignedIn
            ? c.loginClaude
            : () => c.refresh(),
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: primaryFill(context),
          disabledForegroundColor: themeColor(context, C.muted),
          disabledBackgroundColor: themeColor(context, C.track),
          minimumSize: const Size(88, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          textStyle: const TextStyle(fontFamily: 'PingFang SC', fontSize: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: LocalizedText(
          c.connectingClaude
              ? '停止等待'
              : !c.claudeSignedIn
              ? '登录 Claude Code'
              : '读取本地数据',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ),
  );
}

class QuotaResetButton extends StatelessWidget {
  final AppController c;
  final bool prominent, compact;
  const QuotaResetButton(
    this.c, {
    super.key,
    this.prominent = false,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) => LocalizedTooltip(
    message: c.canResetQuota
        ? '使用 1 次重置机会，重置后更新额度。'
        : c.resettingQuota
        ? '正在重置额度…'
        : c.demo
        ? '演示模式不使用真实重置次数。'
        : c.stale
        ? '请先刷新，确认当前账号与可用次数。'
        : '当前没有已确认的可用重置次数。',
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 84 : 112),
      child: TextButton(
        onPressed: c.canResetQuota ? c.resetQuota : null,
        style: TextButton.styleFrom(
          minimumSize: prominent ? Size(compact ? 72 : 104, 32) : Size.zero,
          padding: EdgeInsets.symmetric(
            horizontal: prominent ? (compact ? 10 : 18) : 8,
            vertical: prominent ? 8 : 6,
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: prominent
              ? Colors.white
              : themeColor(context, C.blue),
          backgroundColor: prominent
              ? primaryFill(context)
              : themeColor(context, Color(0xFFE7EEFF)),
          disabledForegroundColor: themeColor(context, C.muted),
          disabledBackgroundColor: themeColor(context, C.bg),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: TextStyle(
            fontSize: compact ? 11 : 12,
            fontWeight: FontWeight.w500,
            height: 1.2,
            fontFamily: 'PingFang SC',
            fontFamilyFallback: [
              '.AppleSystemUIFont',
              'Microsoft YaHei',
              'Arial',
            ],
          ),
        ),
        child: LocalizedText(
          c.resettingQuota ? '重置中…' : '重置额度',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ),
  );
}

class AccountSwitcher extends StatelessWidget {
  final AppController c;
  const AccountSwitcher(this.c, {super.key});

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    enabled: !c.busy,
    tooltip: AppLocale.text(context, '切换本软件查看的账号'),
    position: PopupMenuPosition.under,
    color: themeColor(context, C.card),
    constraints: BoxConstraints(minWidth: 260, maxWidth: 360),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
    onSelected: (index) async {
      if (index == -1) {
        await c.addProfile();
      } else if (index == -2) {
        c.navigate(2);
      } else if (index != c.selected) {
        await c.selectProfile(index);
      }
    },
    itemBuilder: (_) => [
      for (var i = 0; i < c.profiles.length; i++)
        PopupMenuItem(
          value: i,
          child: Row(
            children: [
              Icon(
                i == c.selected ? LucideIcons.check : LucideIcons.userRound,
                size: 17,
                color: i == c.selected
                    ? themeColor(context, C.blue)
                    : themeColor(context, C.muted),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    label(
                      c.accountForProfile(i)?.email ?? c.profiles[i].label,
                      size: 13,
                      weight: FontWeight.w500,
                    ),
                    label(
                      i == c.selected ? '当前查看' : c.profiles[i].label,
                      size: 11,
                      color: themeColor(context, C.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      PopupMenuDivider(),
      PopupMenuItem(
        value: -1,
        enabled: !c.demo,
        child: LocalizedText('添加账号数据源'),
      ),
      PopupMenuItem(value: -2, child: LocalizedText('管理账号')),
    ],
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 112),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.repeat2,
              size: 14,
              color: c.busy
                  ? themeColor(context, C.muted)
                  : themeColor(context, C.blue),
            ),
            SizedBox(width: 4),
            Flexible(
              child: label(
                '切换账号',
                size: 12,
                color: c.busy
                    ? themeColor(context, C.muted)
                    : themeColor(context, C.blue),
                weight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
