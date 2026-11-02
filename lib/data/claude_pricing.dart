import 'models.dart';
import 'store.dart';

abstract final class ClaudePricing {
  static const sourceUrl =
      'https://platform.claude.com/docs/en/about-claude/pricing';
  static const checkedOn = '2026-11-02';
  static const _previousModels = {
    'claude-fable-5',
    'claude-fable-5-1',
    'claude-opus-5',
    'claude-opus-5-5',
    'claude-opus-4-8',
    'claude-opus-4-7',
    'claude-opus-4-6',
    'claude-opus-4-5',
    'claude-sonnet-5',
    'claude-sonnet-5-5',
    'claude-sonnet-4-6',
    'claude-sonnet-4-5',
    'claude-haiku-4-5',
  };
  static const presets = [
    ModelPrice('claude-fable-5', 10, 1, 50),
    ModelPrice('claude-fable-5-1', 10, .25, 50),
    ModelPrice('claude-mythos-5-1', 10, .25, 50),
    ModelPrice('claude-mythos-5', 10, 1, 50),
    ModelPrice('claude-opus-5', 5, .5, 25),
    ModelPrice('claude-opus-5-5', 4, .2, 20),
    ModelPrice('claude-opus-4-8', 5, .5, 25),
    ModelPrice('claude-opus-4-7', 5, .5, 25),
    ModelPrice('claude-opus-4-6', 5, .5, 25),
    ModelPrice('claude-opus-4-5', 5, .5, 25),
    ModelPrice('claude-opus-4-1', 15, 1.5, 75),
    ModelPrice('claude-opus-4', 15, 1.5, 75),
    ModelPrice('claude-sonnet-5', 2, .2, 10),
    ModelPrice('claude-sonnet-5-5', 2, .1, 10),
    ModelPrice('claude-sonnet-4-6', 3, .3, 15),
    ModelPrice('claude-sonnet-4-5', 3, .3, 15),
    ModelPrice('claude-sonnet-4', 3, .3, 15),
    ModelPrice(
      'claude-haiku-5-5',
      .1,
      .01,
      .5,
      longContextThreshold: 100000,
      longContextInput: .5,
      longContextCached: .05,
      longContextOutput: 2.5,
    ),
    ModelPrice('claude-haiku-4-5', 1, .1, 5),
    ModelPrice('claude-3-5-haiku', .8, .08, 4),
  ];
  static List<ModelPrice> seed(
    LocalStore store,
    Map preferences,
    List<ModelPrice> current,
  ) {
    final key = 'claude-reference-prices:$checkedOn';
    if (store.get(key) == true) return current;
    final savedDefaults = store.get('claude-default-models') as List?;
    final previous =
        savedDefaults?.whereType<String>().toSet() ??
        (store.get('claude-reference-prices:2026-11-01') == true
            ? _previousModels
            : <String>{});
    final names = current.map((v) => v.model).toSet();
    final merged = [
      ...current,
      ...presets.where(
        (v) => !names.contains(v.model) && !previous.contains(v.model),
      ),
    ];
    store.db.execute('BEGIN IMMEDIATE');
    try {
      store.set('preferences', {
        ...preferences,
        'prices': merged.map((v) => v.toJson()).toList(),
      });
      store.set(key, true);
      store.set('claude-default-models', presets.map((v) => v.model).toList());
      store.db.execute('COMMIT');
    } catch (_) {
      store.db.execute('ROLLBACK');
      rethrow;
    }
    return merged;
  }
}
