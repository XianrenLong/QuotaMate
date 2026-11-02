import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quota_mate/controller.dart';
import 'package:quota_mate/data/models.dart';
import 'package:quota_mate/data/native_bridge.dart';
import 'package:quota_mate/data/store.dart';
import 'package:quota_mate/l10n/strings.dart';
import 'package:quota_mate/ui/app.dart';
import 'package:quota_mate/ui/localized.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'English templates handle dynamic values, durations and compact numbers',
    () {
      const en = AppStrings(AppLanguage.en);
      expect(en.text('今日'), 'Today');
      expect(en.text('3天4小时后重置'), 'Resets in 3d 4h');
      expect(
        en.text('当前窗口剩余 35% · 2小时6分后重置'),
        '35% remaining · Resets in 2h 6m',
      );
      expect(
        en.text('额度已重置。 额度信息暂未更新，请刷新。'),
        'Limits reset. Limits are not updated yet. Please refresh.',
      );
      expect(en.text('2.6亿'), '260M');
      expect(en.text('31.4万'), '314K');
      expect(en.text('11/1\n2 次'), '11/1\n2 records');
      expect(en.text('2026.11.01（已到期）'), '2026.11.01 (expired)');
      expect(en.text('Pro X5'), 'Pro X5');
      expect(const AppStrings(AppLanguage.zh).text('统计'), '统计');
      expect(const AppStrings(AppLanguage.zh).text('额度管家'), 'QuotaMate');
    },
  );

  test('language survives restart and export translates headers but keeps model data', () async {
    final dir = Directory.systemTemp.createTempSync('quota-language-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeBridge.channel, (call) async {
          calls.add(call);
          return call.method == 'saveCsv' ? '${dir.path}/sample.csv' : null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeBridge.channel, null),
    );
    var c = AppController(LocalStore('${dir.path}/state.db'));
    expect(c.language, AppLanguage.zh);
    await c.setLanguage(AppLanguage.en);
    c.dispose();
    c = AppController(LocalStore('${dir.path}/state.db'));
    addTearDown(c.dispose);
    expect(c.language, AppLanguage.en);
    expect(c.days, 1);
    c.all = [
      UsageEvent(
        id: 'sample',
        session: 'sample',
        project: '/sample/设置',
        model: '模型',
        at: c.now,
        tokens: const Tokens(100, 0, 20),
        timingEstimated: true,
        firstTokenSeconds: 1.2,
      ),
    ];
    await c.export();
    final csv =
        calls.lastWhere((call) => call.method == 'saveCsv').arguments as Map;
    expect(csv['name'], startsWith('GPT-usage-'));
    expect(csv['content'], contains('Time,Model,Estimated cost (USD)'));
    expect(csv['content'], contains('"模型"'));
    expect(csv['content'], contains(',Yes'));
    await c.setLanguage(AppLanguage.zh);
    await c.export();
    final chineseCsv =
        calls.lastWhere((call) => call.method == 'saveCsv').arguments as Map;
    expect(chineseCsv['content'], contains('时间,模型,成本（USD估算）'));
    expect(
      calls
          .where((call) => call.method == 'setLanguage')
          .map((call) => (call.arguments as Map)['language']),
      ['en', 'zh'],
    );
  });

  for (final size in [const Size(1320, 850), const Size(1000, 720)]) {
    testWidgets(
      'settings switch language immediately; English pages fit at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final dir = Directory.systemTemp.createTempSync('quota-language-ui-');
        final c = AppController(LocalStore('${dir.path}/data.db'));
        addTearDown(() {
          c.dispose();
          dir.deleteSync(recursive: true);
        });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeBridge.channel, (_) async => null);
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(NativeBridge.channel, null),
        );
        c.account = AccountSnapshot(
          email: 'sample@example.com',
          plan: 'prolite',
          authMode: 'chatgpt',
          observed: c.now,
          availableQuotaResets: 1,
          primary: QuotaWindow(35, 10080, c.now.add(const Duration(days: 3))),
        );
        c.accountVerified = true;
        c.store.set('quota:${c.profile.root}', c.account!.toJson());
        c.all = [
          UsageEvent(
            id: 'sample',
            session: 'sample',
            project: '/sample/设置',
            model: '模型',
            at: c.now,
            tokens: const Tokens(100, 0, 20),
            cost: .01,
          ),
        ];
        c.navigate(4);
        await tester.pumpWidget(QuotaMateApp(controller: c));
        await tester.pumpAndSettle();
        expect(find.text('QuotaMate'), findsOneWidget);
        expect(find.text('额度管家'), findsNothing);
        await tester.tap(find.text('English'));
        await tester.pumpAndSettle();
        expect(c.language, AppLanguage.en);
        expect(find.text('Appearance & language'), findsOneWidget);
        expect(find.text('Language'), findsOneWidget);
        for (var page = 0; page < 5; page++) {
          c.navigate(page);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'English page $page at $size',
          );
          final untranslated = <String>{};
          for (final element in find.byType(LocalizedText).evaluate()) {
            final widget = element.widget as LocalizedText;
            if (!widget.localize) continue;
            final translated = AppLocale.text(element, widget.data);
            if (RegExp(r'[\u3400-\u9fff]').hasMatch(translated) &&
                translated != '简体中文') {
              untranslated.add(widget.data);
            }
          }
          for (final element in find.byType(LocalizedTooltip).evaluate()) {
            final widget = element.widget as LocalizedTooltip;
            if (!widget.localize) continue;
            if (RegExp(r'[\u3400-\u9fff]')
                .hasMatch(AppLocale.text(element, widget.message))) {
              untranslated.add(widget.message);
            }
          }
          expect(
            untranslated,
            isEmpty,
            reason: 'Untranslated app copy on page $page',
          );
        }
        c.navigate(0);
        await tester.pumpAndSettle();
        expect(find.text('模型'), findsOneWidget);
        await tester.tap(find.text('Projects 1'));
        await tester.pumpAndSettle();
        expect(find.text('设置'), findsOneWidget);
        c.navigate(4);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Add price'));
        await tester.tap(find.text('Add price'));
        await tester.pumpAndSettle();
        expect(find.text('Add model reference price'), findsOneWidget);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.text('Required'), findsNWidgets(4));
        await tester.enterText(find.byType(TextFormField).at(0), '模型');
        await tester.enterText(find.byType(TextFormField).at(1), '-1');
        await tester.enterText(find.byType(TextFormField).at(2), '0.1');
        await tester.enterText(find.byType(TextFormField).at(3), '2');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(
          find.text('Enter a number greater than or equal to 0'),
          findsOneWidget,
        );
        await tester.enterText(find.byType(TextFormField).at(1), '1');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(c.prices.singleWhere((price) => price.model == '模型').input, 1);
        expect(tester.takeException(), isNull);
        c.navigate(2);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('View data sources'));
        await tester.tap(find.text('View data sources'));
        await tester.pumpAndSettle();
        expect(find.text('Got it'), findsOneWidget);
        expect(find.text('Sign in to Codex, then refresh.'), findsNothing);
        await tester.tap(find.text('Got it'));
        await tester.pumpAndSettle();
        c.navigate(4);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('简体中文'));
        await tester.tap(find.text('简体中文'));
        await tester.pumpAndSettle();
        expect(c.language, AppLanguage.zh);
        expect(find.text('外观与语言'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
