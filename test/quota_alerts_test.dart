import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quota_mate/controller.dart';
import 'package:quota_mate/data/models.dart';
import 'package:quota_mate/data/native_bridge.dart';
import 'package:quota_mate/data/quota_reset.dart';
import 'package:quota_mate/data/store.dart';
import 'package:quota_mate/l10n/strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory dir;
  late AppController c;
  late DateTime base;
  late DateTime reset;
  final notices = <Map>[];
  var accepted = true;
  const email = 'sample@example.com';

  AccountSnapshot reading({
    int remaining = 20,
    String address = email,
    int minutes = 10080,
    int seconds = 0,
    bool unknownReset = false,
    QuotaWindow? primary,
  }) => AccountSnapshot(
    email: address,
    authMode: 'chatgpt',
    observed: base.add(Duration(seconds: seconds)),
    availableQuotaResets: 1,
    primary: primary,
    secondary: QuotaWindow(
      100.0 - remaining,
      minutes,
      unknownReset ? null : reset,
    ),
  );

  Future<void> refresh(AccountSnapshot snapshot, {bool verified = true}) async {
    c.account = snapshot;
    c.accountVerified = verified;
    await c.refresh(remote: false);
  }

  void reopen({QuotaResetter? resetter}) {
    c.dispose();
    c = AppController(
      LocalStore('${dir.path}/test.db'),
      quotaResetter: resetter,
    );
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('quota-alerts-');
    final store = LocalStore('${dir.path}/test.db');
    store.set('preferences', {
      'scanEnabled': false,
      'notifications': true,
      'profiles': [
        {'root': dir.path, 'label': 'sample'},
      ],
    });
    c = AppController(store);
    base = DateTime.now().subtract(const Duration(minutes: 1));
    reset = base.add(const Duration(days: 2));
    notices.clear();
    accepted = true;
    messenger.setMockMethodCallHandler(NativeBridge.channel, (call) async {
      if (call.method != 'notify') return true;
      notices.add(call.arguments as Map);
      return accepted;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(NativeBridge.channel, null);
    c.dispose();
    dir.deleteSync(recursive: true);
  });

  test('a weekly low survives restart and only a newer verified reading confirms recovery', () async {
    expect(c.recoveryNotifications, isFalse);
    c.setRecoveryNotifications(true);
    final low = reading(primary: QuotaWindow(95, 300, base));
    await refresh(low);
    await refresh(low);
    expect(notices.single['title'], 'GPT 每周窗口额度提醒');
    reopen();
    expect(c.recoveryNotifications, isTrue);
    final high = reading(remaining: 72, seconds: 1);
    await refresh(high, verified: false);
    await refresh(reading(remaining: 72, seconds: -1));
    await refresh(reading(remaining: 72, minutes: 300, seconds: 1));
    await refresh(
      reading(remaining: 72, address: 'other@example.com', seconds: 1),
    );
    expect(notices, hasLength(1));
    c.language = AppLanguage.en;
    await refresh(high);
    await refresh(high);
    expect(notices, hasLength(2));
    expect(notices.last['title'], 'GPT Weekly window recovered');
    expect(notices.last['body'], 'Remaining quota is back to 72%.');
    expect(c.error, isNull);
  });

  test(
    'changing the threshold or switching alerts off cancels pending recoveries',
    () async {
      c.setRecoveryNotifications(true);
      final low = reading(remaining: 15);
      final high = reading(remaining: 55, seconds: 2);
      await refresh(low);
      c.setAlertThreshold(10);
      await refresh(reading(remaining: 15, seconds: 1));
      c.setAlertThreshold(20);
      await refresh(low);
      c.setRecoveryNotifications(false);
      c.setRecoveryNotifications(true);
      await refresh(high);
      await refresh(low);
      await c.setNotifications(false);
      await c.setNotifications(true);
      await refresh(high);
      expect(notices, hasLength(1));
    },
  );

  test('migration suppresses a duplicate for the old window and new alerts are per account', () async {
    c.store.set(
      'alert:${dir.path}:较长窗口:${reset.millisecondsSinceEpoch}:20',
      true,
    );
    await refresh(reading());
    expect(notices, isEmpty);
    await refresh(reading(address: 'other@example.com'));
    await refresh(reading(address: 'OTHER@example.com'));
    expect(notices, hasLength(1));
    await refresh(reading(remaining: 72, seconds: 1));
    expect(notices, hasLength(1)); // Recovery is opt-in.
  });

  test('clearing local data forgets a pending recovery', () async {
    c.setRecoveryNotifications(true);
    await refresh(reading());
    await c.clear();
    await refresh(reading(remaining: 72, seconds: 1));
    expect(notices, hasLength(1));
  });

  test(
    'failed notification delivery can retry without invalidating the account',
    () async {
      c.setRecoveryNotifications(true);
      final low = reading(unknownReset: true);
      accepted = false;
      await refresh(low);
      expect(c.accountVerified, isTrue);
      expect(c.error, isNull);
      accepted = true;
      await refresh(low);
      expect(notices.last['body'], '20% 剩余');
      final high = reading(remaining: 80, seconds: 1, unknownReset: true);
      accepted = false;
      await refresh(high);
      accepted = true;
      await refresh(high);
      await refresh(high);
      expect(notices.map((n) => n['title']), [
        'GPT 每周窗口额度提醒',
        'GPT 每周窗口额度提醒',
        'GPT 每周窗口额度已恢复',
        'GPT 每周窗口额度已恢复',
      ]);
      await refresh(reading(unknownReset: true, seconds: 2));
      expect(notices.last['title'], 'GPT 每周窗口额度提醒');
    },
  );

  test('manual reset uses the returned reading to confirm recovery', () async {
    c.setRecoveryNotifications(true);
    final cli = File('${dir.path}/sample-cli.exe')
      ..writeAsStringSync('fixture');
    c.executable = cli.path;
    c.save();
    reopen(
      resetter: (_, _, _, _) async => QuotaResetResult(
        QuotaResetOutcome.reset,
        reading(remaining: 94, seconds: 2),
      ),
    );
    await refresh(reading());
    await c.resetQuota();
    expect(notices.map((n) => n['title']), ['GPT 每周窗口额度提醒', 'GPT 每周窗口额度已恢复']);
    expect(c.message, '额度已重置。');
  });
}
