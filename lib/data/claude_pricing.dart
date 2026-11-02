import 'models.dart';
import 'store.dart';

abstract final class ClaudePricing {
  static const sourceUrl =
      'https://platform.claude.com/docs/en/about-claude/pricing';
  static const checkedOn = '2026-11-01';
  static const presets = [
    ModelPrice('claude-fable-5', 10, 1, 50),
    ModelPrice('claude-fable-5-1', 10, .25, 50),
    ModelPrice('claude-opus-5', 5, .5, 25),
    ModelPrice('claude-opus-5-5', 4, .2, 20),
    ModelPrice('claude-opus-4-8', 5, .5, 25),
    ModelPrice('claude-opus-4-7', 5, .5, 25),
    ModelPrice('claude-opus-4-6', 5, .5, 25),
    ModelPrice('claude-opus-4-5', 5, .5, 25),
    ModelPrice('claude-sonnet-5', 2, .2, 10),
    ModelPrice('claude-sonnet-5-5', 2, .1, 10),
    ModelPrice('claude-sonnet-4-6', 3, .3, 15),
    ModelPrice('claude-sonnet-4-5', 3, .3, 15),
    ModelPrice('claude-haiku-4-5', 1, .1, 5),
  ];
  static List<ModelPrice> seed(
    LocalStore store,
    Map preferences,
    List<ModelPrice> current,
  ) {
    final key = 'claude-reference-prices:$checkedOn';
    if (store.get(key) == true) return current;
    final names = current.map((v) => v.model).toSet();
    final merged = [
      ...current,
      ...presets.where((v) => !names.contains(v.model)),
    ];
    store.set('preferences', {
      ...preferences,
      'prices': merged.map((v) => v.toJson()).toList(),
    });
    store.set(key, true);
    return merged;
  }
}
