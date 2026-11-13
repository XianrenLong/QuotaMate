import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quota_mate/controller.dart';
import 'package:quota_mate/data/store.dart';
import 'package:quota_mate/data/models.dart';
import 'package:quota_mate/ui/app.dart';
import 'package:quota_mate/ui/pages.dart';
import 'package:quota_mate/ui/widgets.dart';
import 'package:quota_mate/ui/usage_details_table.dart';

void main() {
  testWidgets(
    'sidebar toggles preserve the overview chart and lay it out at its final width',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('quota-sidebar-');
      final c = AppController(
        LocalStore('${dir.path}/test.db'),
        forceDemo: true,
      )..navigate(1);
      tester.view.physicalSize = const Size(1000, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        c.dispose();
        dir.deleteSync(recursive: true);
        tester.view.reset();
      });
      await tester.pumpWidget(QuotaMateApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.text('记录数'));
      await tester.pumpAndSettle();
      final overview = find.byType(OverviewPage);
      final width = tester.getSize(overview).width;
      final trend = find.byWidgetPredicate(
        (w) => w is UsageChart && w.requests,
      );
      final chart = tester.widget<UsageChart>(trend);
      for (final (button, expectedWidth) in [
        ('收起侧栏', width + 132),
        ('展开侧栏', width),
      ]) {
        await tester.tap(find.byTooltip(button));
        await tester.pump();
        expect(tester.getSize(overview).width, expectedWidth);
        await tester.pumpAndSettle();
        expect(tester.widget<UsageChart>(trend), same(chart));
        expect(tester.takeException(), isNull);
      }
    },
  );
  for (final size in [const Size(1320, 850), const Size(1000, 720)]) {
    testWidgets('all pages and filters render without overflow at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = Directory.systemTemp.createTempSync('quota-ui-');
      final c = AppController(
        LocalStore('${dir.path}/test.db'),
        forceDemo: true,
      );
      addTearDown(() {
        c.dispose();
        dir.deleteSync(recursive: true);
      });
      await tester.pumpWidget(QuotaMateApp(controller: c));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('GPT'), findsOneWidget);
      expect(find.byType(UsageDetailsTable), findsOneWidget);
      final trend = find.byWidgetPredicate((w) => w is UsageChart && !w.mini);
      final baseline = tester.widget<UsageChart>(trend).values;
      expect(baseline, hasLength(30));
      await tester.tap(find.text('近7天'));
      await tester.pumpAndSettle();
      expect(c.days, 7);
      expect(tester.widget<UsageChart>(trend).values, baseline);
      await tester.tap(find.text('今日'));
      await tester.pumpAndSettle();
      expect(c.days, 1);
      for (var i = 1; i < 5; i++) {
        c.navigate(i);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'page $i at $size');
      }
      c.navigate(0);
      await tester.pumpAndSettle();
      await tester.drag(
        find
            .descendant(
              of: find.byType(UsageDetailsTable),
              matching: find.byType(SingleChildScrollView),
            )
            .first,
        const Offset(-800, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.text('首字')).right,
        lessThanOrEqualTo(size.width),
      );
      await tester.tap(find.text('今日'));
      await tester.pumpAndSettle();
      expect(c.days, 1);
      expect(tester.takeException(), isNull);
      c.navigate(1);
      await tester.pumpAndSettle();
      expect(find.text('62%'), findsOneWidget);
      expect(tester.widget<UsageChart>(trend).values, baseline);
      await tester.tap(find.text('记录数'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final originalAccount = c.account;
      c.demo = false;
      c.accountVerified = true;
      for (final plan in ['prolite', 'pro', 'promax']) {
        c.account = AccountSnapshot(
          plan: plan,
          authMode: 'chatgpt',
          observed: c.now,
        );
        c.navigate(1);
        await tester.pumpAndSettle();
        expect(find.text('今日用量记录'), findsOneWidget);
        expect(find.text('5 小时窗口剩余'), findsNothing);
        c.navigate(2);
        await tester.pumpAndSettle();
        expect(find.text(c.planName), findsWidgets);
        expect(tester.takeException(), isNull);
      }
      c.account = AccountSnapshot(
        plan: 'plus',
        authMode: 'chatgpt',
        observed: c.now,
        secondary: QuotaWindow(30, 10080, c.now.add(const Duration(days: 1))),
      );
      c.navigate(1);
      await tester.pumpAndSettle();
      expect(find.text('本周剩余'), findsOneWidget);
      expect(find.text('今日用量记录'), findsNothing);
      c.demo = true;
      c.account = originalAccount;
      final old = c.now.subtract(const Duration(minutes: 1));
      c.account = AccountSnapshot(
        primary: QuotaWindow(38, 300, old),
        secondary: QuotaWindow(65, 10080, old),
        observed: old,
      );
      c.navigate(3);
      await tester.pumpAndSettle();
      expect(find.text('暂不可用'), findsNWidgets(2));
      expect(find.text('35% 剩余'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
