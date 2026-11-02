import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quota_mate/controller.dart';
import 'package:quota_mate/data/store.dart';
import 'package:quota_mate/data/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppController c;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('quota-account-state-');
    final store = LocalStore('${dir.path}/data.db');
    store.set('preferences', {
      'demo': true,
      'scanEnabled': false,
      'profiles': [
        {'root': dir.path, 'label': 'test'},
      ],
    });
    store.set(
      'quota:${dir.path}',
      AccountSnapshot(
        email: 'old@example.com',
        authMode: 'chatgpt',
        primary: QuotaWindow(
          10,
          300,
          DateTime.now().add(const Duration(hours: 1)),
        ),
        observed: DateTime.now(),
      ).toJson(),
    );
    c = AppController(store);
  });
  tearDown(() {
    c.dispose();
    dir.deleteSync(recursive: true);
  });
  test(
    'startup statistics include only today; longer periods remain selectable',
    () {
      c.now = DateTime(2026, 11, 1, 12);
      UsageEvent event(String id, DateTime at, int tokens) => UsageEvent(
        id: id,
        session: id,
        project: 'example',
        model: 'example',
        at: at,
        tokens: Tokens(tokens, 0, 0),
        cost: tokens / 100,
      );
      c.all = [
        event('today-midnight', DateTime(2026, 11, 1), 100),
        event('today-noon', c.now, 200),
        event('yesterday', DateTime(2026, 10, 31, 23, 59), 400),
        event('last-month', DateTime(2026, 10, 10), 800),
        event('future', DateTime(2026, 11, 2), 1600),
      ];
      expect(c.page, 0);
      expect(c.summary.requests, 2);
      expect(c.summary.total, 300);
      expect(c.summary.cost, 3);
      c.setDays(7);
      expect(c.summary.total, 700);
      c.setDays(30);
      expect(c.summary.total, 1500);
      c.setDays(1);
      expect(c.summary.total, 300);
    },
  );
  test('cost sparkline sums reference costs, ignores outside dates, and preserves unknown prices', () {
    c.now = DateTime(2026, 11, 1, 12);
    UsageEvent event(String id, int days, double? cost) => UsageEvent(
      id: id,
      session: id,
      project: 'example',
      model: 'example',
      at: DateTime(2026, 11, 1, 10).subtract(Duration(days: days)),
      tokens: const Tokens(999999, 0, 0),
      cost: cost,
    );
    c.all = [
      event('yesterday-a', 1, .2),
      event('yesterday-b', 1, .3),
      event('today', 0, 1.4),
      event('outside', 7, null),
      event('future', -1, 20),
    ];
    c.days = 1;
    expect(c.costValues(), [0, 0, 0, 0, 0, .5, 1.4]);
    c.all.add(event('unpriced-today', 0, null));
    expect(c.costValues(), isNull);
  });
  test('legacy saved demo preference does not reopen a fictitious account', () {
    expect(c.demo, false);
    expect(c.account?.email, 'old@example.com');
    expect(c.status, '历史快照');
    expect(c.quotaValid, false);
    c.demo = true;
    c.save();
    expect((c.store.get('preferences') as Map).containsKey('demo'), false);
  });
  test(
    'local scan cannot erase an account query failure or confirm old identity',
    () async {
      c.error = 'quota query failed';
      await c.refresh(remote: false);
      expect(c.error, 'quota query failed');
      expect(c.accountVerified, false);
      expect(c.quotaValid, false);
    },
  );
  test(
    'local scan cannot replace a newly verified account with the disk snapshot',
    () async {
      c.account = AccountSnapshot(
        email: 'current@example.com',
        authMode: 'chatgpt',
        observed: DateTime.now(),
      );
      c.accountVerified = true;
      await c.refresh(remote: false);
      expect(c.account?.email, 'current@example.com');
      expect(c.accountVerified, true);
    },
  );
}
