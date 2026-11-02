import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quota_mate/controller.dart';
import 'package:quota_mate/data/claude_pricing.dart';
import 'package:quota_mate/data/models.dart';
import 'package:quota_mate/data/reference_pricing.dart';
import 'package:quota_mate/data/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  LocalStore database() {
    final dir = Directory.systemTemp.createTempSync('quota-default-prices-');
    final store = LocalStore('${dir.path}/data.db');
    addTearDown(() {
      store.close();
      dir.deleteSync(recursive: true);
    });
    return store;
  }

  test('new install has complete project defaults for both providers without sign-in', () {
    final dir = Directory.systemTemp.createTempSync('quota-first-prices-');
    final c = AppController(LocalStore('${dir.path}/data.db'));
    addTearDown(() {
      c.dispose();
      dir.deleteSync(recursive: true);
    });
    expect(c.prices.where((v) => v.model.startsWith('claude-')), hasLength(20));
    expect(
      c.prices.where((v) => v.model.startsWith('gpt-')).map((v) => v.toJson()),
      ReferencePricing.presets.map((v) => v.toJson()),
    );
    expect(c.prices.map((v) => v.model).toSet().length, c.prices.length);
    expect((c.store.get('preferences') as Map)['prices'], hasLength(25));
  });
  test('upgrade fills new models but preserves manual prices, GPT and previous deletions', () {
    final store = database();
    store.set('claude-reference-prices:2026-11-01', true);
    const manual = ModelPrice('claude-opus-5', 7, .7, 30);
    final initial = [...ReferencePricing.presets, manual];
    final merged = ClaudePricing.seed(store, {'language': 'en'}, initial);
    expect(
      merged.firstWhere((v) => v.model == manual.model).toJson(),
      manual.toJson(),
    );
    expect(
      merged.where((v) => v.model.startsWith('gpt-')).map((v) => v.toJson()),
      ReferencePricing.presets.map((v) => v.toJson()),
    );
    expect(merged.any((v) => v.model == 'claude-mythos-5-1'), true);
    expect(merged.any((v) => v.model == 'claude-haiku-5-5'), true);
    expect(merged.any((v) => v.model == 'claude-fable-5'), false);
    final prefs = store.get('preferences') as Map;
    expect(prefs['language'], 'en');
    final reduced = merged.where((v) => v.model != 'claude-haiku-5-5').toList();
    expect(ClaudePricing.seed(store, prefs, reduced), same(reduced));
  });
  test(
    'Haiku 5.5 counts cache tokens toward the per-request 100k threshold',
    () {
      final price = ClaudePricing.presets.firstWhere(
        (v) => v.model == 'claude-haiku-5-5',
      );
      expect(
        price.estimate(const Tokens(100000, 99999, 1000)),
        closeTo(.00150009, 1e-12),
      );
      expect(
        price.estimate(const Tokens(100001, 100000, 1000)),
        closeTo(.0075005, 1e-12),
      );
      expect(
        price.estimate(const Tokens(100001, 0, 1000, 0, 100000, 40000)),
        closeTo((.5 + 60000 * .625 + 40000 * 1 + 1000 * 2.5) / 1e6, 1e-12),
      );
      final restored = ModelPrice.fromJson(price.toJson());
      expect(restored.hasLongContextRate, true);
      expect(
        restored.estimate(const Tokens(100001, 100000, 1000)),
        price.estimate(const Tokens(100001, 100000, 1000)),
      );
    },
  );
  test('dated and latest aliases are priced per response; exact user overrides win', () {
    final store = database();
    final now = DateTime.now();
    for (final entry in [
      ('one', 'claude-haiku-5-5-20261001'),
      ('two', 'claude-haiku-5-5-latest'),
    ]) {
      store.db.execute(
        'INSERT INTO usage_events(scope,id,session,project,model,at,input,cached,output,reasoning) VALUES(?,?,?,?,?,?,?,?,?,?)',
        [
          'claude:sample',
          entry.$1,
          'session',
          'sample',
          entry.$2,
          now.millisecondsSinceEpoch,
          70000,
          60000,
          100,
          0,
        ],
      );
    }
    final events = store.events(
      'claude:sample',
      DateTime(2000),
      ClaudePricing.presets,
    );
    expect(UsageSummary(events).cost, closeTo(.0033, 1e-12));
    final custom = store.events('claude:sample', DateTime(2000), [
      ...ClaudePricing.presets,
      const ModelPrice('claude-haiku-5-5-latest', 1, .1, 5),
    ]);
    expect(custom.firstWhere((v) => v.id == 'two').cost, closeTo(.0165, 1e-12));
  });
}
