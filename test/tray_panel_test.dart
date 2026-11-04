import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quota_mate/controller.dart';
import 'package:quota_mate/data/models.dart';
import 'package:quota_mate/data/quota_forecast.dart';
import 'package:quota_mate/data/store.dart';
import 'package:quota_mate/l10n/strings.dart';
import 'package:quota_mate/tray_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 3, 14);
  final resets = now.add(const Duration(hours: 2));
  QuotaWindow w(double used, [DateTime? at]) =>
      QuotaWindow(used, 300, at ?? resets);

  group('forecast', () {
    test('projects when a window runs out before it resets', () {
      final f = QuotaForecast.project([
        (now.subtract(const Duration(minutes: 30)), w(40)),
        (now, w(55)),
      ], now)!;
      // 15% in 30 minutes leaves 45% for 90 minutes, before the 2-hour reset.
      expect(f.runsOut, isTrue);
      expect(f.emptyAt, now.add(const Duration(minutes: 90)));
    });

    test('projects the remaining share at reset for a slow burn', () {
      final f = QuotaForecast.project([
        (now.subtract(const Duration(minutes: 40)), w(20)),
        (now, w(24)),
      ], now)!;
      // 0.1% per minute leaves 76% - 12% when the window resets.
      expect(f.runsOut, isFalse);
      expect(f.remainingAtReset, 64);
    });

    test('flat usage keeps the current share', () {
      final f = QuotaForecast.project([
        (now.subtract(const Duration(minutes: 20)), w(30)),
        (now, w(30)),
      ], now)!;
      expect(f.remainingAtReset, 70);
    });

    test('needs two samples of one period at least ten minutes apart', () {
      expect(QuotaForecast.project([(now, w(30))], now), isNull);
      expect(
        QuotaForecast.project([
          (now.subtract(const Duration(minutes: 5)), w(10)),
          (now, w(30)),
        ], now),
        isNull,
      );
      // The earlier sample belongs to the previous reset period.
      expect(
        QuotaForecast.project([
          (now.subtract(const Duration(minutes: 40)), w(90, now)),
          (now, w(30)),
        ], now),
        isNull,
      );
    });

    test('an outdated projection is dropped instead of claiming 0%', () {
      final f = QuotaForecast.project([
        (now.subtract(const Duration(minutes: 90)), w(40)),
        (now.subtract(const Duration(minutes: 60)), w(80)),
      ], now);
      expect(f, isNull);
    });
  });

  group('payload', () {
    late Directory dir;
    late LocalStore store;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('quota-tray-');
      store = LocalStore('${dir.path}/data.db');
      store.set('preferences', {
        'scanEnabled': false,
        'profiles': [
          {'root': dir.path, 'label': 'test'},
        ],
      });
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('demo data fills both windows, forecasts and today', () {
      final c = AppController(store, forceDemo: true);
      addTearDown(c.dispose);
      final payload = trayPayload(c);
      expect(payload['title'], 'GPT 62%');
      expect(payload['warning'], isFalse);
      final panel = payload['panel'] as Map;
      expect(panel['online'], isTrue);
      expect(panel['todayTitle'], '今日概览');
      final windows = panel['windows'] as List;
      expect(windows.map((e) => e['label']), ['5 小时窗口', '每周窗口']);
      expect(windows.first['unit'], '剩余');
      expect(windows.first['forecast'], '预计重置时剩 36%');
      expect(windows.first['shortForecast'], '预计重置时剩 36%');
      expect(windows.first['forecastTone'], 'success');
      expect(windows.last['forecast'], startsWith('照现在的速度，约 2小时'));
      expect(windows.last['shortForecast'], startsWith('约 2小时'));
      expect(windows.last['forecastTone'], 'warning');
      expect((panel['metrics'] as List).length, 3);
      expect((panel['hours'] as List).length, 12);
    });

    test('title styles and English copy', () async {
      final c = AppController(store, forceDemo: true);
      await c.setTrayTitle(TrayTitle.both);
      expect(trayPayload(c)['title'], 'G 62% · C 62%');
      await c.setTrayTitle(TrayTitle.countdown);
      expect(trayPayload(c)['title'], matches(RegExp(r'^GPT 62% · 2:1\d$')));
      await c.setTrayTitle(TrayTitle.icon);
      expect(trayPayload(c)['title'], '');
      c.language = AppLanguage.en;
      final panel = trayPayload(c)['panel'] as Map;
      expect(panel['todayTitle'], 'Today overview');
      expect((panel['windows'] as List).first['unit'], 'Remaining');
      expect(
        (panel['windows'] as List).first['forecast'],
        'About 36% left at reset',
      );
      expect(
        (panel['windows'] as List).last['forecast'],
        startsWith('At this pace, runs out in about 2h'),
      );
      expect(
        (panel['windows'] as List).last['shortForecast'],
        startsWith('Runs out in ~2h'),
      );
      expect((panel['actions'] as Map)['open'], 'Open QuotaMate');
      c.dispose();
      final reopened = AppController(LocalStore('${dir.path}/data.db'));
      addTearDown(reopened.dispose);
      expect(reopened.trayTitle, TrayTitle.icon);
    });

    test('saved readings forecast only for the same signed-in identity', () {
      final c = AppController(store);
      addTearDown(c.dispose);
      c.now = DateTime.now();
      final reset = c.now.add(const Duration(hours: 3));
      AccountSnapshot reading(String email, double used, Duration ago) =>
          AccountSnapshot(
            email: email,
            authMode: 'chatgpt',
            primary: QuotaWindow(used, 300, reset),
            observed: c.now.subtract(ago),
          );
      store.set('quota-trend:${dir.path}', [
        reading('other@example.com', 0, const Duration(minutes: 50)).toJson(),
        reading('me@example.com', 50, const Duration(minutes: 30)).toJson(),
      ]);
      c.account = reading('me@example.com', 70, Duration.zero);
      c.accountVerified = true;
      expect(c.quotaTrend().length, 2);
      final f = c.forecast()!;
      // 20% in 30 minutes leaves 30% for 45 minutes.
      expect(f.emptyAt!.difference(c.now).inMinutes, 45);
      c.accountVerified = false;
      expect(c.forecast(), isNull);
      expect(trayPayload(c)['title'], 'GPT —');
    });
  });
}
