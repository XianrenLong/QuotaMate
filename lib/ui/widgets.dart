import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import 'localized.dart';

import 'palette.dart';
export 'palette.dart';

Widget label(
  String text, {
  double size = 14,
  Color? color,
  FontWeight weight = FontWeight.w400,
  int? lines = 1,
  bool localize = true,
}) => LocalizedText(
  text,
  localize: localize,
  maxLines: lines,
  overflow: TextOverflow.ellipsis,
  style: TextStyle(
    fontSize: size,
    color: color ?? C.ink,
    fontWeight: weight,
    height: 1.35,
  ),
);

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Border? border;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.border,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? themeColor(context, C.card),
      borderRadius: BorderRadius.circular(22),
      border: border,
      boxShadow: [
        BoxShadow(
          color: themeColor(context, Color(0x05000000)),
          blurRadius: 15,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: child,
  );
}

class ActionPill extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool primary;
  const ActionPill(
    this.text, {
    super.key,
    this.onTap,
    this.icon,
    this.primary = false,
  });
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: primary ? Colors.white : themeColor(context, C.ink),
      backgroundColor: primary
          ? primaryFill(context)
          : themeColor(context, C.bg),
      padding: EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      minimumSize: Size(0, 40),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 17), SizedBox(width: 9)],
        Flexible(
          child: label(
            text,
            color: primary ? Colors.white : themeColor(context, C.ink),
            weight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class DotLabel extends StatelessWidget {
  final String text;
  final Color color;
  const DotLabel(this.text, {super.key, this.color = C.green});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: themeColor(context, color),
          shape: BoxShape.circle,
        ),
      ),
      SizedBox(width: 9),
      Flexible(
        child: label(text, color: themeColor(context, C.muted), size: 12),
      ),
    ],
  );
}

class ChipLabel extends StatelessWidget {
  final String text;
  final bool green;
  const ChipLabel(this.text, {super.key, this.green = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: BoxDecoration(
      color: green
          ? themeColor(context, Color(0xFFD8F4DA))
          : themeColor(context, Color(0xFFE1EBFF)),
      borderRadius: BorderRadius.circular(30),
    ),
    child: label(
      text,
      size: 12,
      color: green
          ? themeColor(context, Color(0xFF24833A))
          : themeColor(context, C.blue),
      weight: FontWeight.w500,
    ),
  );
}

class Toggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const Toggle(this.value, this.onChanged, {super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 48,
    height: 30,
    child: FittedBox(
      child: CupertinoSwitch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: themeColor(context, C.blue),
      ),
    ),
  );
}

class Segments extends StatelessWidget {
  final List<String> items;
  final int selected;
  final ValueChanged<int> onChanged;
  const Segments(this.items, this.selected, this.onChanged, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: themeColor(context, Color(0xFFEEEDF4)),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        items.length,
        (i) => TextButton(
          onPressed: () => onChanged(i),
          style: TextButton.styleFrom(
            minimumSize: Size(62, 31),
            padding: EdgeInsets.symmetric(horizontal: 17, vertical: 8),
            backgroundColor: i == selected
                ? primaryFill(context)
                : Colors.transparent,
            foregroundColor: i == selected
                ? Colors.white
                : themeColor(context, C.muted),
            shape: StadiumBorder(),
          ),
          child: LocalizedText(items[i], style: TextStyle(fontSize: 13)),
        ),
      ),
    ),
  );
}

class MiniHeading extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget? trailing;
  const MiniHeading(this.title, {super.key, this.icon, this.trailing});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (icon != null) ...[
        Icon(icon, size: 19, color: themeColor(context, C.muted)),
        SizedBox(width: 10),
      ],
      Expanded(child: label(title, weight: FontWeight.w600, size: 15)),
      ?trailing,
    ],
  );
}

class QuotaBar extends StatelessWidget {
  final int? remaining;
  final bool warnLow;
  const QuotaBar(this.remaining, {super.key, this.warnLow = true});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: LinearProgressIndicator(
      value: remaining == null ? 0 : remaining! / 100,
      minHeight: 9,
      backgroundColor: themeColor(context, C.track),
      color: warnLow && remaining != null && remaining! < 20
          ? themeColor(context, C.amber)
          : themeColor(context, C.blue),
    ),
  );
}

class NumberCard extends StatelessWidget {
  final String title, value;
  final IconData icon;
  final String? caption;
  final Widget? bottom;
  final VoidCallback? onTap;
  final bool compactCentered;
  const NumberCard(
    this.title,
    this.value,
    this.icon, {
    super.key,
    this.caption,
    this.bottom,
    this.onTap,
    this.compactCentered = false,
  });
  @override
  Widget build(BuildContext context) {
    if (compactCentered) {
      return Panel(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: themeColor(context, C.muted)),
                SizedBox(width: 9),
                Expanded(
                  child: label(
                    title,
                    size: 13,
                    color: themeColor(context, C.muted),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Center(
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(8),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: label(
                      value,
                      size: 28,
                      weight: FontWeight.w600,
                      color: onTap == null
                          ? themeColor(context, C.ink)
                          : themeColor(context, C.blue),
                    ),
                  ),
                ),
              ),
            ),
            if (caption != null)
              label(caption!, size: 11, color: themeColor(context, C.muted)),
          ],
        ),
      );
    }
    return Panel(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: themeColor(context, C.muted)),
              SizedBox(width: 9),
              Expanded(
                child: label(
                  title,
                  size: 13,
                  color: themeColor(context, C.muted),
                ),
              ),
            ],
          ),
          SizedBox(height: 9),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: label(value, size: 28, weight: FontWeight.w600),
          ),
          if (caption != null) ...[
            SizedBox(height: 4),
            GestureDetector(
              onTap: onTap,
              child: label(
                caption!,
                size: 12,
                color: onTap != null
                    ? themeColor(context, C.blue)
                    : themeColor(context, C.muted),
              ),
            ),
          ],
          if (bottom != null) Expanded(child: bottom!),
        ],
      ),
    );
  }
}

