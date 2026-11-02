import 'package:flutter_test/flutter_test.dart';
import 'package:quota_mate/data/models.dart';
import 'package:quota_mate/data/subscription_info.dart';

void main() {
  final now = DateTime(2026, 11, 1, 12);
  SubscriptionInfo info(String? plan, {String? status, DateTime? end}) =>
      SubscriptionInfo.read(
        AccountSnapshot(
          plan: plan,
          authMode: 'chatgpt',
          subscriptionStatus: status,
          subscriptionExpiresAt: end,
          observed: now,
        ),
        now,
      );
  test('protocol plan tiers map to the requested labels and colors', () {
    for (final pair in {
      'prolite': 'Pro X5',
      'pro': 'Pro X20',
      'promax': 'Pro X50',
      'pro_x5': 'Pro X5',
      'pro_x20': 'Pro X20',
      'pro_x50': 'Pro X50',
    }.entries) {
      final p = info(pair.key);
      expect(p.label, pair.value);
      expect(p.isPro, true);
      expect(p.tone, SubscriptionTone.gold);
    }
    for (final pair in {'go': 'GO', 'plus': 'Plus'}.entries) {
      expect(info(pair.key).label, pair.value);
      expect(info(pair.key).tone, SubscriptionTone.blue);
      expect(info(pair.key).isPro, false);
    }
    expect(info('free').label, '无订阅');
    expect(info('free').tone, SubscriptionTone.neutral);
    expect(info(null).label, '订阅未知');
  });
  test('only explicit expiry evidence changes subscription; cancellation can retain paid access', () {
    expect(info('plus', status: 'expired').label, '订阅过期');
    expect(
      info('pro', end: now.subtract(const Duration(seconds: 1))).tone,
      SubscriptionTone.neutral,
    );
    expect(
      info('pro', end: now.subtract(const Duration(seconds: 1))).isPro,
      false,
    );
    expect(
      info(
        'plus',
        status: 'canceled',
        end: now.add(const Duration(days: 1)),
      ).label,
      'Plus',
    );
  });
  test('subscription metadata survives cached snapshot serialization', () {
    final a = AccountSnapshot(
      plan: 'prolite',
      subscriptionStatus: 'active',
      subscriptionExpiresAt: now.add(const Duration(days: 1)),
      observed: now,
      availableQuotaResets: 2,
    );
    final b = AccountSnapshot.fromJson(a.toJson());
    expect(b.subscriptionExpiresAt, a.subscriptionExpiresAt);
    expect(b.subscriptionStatus, 'active');
    expect(b.availableQuotaResets, 2);
    expect(SubscriptionInfo.read(b, now).label, 'Pro X5');
  });
  test('reset count uses the authoritative summary and distinguishes zero from unknown', () {
    final account = <String, dynamic>{
      'account': {
        'type': 'chatgpt',
        'email': 'test@example.com',
        'planType': 'plus',
      },
    };
    AccountSnapshot read(dynamic credits) => AccountSnapshot.fromRpc(account, {
      'rateLimitsByLimitId': {
        'codex': {'planType': 'prolite'},
      },
      'rateLimitResetCredits': credits,
    }, observed: now);
    final snapshot = read({'availableCount': 3, 'credits': []});
    expect(snapshot.plan, 'prolite');
    expect(snapshot.availableQuotaResets, 3);
    expect(quotaResetText(snapshot), '3 次可用');
    expect(quotaResetText(read({'availableCount': 0})), '暂无可用次数');
    for (final credits in [
      null,
      {},
      {'availableCount': -1},
      {'availableCount': 1.5},
    ]) {
      expect(read(credits).availableQuotaResets, isNull);
      expect(quotaResetText(read(credits)), '接口未提供');
    }
    final legacy = snapshot.toJson()..remove('availableQuotaResets');
    expect(AccountSnapshot.fromJson(legacy).availableQuotaResets, isNull);
  });
  test('subscription validity never uses the quota reset date as expiry', () {
    final paid = AccountSnapshot(
      plan: 'plus',
      authMode: 'chatgpt',
      observed: now,
      primary: QuotaWindow(20, 300, now.add(const Duration(hours: 1))),
    );
    expect(subscriptionValidityText(paid, now), '接口未提供');
    final protocolAccount = AccountSnapshot.fromRpc(
      {
        'account': {
          'type': 'chatgpt',
          'email': 'sample@example.com',
          'planType': 'prolite',
          'workspaceName': null,
        },
      },
      {
        'rateLimits': {
          'primary': {
            'usedPercent': 35,
            'windowDurationMins': 10080,
            'resetsAt':
                now.add(const Duration(days: 3)).millisecondsSinceEpoch ~/ 1000,
          },
        },
        'rateLimitResetCredits': {
          'availableCount': 1,
          'credits': [
            {
              'expiresAt':
                  now.add(const Duration(days: 7)).millisecondsSinceEpoch ~/
                  1000,
            },
          ],
        },
      },
      observed: now,
    );
    expect(protocolAccount.subscriptionExpiresAt, isNull);
    expect(protocolAccount.availableQuotaResets, 1);
    expect(subscriptionValidityText(protocolAccount, now), '接口未提供');
    expect(
      subscriptionValidityText(
        AccountSnapshot(
          plan: 'plus',
          authMode: 'chatgpt',
          observed: now,
          subscriptionExpiresAt: DateTime(2026, 12, 1),
        ),
        now,
      ),
      '2026.12.01',
    );
    expect(
      subscriptionValidityText(
        AccountSnapshot(
          plan: 'plus',
          authMode: 'chatgpt',
          observed: now,
          subscriptionStatus: 'expired',
        ),
        now,
      ),
      '已过期',
    );
    expect(
      subscriptionValidityText(
        AccountSnapshot(plan: 'free', authMode: 'chatgpt', observed: now),
        now,
      ),
      '无订阅',
    );
    expect(subscriptionValidityText(null, now), '未登录');
  });
}
