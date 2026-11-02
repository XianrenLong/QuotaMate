import 'models.dart';
import 'store.dart';

/// USD per million tokens, Standard short-context reference rates.
/// Checked against OpenAI's pricing table on the date below.
abstract final class ReferencePricing {
  static const checkedOn = '2026-10-31';
  static const sourceUrl = 'https://developers.openai.com/api/docs/pricing';
  static const presets = <ModelPrice>[
    ModelPrice('gpt-6-astra', 10, 1, 50),
    ModelPrice('gpt-6.1-sol', 2, .10, 10),
    ModelPrice('gpt-6.1-terra', 1, .05, 5),
    ModelPrice('gpt-5.6-sol', 4, .40, 20),
    ModelPrice('gpt-5.6-terra', 2, .20, 12),
  ];

  static List<ModelPrice> seed(
    LocalStore store,
    Map preferences,
    List<ModelPrice> current,
  ) {
    final key = 'reference-prices-seeded:$checkedOn';
    if (store.get(key) == true) return current;
    final names = current.map((p) => p.model).toSet();
    final merged = [
      ...current,
      ...presets.where((p) => !names.contains(p.model)),
    ];
    store.db.execute('BEGIN IMMEDIATE');
    try {
      store.set('preferences', {
        ...preferences,
        'prices': merged.map((p) => p.toJson()).toList(),
      });
      store.set(key, true);
      store.db.execute('COMMIT');
    } catch (_) {
      store.db.execute('ROLLBACK');
      rethrow;
    }
    return merged;
  }
}
