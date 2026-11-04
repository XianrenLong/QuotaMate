import 'dart:math' as math;

import 'app_info.dart';
import 'controller.dart';
import 'data/models.dart';
import 'data/provider.dart';

enum TrayTitle { percent, countdown, both, icon }

/// Everything the native menu bar panel shows, already localized. Native code
/// only lays it out, so its numbers always match the main window.
Map<String, dynamic> trayPayload(AppController c) {
  final t = c.strings.text;
  final active = c.presentedWindow;
  final other = c.otherAccount;
  final otherWindow = _glance(other, c.now).firstOrNull;
  return {
    'title': _title(c, active, otherWindow),
    'tooltip': active != null
        ? t('当前窗口剩余 ${active.remaining}% · ${countdown(active.resets, c.now)}后重置')
        : '${AppInfo.name} · ${t(c.status)}',
    'warning': active != null && active.remaining <= c.threshold,
    'panel': {
      'provider': c.provider.name,
      'providers': [
        for (final p in AiProvider.values) {'id': p.name, 'label': p.label},
      ],
      'account': [
        if (c.account?.signedIn == true || c.demo) t(c.planName),
        ?c.account?.email,
      ].join(' · '),
      'status': [
        t(c.status),
        if (!c.demo && c.account != null)
          _ago(c.now.difference(c.account!.observed), t, c.now),
      ].join(' · '),
      'busy': c.busy,
      'windows': [
        for (final secondary in [false, true]) ?_window(c, secondary),
      ],
      'empty': t(c.isClaude ? '尚无额度快照' : '暂无额度数据'),
      'todayTitle': t('今日'),
      'metrics': _today(c),
      ..._hours(c),
      'actions': {
        'open': t('打开主窗口'),
        'settings': t('设置'),
        'quit': t('退出'),
        'refresh': t('刷新'),
      },
    },
  };
}

String _title(AppController c, QuotaWindow? active, QuotaWindow? other) {
  String percent(QuotaWindow? w) => w == null ? '—' : '${w.remaining}%';
  return switch (c.trayTitle) {
    TrayTitle.icon => '',
    TrayTitle.percent => '${c.providerLabel} ${percent(active)}',
    TrayTitle.countdown =>
      active?.resets == null
          ? '${c.providerLabel} ${percent(active)}'
          : '${c.providerLabel} ${percent(active)} · ${_clock(active!.resets!.difference(c.now))}',
    TrayTitle.both =>
      '${c.providerLabel[0]} ${percent(active)} · '
          '${(c.isClaude ? AiProvider.gpt : AiProvider.claude).label[0]} ${percent(other)}',
  };
}

/// Compact countdown for the menu bar: hours and minutes, or whole days.
String _clock(Duration d) {
  if (d.isNegative) return '0:00';
  if (d.inHours >= 24) return '${d.inDays}d';
  return '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}';
}

String _ago(Duration age, String Function(String) t, DateTime now) =>
    age < const Duration(minutes: 1)
    ? t('刚刚')
    : t('${countdown(now.add(age), now)}前');

String _windowName(QuotaWindow w, bool secondary) => switch (w.minutes) {
  300 => '5 小时窗口',
  10080 => '每周窗口',
  _ => secondary ? '5 小时窗口' : '当前窗口',
};

Map<String, dynamic>? _window(AppController c, bool secondary) {
  final t = c.strings.text;
  final w = c.presentedQuota(
    secondary ? c.account?.secondary : c.account?.primary,
  );
  if (w == null) return null;
  final f = c.forecast(secondary: secondary);
  return {
    'label': t(_windowName(w, secondary)),
    'remaining': w.remaining,
    'value': t('${w.remaining}% 剩余'),
    'reset': t(
      w.resets == null ? '尚未获取恢复时间' : '${countdown(w.resets, c.now)}后重置',
    ),
    'color': secondary ? 'green' : 'blue',
    if (f?.emptyAt != null) ...{
      'forecast': t('照现在的速度，约 ${countdown(f!.emptyAt, c.now)}后用完'),
      'forecastTone': 'warning',
    } else if (f?.remainingAtReset != null) ...{
      'forecast': t('预计重置时剩 ${f!.remainingAtReset}%'),
      'forecastTone': f.remainingAtReset! <= c.threshold
          ? 'warning'
          : 'success',
    },
  };
}

List<Map<String, String>> _today(AppController c) {
  final t = c.strings.text;
  final s = c.today;
  final cost = s.knownCost;
  final hit = s.cacheHitPercent;
  return [
    {'label': 'Token', 'value': t(compact(s.total))},
    {
      'label': t('成本估算'),
      'value': cost == null
          ? '—'
          : '${s.partiallyPriced ? '≈' : ''}\$${cost.toStringAsFixed(2)}',
    },
    {'label': t('缓存命中'), 'value': hit == null ? '—' : '${hit.round()}%'},
  ];
}

/// Tokens per hour for the last twelve hours, scaled to the busiest hour.
Map<String, dynamic> _hours(AppController c) {
  final t = c.strings.text;
  final now = c.now;
  final start = DateTime(
    now.year,
    now.month,
    now.day,
    now.hour,
  ).subtract(const Duration(hours: 11));
  final values = List<double>.filled(12, 0);
  for (final e in c.all) {
    final at = e.at.toLocal();
    if (at.isBefore(start) || at.isAfter(now)) continue;
    values[math.min(11, at.difference(start).inHours)] += e.tokens.total;
  }
  final peak = values.fold<double>(0, math.max);
  return {
    'hours': [for (final v in values) peak == 0 ? 0.0 : v / peak],
    'hoursStart': clockText(start),
    'hoursLabel': t('按小时用量'),
    'hoursEnd': t('现在'),
  };
}

/// Windows of the provider not on screen that are still worth showing: not
/// reset yet and captured within their own window length.
List<QuotaWindow> _glance(AccountSnapshot? a, DateTime now) {
  if (a == null) return [];
  final age = now.difference(a.observed);
  return [
    for (final w in [a.primary, a.secondary])
      if (w != null && !w.expired(now) && age <= Duration(minutes: w.minutes))
        w,
  ];
}
