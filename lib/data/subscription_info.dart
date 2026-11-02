import 'models.dart';

enum SubscriptionTone { neutral, blue, gold }

String subscriptionDateLabel(AccountSnapshot? account) {
  if (account?.subscriptionExpiresAt != null) return '订阅有效期';
  if (account?.subscriptionDates?.periodEndsAt != null) return '订阅周期（缓存）';
  if (account?.subscriptionDates?.startedAt != null) return '订阅开始（本机）';
  return '订阅有效期';
}

String _dateText(DateTime value) {
  final local = value.toLocal();
  return '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
}

String subscriptionDateExplanation(AccountSnapshot? account, DateTime now) {
  if (account?.subscriptionExpiresAt != null) {
    return '账号接口提供的订阅有效期；额度恢复时间和登录凭证有效期不代表订阅到期。';
  }
  final dates = account?.subscriptionDates;
  if (dates == null) return '当前数据源未提供订阅日期；可在官方订阅管理中核对。';
  final lines = <String>[
    dates.source == 'codexLoginCache'
        ? '来源：本机 Codex 登录缓存的订阅字段。'
        : '来源：Claude 本机配置的订阅元数据。',
    if (dates.startedAt != null) '订阅开始：${_dateText(dates.startedAt!)}',
    if (dates.periodEndsAt != null) '本期截至：${_dateText(dates.periodEndsAt!)}',
    if (dates.lastCheckedAt != null)
      '元数据核对时间：${_dateText(dates.lastCheckedAt!)}',
    if (dates.periodEndsAt != null)
      '周期结束不等于停止订阅；自动续费及实际状态以官方账单为准。'
    else
      '未提供计费周期和结束日，未按一个月推算到期。',
    if (dates.periodEndsAt?.isBefore(now) == true) '缓存日期已过，等待原工具更新；不据此判定订阅过期。',
  ];
  return lines.join('\n');
}

String subscriptionValidityText(AccountSnapshot? account, DateTime now) {
  if (account?.authMode == 'apiKey' || account?.authMode == 'thirdParty') {
    return '不适用';
  }
  if (account?.signedIn != true) return '未登录';
  final end = account?.subscriptionExpiresAt?.toLocal();
  if (end != null) {
    final date =
        '${end.year}.${end.month.toString().padLeft(2, '0')}.${end.day.toString().padLeft(2, '0')}';
    return end.isAfter(now) ? date : '$date（已到期）';
  }
  final info = SubscriptionInfo.read(account, now);
  if (info.label == '订阅过期') return '已过期';
  if (info.label == '无订阅' || info.label == 'Free') return '无订阅';
  final dates = account?.subscriptionDates;
  if (dates?.periodEndsAt != null) {
    final date = _dateText(dates!.periodEndsAt!);
    return dates.periodEndsAt!.isAfter(now) ? date : '$date（待更新）';
  }
  if (dates?.startedAt != null) return _dateText(dates!.startedAt!);
  return '接口未提供';
}

String quotaResetText(AccountSnapshot? account) {
  if (account?.authMode == 'claude') return '不适用';
  if (account?.authMode == 'apiKey' || account?.authMode == 'thirdParty') {
    return '不适用';
  }
  if (account?.signedIn != true) return '未登录';
  final count = account?.availableQuotaResets;
  if (count == null) return '接口未提供';
  return count == 0 ? '暂无可用次数' : '$count 次可用';
}

class SubscriptionInfo {
  final String label;
  final SubscriptionTone tone;
  final bool isPro;
  const SubscriptionInfo(this.label, this.tone, {this.isPro = false});
  static SubscriptionInfo read(AccountSnapshot? account, DateTime now) {
    const neutral = SubscriptionTone.neutral;
    const blue = SubscriptionTone.blue;
    const gold = SubscriptionTone.gold;
    final state = account?.subscriptionStatus?.toLowerCase();
    if (['expired', 'ended'].contains(state) ||
        (account?.subscriptionExpiresAt != null &&
            !account!.subscriptionExpiresAt!.isAfter(now))) {
      return const SubscriptionInfo('订阅过期', neutral);
    }
    final plan = (account?.plan ?? '').toLowerCase().replaceAll(
      RegExp(r'[\s_\-]'),
      '',
    );
    return switch (plan) {
      'claudefree' => const SubscriptionInfo('Free', neutral),
      'claudepro' => const SubscriptionInfo('Pro', blue),
      'claudemax5' => const SubscriptionInfo('Max X5', gold),
      'claudemax20' => const SubscriptionInfo('Max X20', gold),
      'claudemax' => const SubscriptionInfo('Max', gold),
      'claudeultra' => const SubscriptionInfo('Ultra', gold),
      'claudeteam' => const SubscriptionInfo('Team', blue),
      'claudeenterprise' => const SubscriptionInfo('Enterprise', blue),
      'free' ||
      'none' ||
      'nosubscription' => const SubscriptionInfo('无订阅', neutral),
      'expired' ||
      'subscriptionexpired' => const SubscriptionInfo('订阅过期', neutral),
      'go' => const SubscriptionInfo('GO', blue),
      'plus' => const SubscriptionInfo('Plus', blue),
      'prolite' ||
      'pro5x' ||
      'prox5' => const SubscriptionInfo('Pro X5', gold, isPro: true),
      'pro' ||
      'pro20x' ||
      'prox20' => const SubscriptionInfo('Pro X20', gold, isPro: true),
      'promax' ||
      'pro50x' ||
      'prox50' => const SubscriptionInfo('Pro X50', gold, isPro: true),
      'business' ||
      'selfservebusinessprolite' ||
      'selfservebusinessusagebased' => const SubscriptionInfo('Business', blue),
      'team' => const SubscriptionInfo('Team', blue),
      'enterprise' ||
      'ent26' ||
      'enterprisecbpautomation' ||
      'enterprisecbpusagebased' => const SubscriptionInfo('Enterprise', blue),
      'edu' || 'eduplus' || 'edupro' => const SubscriptionInfo('Edu', blue),
      _ =>
        plan.startsWith('pro')
            ? const SubscriptionInfo('Pro（档位未知）', gold, isPro: true)
            : SubscriptionInfo(
                account?.authMode == 'apiKey'
                    ? 'API Key 模式'
                    : account?.authMode == 'thirdParty'
                    ? '第三方认证'
                    : '订阅未知',
                neutral,
              ),
    };
  }
}
