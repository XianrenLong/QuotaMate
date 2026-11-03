import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quota_mate/controller.dart';
import 'package:quota_mate/data/claude_connection.dart';
import 'package:quota_mate/data/models.dart';
import 'package:quota_mate/data/native_bridge.dart';
import 'package:quota_mate/data/store.dart';
import 'package:quota_mate/l10n/strings.dart';
import 'package:quota_mate/ui/app.dart';
import 'package:flutter/material.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('startup and repeated refreshes use local auth status only, even with legacy polling preferences', () async {
    final dir = Directory.systemTemp.createTempSync("quota local-mode '-");
    final root = '${dir.path}/profile';
    Directory(root).createSync();
    final log = File('${dir.path}/commands');
    final cli = File('${dir.path}/official-cli-fixture');
    final auth = <String, dynamic>{
      'loggedIn': true,
      'authMethod': 'claude.ai',
      'orgId': 'sample-org',
      'email': 'sample@example.com',
      'subscriptionType': 'pro',
      'configDirectory': root,
    };
    // Any startup, print, SDK control or model command would fail this fixture.
    cli.writeAsStringSync('''#!/bin/sh
printf '%s\\n' "\$*" >> ${ClaudeConnection.shellQuote(log.path)}
if [ "\$#" -ne 2 ] || [ "\$1" != auth ] || [ "\$2" != status ]; then exit 91; fi
cat <<'QUOTAMATE_TEST_AUTH'
${jsonEncode(auth)}
QUOTAMATE_TEST_AUTH
''');
    await Process.run('chmod', ['700', cli.path]);
    final store = LocalStore('${dir.path}/usage.db');
    store.set('preferences', {
      'provider': 'claude',
      'scanEnabled': false,
      'quotaEnabled': true,
      'autoRefresh': true,
      'refreshMinutes': 5,
      'claudeExecutable': cli.path,
      'profiles': [
        {'root': root, 'label': 'Sample', 'provider': 'claude'},
      ],
    });
    final original = DateTime.now().subtract(const Duration(seconds: 1));
    store.set(
      'quota:claude:$root',
      AccountSnapshot(
        email: auth['email'],
        authMode: 'claude',
        plan: 'claude_pro',
        source: 'Claude Code 官方额度',
        observed: original,
        primary: QuotaWindow(7, 300, original.add(const Duration(hours: 2))),
        identityFingerprint: ClaudeConnection.identityHash(auth),
      ).toJson(),
    );
    final c = AppController(store);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeBridge.channel, (_) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeBridge.channel, null);
      c.dispose();
      dir.deleteSync(recursive: true);
    });
    expect(c.account?.source, ClaudeConnection.cachedSource);
    expect(c.quotaValid, false);
    expect(c.presentedWindow, isNull); // Identity has not yet been checked.
    for (final remote in [true, false, true]) {
      await c.refresh(remote: remote);
      expect(c.error, isNull);
      expect(c.claudeSignedIn, true);
      expect(c.accountVerified, true);
      expect(c.account?.observed, original);
      expect(c.account?.source, ClaudeConnection.cachedSource);
      expect(c.presentedWindow?.remaining, 93);
      expect(c.quotaValid, false);
    }
    expect(log.readAsLinesSync(), List.filled(6, 'auth status'));
    expect(File('$root/quotamate/usage.json').existsSync(), false);
    final sampleTime = DateTime.now();
    Directory('$root/quotamate').createSync();
    File('$root/quotamate/usage.json').writeAsStringSync(
      jsonEncode({
        'identity': ClaudeConnection.identityHash(auth),
        'capturedAt': sampleTime.toIso8601String(),
        'rate_limits': {
          'five_hour': {'used_percentage': 12},
        },
      }),
    );
    await c.refresh(remote: false);
    expect(c.account?.source, 'Claude Code 状态栏快照');
    expect(c.account?.observed, sampleTime);
    expect(c.presentedWindow?.remaining, 88);
    expect(log.readAsLinesSync(), List.filled(8, 'auth status'));
  }, skip: Platform.isWindows);

  testWidgets(
    'empty Claude statistics explain data coverage and allow opening settings in both languages',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('quota-empty-');
      final store = LocalStore('${dir.path}/usage.db');
      store.set('preferences', {'provider': 'claude', 'scanEnabled': true});
      final c = AppController(store);
      addTearDown(() {
        c.dispose();
        dir.deleteSync(recursive: true);
      });
      tester.view.physicalSize = const Size(1000, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      c.all = [
        UsageEvent(
          id: 'old',
          session: 'old',
          project: 'sample',
          model: 'claude-opus-5',
          at: DateTime(2026, 7, 27),
          tokens: const Tokens(10, 0, 2),
        ),
      ];
      for (final language in AppLanguage.values) {
        c.language = language;
        c.navigate(0);
        await tester.pumpWidget(QuotaMateApp(controller: c));
        await tester.pumpAndSettle();
        final text = language == AppLanguage.zh
            ? '网页与普通桌面聊天暂无 Token 明细。'
            : 'Token details for web and regular desktop chat are unavailable.';
        expect(find.textContaining(text), findsWidgets);
        final action = language == AppLanguage.zh
            ? '查看数据设置'
            : 'Open data settings';
        await tester.tap(find.text(action).last);
        await tester.pumpAndSettle();
        expect(c.page, 4);
        expect(
          find.text(
            language == AppLanguage.zh ? '状态栏额度采集' : 'Status line collection',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            language == AppLanguage.zh ? '额度刷新间隔' : 'Limit refresh interval',
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
