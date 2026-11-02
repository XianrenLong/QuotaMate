import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quota_mate/data/models.dart';
import 'package:quota_mate/data/reference_pricing.dart';
import 'package:quota_mate/data/store.dart';

void main() {
  test('reference estimate charges cached input only once', () {
    final price = ReferencePricing.presets.firstWhere(
      (p) => p.model == 'gpt-6-astra',
    );
    expect(
      price.estimate(const Tokens(669341, 668000, 123)),
      closeTo(.68756, 1e-9),
    );
  });
  test(
    'seed fills missing models and persists without replacing custom prices',
    () {
      final dir = Directory.systemTemp.createTempSync('quota-pricing-');
      final store = LocalStore('${dir.path}/data.db');
      try {
        const custom = ModelPrice('gpt-6-astra', 9, .9, 45);
        final prices = ReferencePricing.seed(
          store,
          {'quotaEnabled': false},
          [custom],
        );
        expect(prices.length, 5);
        expect(prices.first.input, 9);
        final saved = store.get('preferences') as Map;
        expect(saved['quotaEnabled'], false);
        expect((saved['prices'] as List).length, 5);
        final reduced = prices.where((p) => p.model != 'gpt-6.1-sol').toList();
        expect(ReferencePricing.seed(store, saved, reduced).length, 4);
      } finally {
        store.close();
        dir.deleteSync(recursive: true);
      }
    },
  );
}
