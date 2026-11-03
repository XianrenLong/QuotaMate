import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../data/models.dart';
import 'widgets.dart';

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
    final muted = themeColor(context, C.muted);
    Widget reading(bool week) {
      final sample = inPeriod
          .where((v) => (week ? v.secondary : v.primary) != null)
          .firstOrNull;
      final window = week ? sample?.secondary : sample?.primary;
      return Expanded(
        child: Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label(week ? '每周额度 · 采样时剩余' : '5 小时额度 · 采样时剩余', color: muted),
              label(
                window == null ? '—' : '${window.remaining}%',
                size: 30,
                weight: FontWeight.w600,
              ),
              if (sample != null)
                label(
                  sampleDate(sample.observed),
                  size: 12,
                  color: muted,
                  localize: false,
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
          Expanded(child: label(title, color: muted, size: 13)),
          Flexible(child: label(value, size: 13, lines: 2)),
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
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MiniHeading(
                '额度采样趋势',
                trailing: ChipLabel('采样 ${timestamps.length} 条'),
              ),
              const SizedBox(height: 12),
              if (timestamps.isEmpty) ...[
                label('所选周期没有已核对的额度快照。', color: muted),
                if (samples.isNotEmpty)
                  label(
                    '最近采样：${sampleDate(samples.first.observed)}',
                    size: 12,
                    color: muted,
                  ),
              ] else ...[
                Wrap(
                  spacing: 16,
                  children: [
                    label('5 小时剩余', color: themeColor(context, C.blue)),
                    label('每周剩余', color: themeColor(context, C.green)),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 144,
                  child: LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: 100,
                      minX: 0,
                      maxX: DateTime(
                        c.now.year,
                        c.now.month,
                        c.now.day + 1,
                      ).difference(c.rangeStart).inSeconds.toDouble(),
                      borderData: FlBorderData(show: false),
                      gridData: const FlGridData(
                        drawVerticalLine: false,
                        horizontalInterval: 25,
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
                            interval: 50,
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
                            barWidth: 0,
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
                            dotData: const FlDotData(show: true),
                          ),
                      ],
                    ),
                    duration: Duration.zero,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    label(
                      c.days == 1
                          ? '00:00'
                          : sampleDate(c.rangeStart, time: false),
                      size: 11,
                      color: muted,
                    ),
                    const Spacer(),
                    label(
                      c.days == 1 ? '24:00' : sampleDate(c.now, time: false),
                      size: 11,
                      color: muted,
                    ),
                  ],
                ),
                const Divider(),
                label(
                  '最近采样：${sampleDate(inPeriod.first.observed)}',
                  size: 12,
                  color: muted,
                ),
                label(inPeriod.first.source, size: 12, color: muted),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MiniHeading('账号日期'),
              const SizedBox(height: 8),
              resetRow(false),
              resetRow(true),
              dateRow(
                '订阅开始日期',
                account?.subscriptionDates?.startedAt == null
                    ? '未提供'
                    : sampleDate(
                        account!.subscriptionDates!.startedAt!,
                        time: false,
                      ),
              ),
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
