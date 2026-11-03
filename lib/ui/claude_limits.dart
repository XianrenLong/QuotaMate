import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../data/models.dart';
import 'widgets.dart';
import 'localized.dart';

String sampleDate(DateTime date, {bool time = true}) {
  final local = date.toLocal();
  final day = local.toIso8601String().substring(0, 10);
  return time ? '$day ${clockText(local)}' : day;
}

class ClaudeLimits extends StatelessWidget {
  final AppController c;
  const ClaudeLimits(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    final samples = c.quotaSamples;
    final inPeriod = samples
        .where(
          (s) =>
              !s.observed.isBefore(c.rangeStart) &&
              s.observed.isBefore(
                DateTime(c.now.year, c.now.month, c.now.day + 1),
              ),
        )
        .toList();
    final account = (c.accountVerified && c.quotaEnabled || c.demo)
        ? c.account
        : null;
    final timestamps = inPeriod.reversed.toList();
    final upperHalf = inPeriod.every(
      (s) => (s.primary?.used ?? 0) <= 50 && (s.secondary?.used ?? 0) <= 50,
    );
    final tick = upperHalf ? 10.0 : 20.0;
    final muted = themeColor(context, C.muted);
    Widget reading(bool week) {
      final sample = inPeriod
          .where((v) => (week ? v.secondary : v.primary) != null)
          .firstOrNull;
      final window = week ? sample?.secondary : sample?.primary;
      final accent = themeColor(context, week ? C.green : C.blue);
      return Expanded(
        child: _Surface(
          child: Row(
            children: [
              SizedBox.square(
                dimension: 88,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: CircularProgressIndicator(
                        value: window == null ? 0 : (100 - window.used) / 100,
                        strokeWidth: 7,
                        strokeAlign:
                            CircularProgressIndicator.strokeAlignInside,
                        strokeCap: StrokeCap.round,
                        backgroundColor: accent.withValues(alpha: .15),
                        color: accent,
                      ),
                    ),
                    label(
                      window == null ? '—' : '${window.remaining}%',
                      size: 23,
                      weight: FontWeight.w600,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    label(
                      week ? '每周剩余' : '5 小时剩余',
                      size: 19,
                      weight: FontWeight.w600,
                      lines: 2,
                    ),
                    const SizedBox(height: 5),
                    label(
                      sample == null
                          ? '暂无采样'
                          : '采集于 ${sampleDate(sample.observed)}',
                      size: 12,
                      color: muted,
                      lines: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget dateRow(String title, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(width: 170, child: label(title, color: muted, size: 13)),
          Expanded(child: label(value, size: 13, lines: 2)),
        ],
      ),
    );
    Widget resetRow(bool week) {
      AccountSnapshot? s;
      QuotaWindow? w;
      double? newerUsed;
      for (final candidate in samples) {
        final window = week ? candidate.secondary : candidate.primary;
        if (window == null || window.minutes != (week ? 10080 : 300)) continue;
        if (newerUsed != null && window.used > newerUsed) break;
        newerUsed = window.used;
        final reset = window.resets;
        if (reset == null) continue;
        if (reset.isAfter(c.now) &&
            reset.isAfter(candidate.observed) &&
            !reset.isAfter(
              candidate.observed.add(Duration(minutes: window.minutes + 1)),
            )) {
          s = candidate;
          w = window;
        }
        break;
      }
      return dateRow(
        week ? '周额度重置时间' : '5 小时额度重置时间',
        s == null
            ? '未提供'
            : '${sampleDate(w!.resets!)}（采集于 ${sampleDate(s.observed)}）',
      );
    }

    return ListView(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [reading(false), const SizedBox(width: 14), reading(true)],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: QuotaSegments(
            ['今日', '近7天', '近30天'],
            [1, 7, 30].indexOf(c.days),
            (i) => c.setDays([1, 7, 30][i]),
            segmentWidth: 92,
          ),
        ),
        const SizedBox(height: 12),
        _Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: label('额度采样趋势', size: 16, weight: FontWeight.w600),
                  ),
                  for (final week in [false, true]) ...[
                    const SizedBox(width: 14),
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: themeColor(context, week ? C.green : C.blue),
                      ),
                    ),
                    const SizedBox(width: 5),
                    label(week ? '每周剩余' : '5 小时剩余', size: 12, color: muted),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              if (timestamps.isEmpty) ...[
                label('所选周期没有已核对的额度快照。', color: muted),
                if (samples.isNotEmpty)
                  label(
                    '最近采样：${sampleDate(samples.first.observed)}',
                    size: 12,
                    color: muted,
                  ),
              ] else ...[
                SizedBox(
                  height: 164,
                  child: LineChart(
                    LineChartData(
                      minY: upperHalf ? 50 : 0,
                      maxY: 100,
                      minX: 0,
                      maxX: DateTime(
                        c.now.year,
                        c.now.month,
                        c.now.day + 1,
                      ).difference(c.rangeStart).inSeconds.toDouble(),
                      borderData: FlBorderData(show: false),
                      gridData: FlGridData(
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: themeColor(context, C.line),
                          strokeWidth: 1,
                          dashArray: [4, 4],
                        ),
                        drawVerticalLine: false,
                        horizontalInterval: tick,
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        topTitles: const AxisTitles(),
                        rightTitles: const AxisTitles(),
                        bottomTitles: const AxisTitles(),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 42,
                            interval: tick,
                            getTitlesWidget: (v, _) =>
                                label('${v.toInt()}%', size: 10, color: muted),
                          ),
                        ),
                      ),
                      lineTouchData: const LineTouchData(enabled: false),
                      lineBarsData: [
                        for (final week in [false, true])
                          LineChartBarData(
                            color: themeColor(context, week ? C.green : C.blue),
                            barWidth: 2,
                            isCurved: false,
                            spots: [
                              for (final s in timestamps)
                                if ((week ? s.secondary : s.primary)
                                    case final w?)
                                  FlSpot(
                                    s.observed
                                        .difference(c.rangeStart)
                                        .inSeconds
                                        .toDouble(),
                                    100 - w.used,
                                  ),
                            ],
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (_, _, bar, _) =>
                                  FlDotCirclePainter(
                                    radius: 3,
                                    color: bar.color!,
                                    strokeWidth: 0,
                                  ),
                            ),
                          ),
                      ],
                    ),
                    duration: Duration.zero,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var i = 0; i <= 4; i++)
                        label(
                          c.days == 1
                              ? '${(6 * i).toString().padLeft(2, "0")}:00'
                              : sampleDate(
                                  DateTime(
                                    c.rangeStart.year,
                                    c.rangeStart.month,
                                    c.rangeStart.day +
                                        ((c.days - 1) * i / 4).round(),
                                  ),
                                  time: false,
                                ).substring(5),
                          size: 11,
                          color: muted,
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: label('账号日期', size: 16, weight: FontWeight.w600),
                  ),
                  label('采样 ${timestamps.length} 条', size: 11, color: muted),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              resetRow(false),
              const Divider(height: 8),
              resetRow(true),
              const Divider(height: 8),
              dateRow(
                '订阅开始日期',
                account?.subscriptionDates?.startedAt == null
                    ? '未提供'
                    : sampleDate(
                        account!.subscriptionDates!.startedAt!,
                        time: false,
                      ),
              ),
              const Divider(height: 8),
              dateRow(
                '订阅到期日',
                account?.subscriptionExpiresAt == null
                    ? '未提供'
                    : sampleDate(account!.subscriptionExpiresAt!, time: false),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Surface extends StatelessWidget {
  final Widget child;
  const _Surface({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: BoxDecoration(
      color: themeColor(context, C.card),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: themeColor(context, C.line)),
    ),
    child: child,
  );
}

class QuotaSegments extends StatelessWidget {
  final List<String> titles;
  final int selected;
  final ValueChanged<int> onChanged;
  final double segmentWidth;
  const QuotaSegments(
    this.titles,
    this.selected,
    this.onChanged, {
    this.segmentWidth = 142,
    super.key,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: themeColor(context, C.card),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: themeColor(context, C.line)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < titles.length; i++)
          SizedBox(
            width: segmentWidth,
            height: 34,
            child: Semantics(
              selected: i == selected,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: i == selected
                      ? primaryFill(context)
                      : Colors.transparent,
                  foregroundColor: i == selected
                      ? Colors.white
                      : themeColor(context, C.ink),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                onPressed: () => onChanged(i),
                child: FittedBox(child: LocalizedText(titles[i])),
              ),
            ),
          ),
      ],
    ),
  );
}
