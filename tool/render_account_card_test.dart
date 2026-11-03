// Render the production Flutter widget with local system fonts for visual QA.
// QUOTA_QA_CJK_FONT=/path/to/PingFang.ttc flutter test tool/render_account_card_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quota_mate/controller.dart';
import 'package:quota_mate/app_info.dart';
import 'package:quota_mate/l10n/strings.dart';
import 'package:quota_mate/data/appearance.dart';
import 'package:quota_mate/data/provider.dart';
import 'package:quota_mate/data/models.dart';
import 'package:quota_mate/data/demo.dart';
import 'package:quota_mate/data/store.dart';
import 'package:quota_mate/ui/app.dart';
import 'package:quota_mate/ui/overview_account.dart';

class _PreviewController extends AppController {
  _PreviewController(super.store);
  @override
  List<AccountSnapshot> get quotaSamples {
    if (!isClaude || account == null) return super.quotaSamples;
    return [
      for (var i = 0; i <= 12; i++)
        AccountSnapshot(
          authMode: 'claude',
          observed: now.subtract(Duration(minutes: 119 * i)),
          source: '演示数据',
          primary: QuotaWindow(
            (32 - i * 2).toDouble(),
            300,
            now.add(const Duration(hours: 2)),
          ),
          secondary: QuotaWindow(
            (16 - i).toDouble(),
            10080,
            now.add(const Duration(days: 3)),
          ),
        ),
    ];
  }
}