class UsageChart extends StatelessWidget {
  final List<double> values;
  final DateTime now;
  final bool mini, requests, showDates;
  const UsageChart(
    this.values,
    this.now, {
    super.key,
    this.mini = false,
    this.requests = false,
    this.showDates = true,
  });
  @override
  Widget build(BuildContext context) {
    final maxValue = values.fold<double>(0, math.max);
    final base = maxValue <= 0
        ? 1.0
        : math.pow(10, (math.log(maxValue / 3) / math.ln10).floor()).toDouble();
    final ratio = maxValue / 3 / base;
    final step =
        base *
        (ratio <= 1
            ? 1
            : ratio <= 2
            ? 2
            : ratio <= 5
            ? 5
            : 10);
    final maxY = maxValue <= 0 ? 3.0 : (maxValue / step).ceil() * step;
    final spots = values.length == 1
        ? [FlSpot(0, values.first), FlSpot(1, values.first)]
        : [
            for (var i = 0; i < values.length; i++)
              FlSpot(i.toDouble(), values[i]),
          ];
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        minX: 0,
        maxX: math.max(1, values.length - 1).toDouble(),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: !mini,
          drawVerticalLine: true,
          horizontalInterval: step,
          getDrawingHorizontalLine: (_) => FlLine(
            color: themeColor(context, C.line),
            strokeWidth: .8,
            dashArray: [3, 3],
          ),
          getDrawingVerticalLine: (_) => FlLine(
            color: themeColor(context, C.line),
            strokeWidth: .6,
            dashArray: [3, 3],
          ),
        ),
        lineTouchData: LineTouchData(
          enabled: !mini,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => themeColor(context, C.blue),
            getTooltipItems: (spots) => spots
                .map(
                  (s) => LineTooltipItem(
                    AppLocale.text(
                      context,
                      '${showDates ? '' : '${_dateFor(s.x.round())}\n'}${requests ? '${s.y.toInt()} 次' : compact(s.y)}',
                    ),
                    TextStyle(color: Colors.white, fontSize: 12),
                  ),
                )
                .toList(),
          ),
        ),
        titlesData: FlTitlesData(
          show: !mini,
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: showDates ? 40 : 60,
              interval: step,
              getTitlesWidget: (v, m) => Padding(
                padding: EdgeInsets.only(right: 8),
                child: label(
                  requests ? v.toInt().toString() : compact(v),
                  size: 10,
                  color: themeColor(context, C.muted),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: showDates,
              reservedSize: showDates ? 28 : 0,
              interval: values.length > 14 ? 7 : 1,
              getTitlesWidget: (v, m) {
                final i = v.round();
                if ((v - i).abs() > .01 || i >= values.length) {
                  return SizedBox.shrink();
                }
                if (values.length > 14 &&
                    i != values.length - 1 &&
                    i > values.length - 5) {
                  return SizedBox.shrink();
                }
                final d = DateTime(
                  now.year,
                  now.month,
                  now.day,
                ).subtract(Duration(days: values.length - 1 - i));
                return Padding(
                  padding: EdgeInsets.only(top: 9),
                  child: label(
                    '${d.month}/${d.day}',
                    size: 10,
                    color: themeColor(context, C.muted),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: themeColor(context, C.blue),
            barWidth: mini ? 1.7 : 2.3,
            isStrokeCapRound: true,
            dotData: FlDotData(show: !mini),
            belowBarData: BarAreaData(
              show: true,
              color: themeColor(
                context,
                C.blue,
              ).withValues(alpha: mini ? 0.055 : 0.065),
            ),
          ),
        ],
      ),
      duration: Duration(milliseconds: 200),
    );
  }

  String _dateFor(int index) {
    final i = index.clamp(0, math.max(0, values.length - 1)).toInt();
    final d = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: values.length - 1 - i));
    return '${d.month}/${d.day}';
  }
}

class EmptyState extends StatelessWidget {
  final String title, subtitle;
  final VoidCallback? onTap;
  const EmptyState(this.title, this.subtitle, {super.key, this.onTap});
  @override
  Widget build(BuildContext context) => Center(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.folderOpen,
            size: 28,
            color: themeColor(context, C.muted),
          ),
          SizedBox(height: 12),
          label(title, weight: FontWeight.w500),
          SizedBox(height: 5),
          label(
            subtitle,
            size: 12,
            color: themeColor(context, C.muted),
            lines: 3,
          ),
          if (onTap != null) ...[
            SizedBox(height: 14),
            ActionPill('查看数据设置', onTap: onTap),
          ],
        ],
      ),
    ),
  );
}
