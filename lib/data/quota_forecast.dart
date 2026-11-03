import 'models.dart';

/// A projection for one quota window, based on samples from the same reset
/// period. The rate uses a recent lookback so a quiet morning does not hide the
/// current burst, and a short span never produces a forecast at all.
class QuotaForecast {
  /// When the window is projected to reach 0%, before it resets.
  final DateTime? emptyAt;

  /// Remaining percent projected at reset when the window will not run out.
  final int? remainingAtReset;
  const QuotaForecast({this.emptyAt, this.remainingAtReset});
  bool get runsOut => emptyAt != null;

  static const minimumSpan = Duration(minutes: 10);

  static QuotaForecast? project(
    List<(DateTime, QuotaWindow)> samples,
    DateTime now,
  ) {
    if (samples.isEmpty) return null;
    final sorted = [...samples]..sort((a, b) => a.$1.compareTo(b.$1));
    final (at, window) = sorted.last;
    if (window.expired(now) || window.minutes <= 0) return null;
    final lookback = Duration(minutes: (window.minutes ~/ 6).clamp(30, 1440));
    final period = sorted
        .where(
          (s) =>
              _samePeriod(s.$2, window) &&
              !s.$1.isBefore(at.subtract(lookback)),
        )
        .toList();
    if (period.length < 2) return null;
    final (firstAt, first) = period.first;
    final span = at.difference(firstAt);
    if (span < minimumSpan) return null;
    final remaining = 100 - window.used;
    // A drop in usage means the provider recalculated; treat it as no burn.
    final rate = ((window.used - first.used) / span.inSeconds).clamp(
      0.0,
      double.infinity,
    );
    final resets = window.resets;
    if (rate == 0) {
      return resets == null
          ? null
          : QuotaForecast(remainingAtReset: remaining.round());
    }
    final emptyAt = at.add(Duration(seconds: (remaining / rate).round()));
    if (resets != null && !emptyAt.isBefore(resets)) {
      final left = remaining - rate * resets.difference(at).inSeconds;
      return QuotaForecast(remainingAtReset: left.clamp(0, 100).round());
    }
    // An old sample whose projected end already passed says nothing reliable.
    return emptyAt.isAfter(now) ? QuotaForecast(emptyAt: emptyAt) : null;
  }

  static bool _samePeriod(QuotaWindow a, QuotaWindow b) {
    if (a.minutes != b.minutes) return false;
    if (a.resets == null || b.resets == null) return a.resets == b.resets;
    return a.resets!.difference(b.resets!).abs() <= const Duration(minutes: 5);
  }
}
