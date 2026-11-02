import 'models.dart';

enum SubscriptionTone { neutral, blue, gold }

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
  if (info.label == '无订阅') return '无订阅';
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
