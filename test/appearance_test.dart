import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quota_mate/controller.dart';
import 'package:quota_mate/data/appearance.dart';
import 'package:quota_mate/data/native_bridge.dart';
import 'package:quota_mate/data/store.dart';
import 'package:quota_mate/l10n/strings.dart';
import 'package:quota_mate/ui/app.dart';
import 'package:quota_mate/ui/palette.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'appearance persists independently from language and current data',
    () async {
      final dir = Directory.systemTemp.createTempSync('quota-appearance-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeBridge.channel, (call) async {
            if (call.method == 'setAppearance') {
              calls.add((call.arguments as Map)['appearance']);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeBridge.channel, null),
      );
      var c = AppController(LocalStore('${dir.path}/data.db'), forceDemo: true);
      expect(c.appearance, AppAppearance.light);
      final account = c.account;
      c.setDays(30);
      await c.setAppearance(AppAppearance.dark);
      expect(c.account, same(account));
      expect(c.days, 30);
      await c.setLanguage(AppLanguage.en);
      expect(c.appearance, AppAppearance.dark);
      c.dispose();
      c = AppController(LocalStore('${dir.path}/data.db'));
      expect(c.appearance, AppAppearance.dark);
      expect(c.language, AppLanguage.en);
      await c.setAppearance(AppAppearance.system);
      c.dispose();
      c = AppController(LocalStore('${dir.path}/data.db'));
      expect(c.appearance, AppAppearance.system);
      expect(c.language, AppLanguage.en);
      c.dispose();
      expect(calls, ['dark', 'system']);
    },
  );

  for (final size in [const Size(1320, 850), const Size(1000, 720)]) {
    testWidgets(
      'night mode covers both languages and follows system changes at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final dir = Directory.systemTemp.createTempSync('quota-night-ui-');
        final c = AppController(
          LocalStore('${dir.path}/data.db'),
          forceDemo: true,
        )..navigate(4);
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
        await tester.pumpWidget(QuotaMateApp(controller: c));
        await tester.pumpAndSettle();
        await tester.tap(find.text('深色'));
        await tester.pumpAndSettle();
        expect(c.appearance, AppAppearance.dark);
        for (final language in AppLanguage.values) {
          await c.setLanguage(language);
          for (var page = 0; page < 5; page++) {
            c.navigate(page);
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: 'dark $language page $page at $size',
            );
            final context = tester.element(find.byType(Scaffold).first);
            expect(Theme.of(context).brightness, Brightness.dark);
            final palette = Theme.of(context).extension<AppPalette>()!;
            expect(
              contrast(Colors.white, primaryFill(context)),
              greaterThanOrEqualTo(4.5),
            );
            expect(
              contrast(palette.resolve(C.ink), palette.resolve(C.card)),
              greaterThan(7),
            );
            expect(
              contrast(palette.resolve(C.muted), palette.resolve(C.card)),
              greaterThan(4.5),
            );
            if (page == 1) {
              expect(
                find.image(
                  const AssetImage(
                    'assets/branding/account-card-soft-curve-dark.png',
                  ),
                ),
                findsOneWidget,
              );
            }
            for (final element in find.byType(Container).evaluate()) {
              final box = (element.widget as Container).decoration;
              if (box is BoxDecoration && box.color != null) {
                expect(
                  [C.bg, C.card, C.side, C.track].contains(box.color),
                  false,
                  reason: 'daytime surface leaked into dark page $page',
                );
              }
            }
          }
        }
        c.navigate(2);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('View data sources'));
        await tester.tap(find.text('View data sources'));
        await tester.pumpAndSettle();
        final dialogTheme = Theme.of(tester.element(find.byType(AlertDialog)));
        expect(
          dialogTheme.dialogTheme.backgroundColor!.computeLuminance(),
          lessThan(.1),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Got it'));
        await tester.pumpAndSettle();
        c.navigate(4);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Light'));
        await tester.pumpAndSettle();
        expect(c.appearance, AppAppearance.light);
        expect(
          Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
          Brightness.light,
        );
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        await tester.tap(find.text('System'));
        await tester.pumpAndSettle();
        expect(c.appearance, AppAppearance.system);
        expect(
          Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
          Brightness.dark,
        );
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
          Brightness.light,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
