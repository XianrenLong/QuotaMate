import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quota_mate/controller.dart';
import 'package:quota_mate/data/claude_connection.dart';
import 'package:quota_mate/data/models.dart';
import 'package:quota_mate/data/native_bridge.dart';
import 'package:quota_mate/data/store.dart';
import 'package:quota_mate/ui/app.dart';

void main() {
  const auth = {
    'loggedIn': true,
    'email': 'sample@example.com',
    'orgId': 'org',
    'authMethod': 'claude.ai',
  };
  test('cached reset dates are bound to identity, window length and original timestamp', () {
    final now = DateTime.utc(2030, 2, 3, 10);
    final profile = {
      'oauthAccount': {
        'emailAddress': 'sample@example.com',
        'accountUuid': 'id',
        'organizationUuid': 'org',
      },
      'cachedUsageUtilization': {
        'accountUuid': 'id',
        'fetchedAtMs': now.millisecondsSinceEpoch,
        'utilization': {
          'five_hour': {'utilization': 0, 'resets_at': '2030-02-08T00:00:00Z'},
          'seven_day': {'utilization': 7, 'resets_at': '2030-02-08T00:00:00Z'},
        },
      },
    };
    final result = ClaudeConnection.profileQuota(profile, auth, now)!;
    expect(result.observed.isAtSameMomentAs(now), true);
    expect(result.primary?.resets, isNull);
    expect(result.secondary!.resets, DateTime.utc(2030, 2, 8));
    expect(result.secondary!.remaining, 93);
    expect(
      ClaudeConnection.profileQuota(profile, {...auth, 'orgId': 'other'}, now),
      isNull,
    );
    expect(
      ClaudeConnection.profileQuota(profile, {
        ...auth,
        'email': 'other@example.com',
      }, now),
      isNull,
    );
    (profile['cachedUsageUtilization'] as Map)['accountUuid'] = 'other';
    expect(ClaudeConnection.profileQuota(profile, auth, now), isNull);
  });
  test('desktop history filters other organizations and malformed samples independently', () {
    final now = DateTime.now(), ms = now.millisecondsSinceEpoch;
    final samples = ClaudeConnection.desktopSamples(
      {
        'samples': [
          {
            'org': 'other',
            't': ms,
            'u': {'fh': 10},
          },
          {
            'org': 'org',
            't': ms,
            'u': {'sd': 200},
          },
          {
            'org': 'org',
            't': ms + 86400000,
            'u': {'sd': 10},
          },
          {
            'org': 'org',
            't': ms - 1,
            'u': {'sd': 7},
          },
          {
            'org': 'org',
            't': ms - 2,
            'u': {'sd': 8},
          },
        ],
      },
      auth,
      now,
    );
    expect(samples.map((s) => s.secondary!.remaining), [93, 92]);
    expect(samples.first.primary, isNull);
  });
  testWidgets(
    'Claude opens on verified quota and jumps to the actual last log date including its partial price and CSV',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('quotamate-stats-');
      final store = LocalStore('${dir.path}/stats.db');
      store.set('preferences', {'provider': 'claude'});
      final c = AppController(store);
      addTearDown(() {
        c.dispose();
        dir.deleteSync(recursive: true);
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1050, 780);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      c.now = DateTime(2030, 2, 3, 11);
      c.account = AccountSnapshot(
        observed: DateTime(2030, 2, 3, 10, 33),
        authMode: 'claude',
        identityFingerprint: 'sample',
        source: 'Claude 桌面用量快照',
        secondary: const QuotaWindow(7, 10080, null),
      );
      c.accountVerified = true;
      c.all = [
        for (final entry in [
          ('priced', 1.17, 20),
          ('unknown', null, 20),
          ('older', 4.0, 19),
        ])
          UsageEvent(
            id: entry.$1,
            session: 's',
            project: 'p',
            model: entry.$1,
            at: DateTime(2029, 12, entry.$3, 14),
            tokens: const Tokens(10, 0, 2),
            cost: entry.$2,
          ),
      ];
      String? csv, name;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeBridge.channel, (m) async {
            if (m.method == 'saveCsv') {
              csv = m.arguments['content'];
              name = m.arguments['name'];
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeBridge.channel, null),
      );
      await tester.pumpWidget(QuotaMateApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text('93%'), findsOneWidget);
      expect(find.text('采样 1 条'), findsOneWidget);
      await tester.tap(find.text('Token 与成本'));
      await tester.pumpAndSettle();
      expect(find.text('暂无可计价记录'), findsOneWidget);
      await tester.tap(find.text('查看最近有记录的一天'));
      await tester.pumpAndSettle();
      expect(c.events.length, 2);
      expect(find.text(r'$1.17'), findsOneWidget);
      expect(find.text('已计价 1/2 条'), findsOneWidget);
      await c.export();
      expect(csv, contains('"unknown"'));
      expect(csv, isNot(contains('"older"')));
      expect(name, contains('2029-12-20'));
      await tester.tap(find.text('返回今日'));
      await tester.pumpAndSettle();
      expect(c.events, isEmpty);
      expect(c.days, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
