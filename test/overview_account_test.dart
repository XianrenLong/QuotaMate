import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quota_mate/controller.dart';
import 'package:quota_mate/data/models.dart';
import 'package:quota_mate/data/store.dart';
import 'package:quota_mate/data/quota_reset.dart';
import 'package:quota_mate/ui/app.dart';
import 'package:quota_mate/ui/overview_account.dart';

void main() {
  for (final size in [const Size(1320, 850), const Size(1000, 720)]) {
    testWidgets('overview details and account switching at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = Directory.systemTemp.createTempSync('quota-overview-');
      final store = LocalStore('${dir.path}/test.db');
      final rootA = '${dir.path}/a';
      final rootB = '${dir.path}/b';
      store.set('preferences', {
        'scanEnabled': false,
        'quotaEnabled': false,
        'profiles': [
          {'root': rootA, 'label': '个人账号'},
          {'root': rootB, 'label': '工作账号'},
        ],
      });
      final now = DateTime.now();
      const emailA = 'a-very-long-account-address-for-layout-check@example.com';
      store.set(
        'quota:$rootA',
        AccountSnapshot(
          email: emailA,
          plan: 'prolite',
          authMode: 'chatgpt',
          observed: now,
          availableQuotaResets: 0,
        ).toJson(),
      );
      store.set(
        'quota:$rootB',
        AccountSnapshot(
          email: 'work@example.com',
          plan: 'plus',
          authMode: 'chatgpt',
          observed: now,
          subscriptionExpiresAt: DateTime(2027, 1, 2),
          availableQuotaResets: 3,
        ).toJson(),
      );
      final executable = File(
        '${dir.path}/mock-codex${Platform.isWindows ? '.exe' : ''}',
      )..writeAsStringSync('mock');
      var resetCalls = 0;
      final c = AppController(
        store,
        quotaResetter: (_, root, email, key) async {
          resetCalls++;
          expect(root, rootB);
          expect(email, 'work@example.com');
          return QuotaResetResult(
            QuotaResetOutcome.reset,
            AccountSnapshot(
              email: email,
              plan: 'plus',
              authMode: 'chatgpt',
              observed: DateTime.now(),
              subscriptionExpiresAt: DateTime(2027, 1, 2),
              availableQuotaResets: 2,
            ),
          );
        },
      )..navigate(1);
      addTearDown(() {
        c.dispose();
        dir.deleteSync(recursive: true);
      });
      await tester.pumpWidget(QuotaMateApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text(emailA), findsOneWidget);
      expect(find.text('账号状态'), findsNothing);
      expect(find.text('GPT · 个人账号'), findsNothing);
      expect(find.text('Codex 订阅额度'), findsNothing);
      expect(find.text('订阅有效期'), findsOneWidget);
      expect(find.text('接口未提供'), findsOneWidget);
      expect(find.text('暂无可用次数'), findsOneWidget);
      final button = find.descendant(
        of: find.byType(QuotaResetButton),
        matching: find.byType(TextButton),
      );
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byType(AccountSwitcher));
      await tester.pumpAndSettle();
      expect(find.text('当前查看'), findsOneWidget);
      await tester.tap(find.text('work@example.com'));
      await tester.pumpAndSettle();
      expect(c.selected, 1);
      expect(find.text('work@example.com'), findsOneWidget);
      expect(find.text('2027.01.02'), findsOneWidget);
      expect(find.text('3 次可用'), findsOneWidget);
      expect(find.text('暂无可用次数'), findsNothing);
      expect(find.text(emailA), findsNothing);
      expect(tester.takeException(), isNull);

      c.accountVerified = true;
      c.setting(() {
        c.quotaEnabled = true;
        c.executable = executable.path;
      });
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(button).onPressed, isNotNull);
      await tester.runAsync(() async {
        await tester.tap(button);
        await Future.doWhile(() async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          return c.busy;
        }).timeout(const Duration(seconds: 5));
      });
      await tester.pumpAndSettle();
      expect(resetCalls, 1);
      expect(find.text('2 次可用'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byType(AccountSwitcher));
      await tester.pumpAndSettle();
      await tester.tap(find.text('管理账号'));
      await tester.pumpAndSettle();
      expect(c.page, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