void main() {
  testWidgets(
    'capture production account card with sample identity, no network calls',
    (tester) async {
      final font = Platform.environment['QUOTA_QA_CJK_FONT'];
      if (font == null) {
        throw StateError('Set QUOTA_QA_CJK_FONT to a local Chinese font.');
      }
      await tester.runAsync(() async {
        final data = ByteData.sublistView(await File(font).readAsBytes());
        for (final family in ['PingFang SC', 'Roboto']) {
          await (FontLoader(family)..addFont(Future.value(data))).load();
        }
        final iconFont = await rootBundle.load(
          'packages/lucide_icons_flutter/assets/lucide.ttf',
        );
        await (FontLoader(
          'packages/lucide_icons_flutter/Lucide',
        )..addFont(Future.value(iconFont))).load();
      });
      final dir = Directory.systemTemp.createTempSync('quotamate-visual-');
      final store = LocalStore('${dir.path}/sample.db');
      store.set('preferences', {
        'scanEnabled': false,
        'autoRefresh': false,
        'profiles': [
          {'root': '/sample/codex', 'label': '示例账号'},
          {'root': '/sample/claude', 'label': '示例账号', 'provider': 'claude'},
        ],
      });
      final c = _PreviewController(store);
      c.now = DateTime(2026, 11, 1, 12);
      c.account = AccountSnapshot(
        email: 'alex@example.com',
        plan: 'prolite',
        authMode: 'chatgpt',
        observed: c.now,
        availableQuotaResets: 1,
        primary: QuotaWindow(65, 10080, c.now.add(const Duration(days: 3))),
      );
      c.accountVerified = true;
      c.navigate(1);
      addTearDown(() {
        c.dispose();
        dir.deleteSync(recursive: true);
      });
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final captures = Directory('screenshots/${AppInfo.version}')
        ..createSync(recursive: true);
      c.all = [
        UsageEvent(
          id: 'sample',
          session: 'sample',
          project: '/sample/Example project',
          model: 'gpt-6.1-sol',
          at: c.now,
          tokens: const Tokens(100000, 98000, 200),
          cost: .028,
        ),
      ];
      for (final target in [
        (AppLanguage.zh, 1320.0, 0, AppAppearance.dark, AiProvider.gpt),
        (AppLanguage.zh, 1320.0, 1, AppAppearance.dark, AiProvider.gpt),
        (AppLanguage.zh, 1320.0, 1, AppAppearance.light, AiProvider.gpt),
        (AppLanguage.en, 1320.0, 0, AppAppearance.light, AiProvider.gpt),
        (AppLanguage.zh, 1320.0, 0, AppAppearance.dark, AiProvider.claude),
        (AppLanguage.zh, 1320.0, 1, AppAppearance.dark, AiProvider.claude),
        (AppLanguage.zh, 1320.0, 4, AppAppearance.dark, AiProvider.claude),
        (AppLanguage.en, 1320.0, 4, AppAppearance.dark, AiProvider.claude),
        (AppLanguage.en, 1320.0, 0, AppAppearance.dark, AiProvider.claude),
        (AppLanguage.zh, 1320.0, 0, AppAppearance.light, AiProvider.claude),
        (AppLanguage.en, 1000.0, 1, AppAppearance.dark, AiProvider.claude),
        (AppLanguage.zh, 1320.0, 1, AppAppearance.light, AiProvider.claude),
      ]) {
        final width = target.$2;
        c.now = DateTime(
          2026,
          11,
          1,
          target.$3 == 0 && target.$5 == AiProvider.claude ? 23 : 12,
          target.$3 == 0 && target.$5 == AiProvider.claude ? 55 : 0,
        );
        c.provider = target.$5;
        c.selected = 0;
        c.claudeSignedIn = c.isClaude;
        c.claudeCollectorEnabled = c.isClaude;
        c.account = AccountSnapshot(
          email: 'alex@example.com',
          plan: c.isClaude ? 'claude_max20' : 'prolite',
          authMode: c.isClaude ? 'claude' : 'chatgpt',
          observed: c.now,
          source: c.isClaude ? 'Claude Code 状态栏快照' : 'Codex CLI 登录',
          identityFingerprint: c.isClaude ? 'sample-identity' : null,
          availableQuotaResets: c.isClaude ? null : 1,
          subscriptionDates: SubscriptionDates(
            startedAt: c.now.subtract(const Duration(days: 12)),
            periodEndsAt: c.isClaude
                ? null
                : c.now.add(const Duration(days: 18)),
            lastCheckedAt: c.now.subtract(const Duration(hours: 2)),
            source: c.isClaude ? 'claudeProfile' : 'codexLoginCache',
          ),
          primary: QuotaWindow(
            65,
            c.isClaude ? 300 : 10080,
            c.now.add(
              c.isClaude ? const Duration(hours: 2) : const Duration(days: 3),
            ),
          ),
          secondary: c.isClaude
              ? QuotaWindow(40, 10080, c.now.add(const Duration(days: 3)))
              : null,
        );
        c.accountVerified = true;
        // Rich, synthetic seven-day data makes the documentation useful without
        // reading real accounts. Claude's unsupported timing fields stay unknown.
        c.days = 7;
        c.all = demoEvents(c.now, claude: c.isClaude).map((event) {
          final tokens = c.isClaude
              ? Tokens(
                  event.tokens.input,
                  event.tokens.cached,
                  event.tokens.output,
                  0,
                  event.freshInput ~/ 3,
                )
              : event.tokens;
          final model = c.isClaude ? 'claude-sonnet-4-6' : 'gpt-6.1-sol';
          final price = c.prices.where((v) => v.model == model).firstOrNull;
          return UsageEvent(
            id: event.id,
            session: event.session,
            project: event.project,
            model: model,
            at: event.at,
            tokens: tokens,
            cost: price?.estimate(tokens),
            outputTokensPerSecond: c.isClaude
                ? null
                : event.outputTokensPerSecond,
            firstTokenSeconds: c.isClaude ? null : event.firstTokenSeconds,
            timingEstimated: !c.isClaude,
          );
        }).toList();
        c.language = target.$1;
        c.appearance = target.$4;
        if (c.isClaude && target.$3 == 0) c.days = 1;
        c.navigate(target.$3);
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: QuotaMateApp(controller: c),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          for (final asset in [
            'assets/branding/account-card-soft-curve.png',
            'assets/branding/account-card-soft-curve-dark.png',
            'assets/branding/quotamate-hourglass.png',
          ]) {
            await precacheImage(
              AssetImage(asset),
              tester.element(find.byType(AppShell)),
            );
          }
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('QuotaMate'), findsOneWidget);
        if (target.$3 == 1) expect(find.text('35%'), findsOneWidget);
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final rect = target.$3 == 1
            ? tester.getRect(find.byType(OverviewAccountCard))
            : null;
        final name =
            '${target.$5.name}-${target.$4.name}-${target.$1.name}-${width.toInt()}';
        final page = [
          'statistics',
          'overview',
          'accounts',
          'alerts',
          'settings',
        ][target.$3];
        await tester.runAsync(() async {
          final capture = await boundary.toImage(pixelRatio: 2);
          final bytes = (await capture.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          await File('${captures.path}/$page-$name.png')
              .writeAsBytes(bytes.buffer.asUint8List());
          if (rect != null) {
            await File('${captures.path}/card-$name.rect').writeAsString(
              '${rect.left * 2},${rect.top * 2},${rect.right * 2},${rect.bottom * 2}',
            );
          }
          capture.dispose();
        });
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
