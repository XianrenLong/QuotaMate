import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quota_mate/controller.dart';
import 'package:quota_mate/data/provider.dart';
import 'package:quota_mate/data/store.dart';
import 'package:quota_mate/data/models.dart';
import 'package:quota_mate/data/appearance.dart';
import 'package:quota_mate/data/native_bridge.dart';
import 'package:quota_mate/l10n/strings.dart';
import 'package:quota_mate/ui/app.dart';
import 'package:quota_mate/ui/localized.dart';
import 'package:quota_mate/ui/overview_account.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('provider switch keeps statistics and account caches separate and restores the selection', () async {
    final dir = Directory.systemTemp.createTempSync('quota-providers-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final root = '${dir.path}/shared-root';
    final store = LocalStore('${dir.path}/data.db');
    store.set('preferences', {
      'scanEnabled': false,
      'quotaEnabled': false,
      'profiles': [
        SourceProfile(root, 'GPT source').toJson(),
        SourceProfile(
          root,
          'Claude source',
          provider: AiProvider.claude,
        ).toJson(),
      ],
    });
    final now = DateTime.now();
    for (final scope in [root, 'claude:$root']) {
      store.db.execute(
        'INSERT INTO usage_events(scope,id,session,project,model,at,input,cached,output,reasoning) VALUES(?,?,?,?,?,?,?,?,?,?)',
        [
          scope,
          'same-id',
          'session',
          'project',
          scope == root ? 'gpt-6.1-sol' : 'claude-opus-5',
          now.millisecondsSinceEpoch,
          scope == root ? 100 : 200,
          0,
          0,
          0,
        ],
      );
      store.set(
        'quota:$scope',
        AccountSnapshot(
          email: scope == root ? 'gpt@example.com' : 'claude@example.com',
          authMode: scope == root ? 'chatgpt' : 'claude',
          observed: now,
        ).toJson(),
      );
    }
    var c = AppController(store);
    expect(c.summary.total, 100);
    await c.selectProvider(AiProvider.claude);
    expect(c.summary.total, 200);
    expect(c.account?.email, 'claude@example.com');
    expect(c.canResetQuota, false);
    expect(c.profiles.single.provider, AiProvider.claude);
    c.dispose();
    c = AppController(LocalStore('${dir.path}/data.db'));
    expect(c.provider, AiProvider.claude);
    expect(c.summary.total, 200);
    await c.selectProvider(AiProvider.gpt);
    expect(c.summary.total, 100);
    expect(c.account?.email, 'gpt@example.com');
    c.dispose();
  });
  test('Claude historical presentation is identity-verified and never becomes live quota', () {
    final dir = Directory.systemTemp.createTempSync('quota-history-view-');
    final c = AppController(LocalStore('${dir.path}/data.db'));
    addTearDown(() {
      c.dispose();
      dir.deleteSync(recursive: true);
    });
    c.provider = AiProvider.claude;
    c.now = DateTime(2026, 11, 1, 20);
    void snapshot({String? identity = 'verified', int age = 60}) {
      c.account = AccountSnapshot(
        authMode: 'claude',
        observed: c.now.subtract(Duration(minutes: age)),
        identityFingerprint: identity,
        source: 'Claude 桌面用量快照',
        primary: const QuotaWindow(7, 300, null),
        secondary: const QuotaWindow(2, 10080, null),
      );
    }

    snapshot();
    c.accountVerified = true;
    expect(c.stale, true);
    expect(c.quotaValid, false);
    expect(c.quotaHistorical, true);
    expect(c.presentedWindow?.remaining, 93);
    expect(c.canResetQuota, false);
    snapshot(identity: null);
    expect(c.presentedWindow, isNull);
    snapshot();
    c.accountVerified = false;
    expect(c.presentedWindow, isNull);
    c.accountVerified = true;
    c.quotaEnabled = false;
    expect(c.presentedWindow, isNull);
    c.quotaEnabled = true;
    snapshot(age: 400);
    expect(c.presentedWindow?.remaining, 98);
    snapshot(age: 11000);
    expect(c.presentedWindow, isNull);
    c.account = AccountSnapshot(
      authMode: 'claude',
      observed: c.now,
      source: 'Claude 历史额度快照',
      identityFingerprint: 'verified',
      primary: QuotaWindow(90, 300, c.now.subtract(const Duration(seconds: 1))),
      secondary: QuotaWindow(2, 10080, c.now.add(const Duration(days: 2))),
    );
    expect(c.quotaValid, false);
    expect(c.activeWindow?.remaining, 98);
    expect(c.presentedWindow?.remaining, 98);
    expect(c.quotaHistorical, true);
  });
  for (final size in [const Size(1320, 850), const Size(1000, 720)]) {
    testWidgets(
      'Claude menu and pages work in both languages and themes at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final dir = Directory.systemTemp.createTempSync('quota-claude-ui-');
        final c = AppController(
          LocalStore('${dir.path}/data.db'),
          forceDemo: true,
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeBridge.channel, (_) async => null);
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(NativeBridge.channel, null),
        );
        addTearDown(() {
          c.dispose();
          dir.deleteSync(recursive: true);
        });
        await tester.pumpWidget(QuotaMateApp(controller: c));
        await tester.pumpAndSettle();
        await tester.tap(find.text('GPT'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Claude'));
        await tester.pumpAndSettle();
        expect(c.provider, AiProvider.claude);
        expect(find.text('Claude'), findsOneWidget);
        for (final language in AppLanguage.values) {
          await c.setLanguage(language);
          for (final appearance in [AppAppearance.light, AppAppearance.dark]) {
            await c.setAppearance(appearance);
            for (var page = 0; page < 5; page++) {
              c.navigate(page);
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: 'Claude $language $appearance page $page at $size',
              );
              expect(find.byType(QuotaResetButton), findsNothing);
              for (final element in find.byType(LocalizedText).evaluate()) {
                final widget = element.widget as LocalizedText;
                if (language == AppLanguage.en && widget.localize) {
                  final text = AppLocale.text(element, widget.data);
                  expect(
                    RegExp(r'[\u3400-\u9fff]').hasMatch(text) && text != '简体中文',
                    false,
                    reason: widget.data,
                  );
                }
              }
            }
          }
        }
        await tester.tap(find.text('Claude'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('GPT'));
        await tester.pumpAndSettle();
        expect(c.provider, AiProvider.gpt);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
