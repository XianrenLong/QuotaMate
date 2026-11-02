import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quota_mate/data/models.dart';
import 'package:quota_mate/controller.dart';
import 'package:quota_mate/data/store.dart';
import 'package:quota_mate/data/subscription_dates.dart';
import 'package:quota_mate/data/subscription_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2030, 5, 10);
  final account = <String, dynamic>{
    'type': 'chatgpt',
    'email': 'person@example.com',
    'planType': 'plus',
  };
  Json cache({
    String email = 'person@example.com',
    String id = 'account-one',
    String plan = 'plus',
    String? start = '2030-05-01T00:00:00Z',
    String? end = '2030-06-01T00:00:00Z',
    String? checked = '2030-05-09T00:00:00Z',
  }) {
    final payload = {
      'email': email,
      'exp': 1,
      'iat': 9999999999,
      'https://api.openai.com/auth': {
        'chatgpt_account_id': id,
        'chatgpt_plan_type': plan,
        'chatgpt_subscription_active_start': start,
        'chatgpt_subscription_active_until': end,
        'chatgpt_subscription_last_checked': checked,
      },
    };
    final body = base64Url
        .encode(utf8.encode(jsonEncode(payload)))
        .replaceAll('=', '');
    return {
      'auth_mode': 'chatgpt',
      'tokens': {
        'id_token': 'header.$body.signature',
        'access_token': 'PRIVATE_ACCESS_VALUE',
        'refresh_token': 'PRIVATE_REFRESH_VALUE',
        'account_id': 'account-one',
      },
    };
  }

  test(
    'disabling automatic date reading hides cached dates after restart',
    () async {
      final dir = Directory.systemTemp.createTempSync('quota-date-preference-');
      final db = '${dir.path}/data.db';
      final store = LocalStore(db);
      store.set('preferences', {
        'scanEnabled': false,
        'quotaEnabled': false,
        'profiles': [
          {'root': dir.path, 'label': 'Sample'},
        ],
      });
      store.set(
        'quota:${dir.path}',
        AccountSnapshot(
          authMode: 'chatgpt',
          observed: now,
          subscriptionDates: SubscriptionDates(
            periodEndsAt: DateTime.utc(2030, 6, 1),
            source: 'codexLoginCache',
          ),
        ).toJson(),
      );
      var c = AppController(store);
      expect(c.account?.subscriptionDates, isNotNull);
      await c.setSubscriptionDateReading(false);
      expect(c.account?.subscriptionDates, isNull);
      c.dispose();
      c = AppController(LocalStore(db));
      expect(c.readSubscriptionDates, false);
      expect(c.account?.subscriptionDates, isNull);
      c.dispose();
      dir.deleteSync(recursive: true);
    },
  );
  test('automatic Codex dates use explicit subscription claims only, never JWT lifetime', () {
    final dates = SubscriptionDateReader.fromCodex(cache(), account, now)!;
    expect(dates.startedAt, DateTime.utc(2030, 5, 1));
    expect(dates.periodEndsAt, DateTime.utc(2030, 6, 1));
    expect(dates.lastCheckedAt, DateTime.utc(2030, 5, 9));
    final value = AccountSnapshot(
      email: account['email'],
      plan: 'plus',
      authMode: 'chatgpt',
      observed: now,
      subscriptionDates: dates,
    );
    final copy = AccountSnapshot.fromJson(value.toJson());
    expect(copy.subscriptionDates?.periodEndsAt, dates.periodEndsAt);
    expect(subscriptionDateLabel(copy), '订阅周期（缓存）');
    expect(subscriptionValidityText(copy, now), '2030.06.01');
    final serialized = jsonEncode(copy.toJson());
    for (final private in [
      'PRIVATE_ACCESS_VALUE',
      'PRIVATE_REFRESH_VALUE',
      'id_token',
      'access_token',
      'refresh_token',
    ]) {
      expect(serialized, isNot(contains(private)));
    }
    expect(
      SubscriptionDateReader.fromCodex(
        cache(start: null, end: null),
        account,
        now,
      ),
      isNull,
    );
  });
  test('foreign email, account, plan, API key, malformed and impossible dates are rejected', () {
    for (final value in [
      cache(email: 'other@example.com'),
      cache(id: 'account-two'),
      cache(plan: 'pro'),
      cache(start: '2030-05-11T00:00:00Z'),
      cache(end: '2030-04-01T00:00:00Z'),
      cache(checked: '2031-01-01T00:00:00Z'),
      {'auth_mode': 'apikey', 'tokens': cache()['tokens']},
      {
        'tokens': {'id_token': 'not-a-jwt', 'account_id': 'account-one'},
      },
    ]) {
      expect(
        SubscriptionDateReader.fromCodex(
          Map<String, dynamic>.from(value),
          account,
          now,
        ),
        isNull,
      );
    }
    expect(SubscriptionDateReader.date('2030-02-30T00:00:00Z'), isNull);
    expect(SubscriptionDateReader.date('2030-06-01'), isNull);
    expect(SubscriptionDateReader.date(1893456000), isNull);
    expect(
      SubscriptionDateReader.fromCodex(cache(), {
        ...account,
        'type': 'apiKey',
      }, now),
      isNull,
    );
  });
  test(
    'expired cached period cannot downgrade the latest paid subscription',
    () {
      final dates = SubscriptionDateReader.fromCodex(
        cache(start: '2030-01-01T00:00:00Z', end: '2030-02-01T00:00:00Z'),
        account,
        now,
      )!;
      final value = AccountSnapshot(
        plan: 'plus',
        authMode: 'chatgpt',
        observed: now,
        subscriptionDates: dates,
      );
      expect(SubscriptionInfo.read(value, now).label, 'Plus');
      expect(subscriptionValidityText(value, now), contains('待更新'));
      expect(subscriptionDateExplanation(value, now), contains('不据此判定订阅过期'));
      final official = AccountSnapshot(
        plan: 'plus',
        authMode: 'chatgpt',
        observed: now,
        subscriptionDates: dates,
        subscriptionExpiresAt: DateTime.utc(2030, 7, 1),
      );
      expect(subscriptionDateLabel(official), '订阅有效期');
      expect(subscriptionValidityText(official, now), '2030.07.01');
    },
  );
  test('Claude reads matching subscription creation, never trial/account creation or an invented month', () {
    final auth = <String, dynamic>{
      'loggedIn': true,
      'authMethod': 'claude.ai',
      'email': 'person@example.com',
      'orgId': 'org-one',
    };
    final value = <String, dynamic>{
      'oauthAccount': {
        'emailAddress': 'PERSON@example.com',
        'organizationUuid': 'org-one',
        'subscriptionCreatedAt': '2029-02-28T01:00:00Z',
        'accountCreatedAt': '2028-01-01T00:00:00Z',
        'claudeCodeTrialEndsAt': '2030-06-01T00:00:00Z',
        'profileFetchedAt': '2030-05-09T00:00:00Z',
        'billingType': 'apple_subscription',
      },
    };
    final dates = SubscriptionDateReader.fromClaude(value, auth, now)!;
    expect(dates.startedAt, DateTime.utc(2029, 2, 28, 1));
    expect(dates.periodEndsAt, isNull);
    final snapshot = AccountSnapshot(
      plan: 'claude_pro',
      authMode: 'claude',
      observed: now,
      subscriptionDates: dates,
    );
    expect(subscriptionDateLabel(snapshot), '订阅开始（本机）');
    expect(subscriptionDateExplanation(snapshot, now), contains('未按一个月推算'));
    expect(
      SubscriptionDateReader.fromClaude(value, {
        ...auth,
        'orgId': 'other',
      }, now),
      isNull,
    );
    expect(
      SubscriptionDateReader.fromClaude(value, {
        ...auth,
        'email': 'other@example.com',
      }, now),
      isNull,
    );
    final missing = jsonDecode(jsonEncode(value)) as Json;
    (missing['oauthAccount'] as Map).remove('subscriptionCreatedAt');
    expect(SubscriptionDateReader.fromClaude(missing, auth, now), isNull);
  });
  test('custom profile paths stay isolated and external Codex tokens disable local-cache fallback', () async {
    final temp = await Directory.systemTemp.createTemp('quota-date-sources-');
    addTearDown(() => temp.delete(recursive: true));
    final root = Directory('${temp.path}/profile')..createSync();
    File('${root.path}/auth.json').writeAsStringSync(jsonEncode(cache()));
    final external = await SubscriptionDateReader.codex(
      root.path,
      account,
      environment: {'CODEX_ACCESS_TOKEN': 'external-fixture'},
    );
    expect(external, isNull);
    final auth = <String, dynamic>{
      'loggedIn': true,
      'authMethod': 'claude.ai',
      'email': 'person@example.com',
      'orgId': 'org-one',
    };
    File('${temp.path}/.claude.json').writeAsStringSync(
      jsonEncode({
        'oauthAccount': {
          'emailAddress': 'person@example.com',
          'organizationUuid': 'org-one',
          'subscriptionCreatedAt': '2020-01-01T00:00:00Z',
        },
      }),
    );
    expect(
      await SubscriptionDateReader.claude(
        root.path,
        auth,
        home: temp.path,
        environment: {},
      ),
      isNull,
    );
    final standard = Directory('${temp.path}/.claude')..createSync();
    expect(
      (await SubscriptionDateReader.claude(
        standard.path,
        auth,
        home: temp.path,
        environment: {},
      ))?.startedAt,
      DateTime.utc(2020),
    );
  });
}
