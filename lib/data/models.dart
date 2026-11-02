import 'dart:math' as math;

import 'provider.dart';

typedef Json = Map<String, dynamic>;

class Tokens {
  final int input, cached, output, reasoning, cacheCreation, cacheCreation1h;
  const Tokens(
    this.input,
    this.cached,
    this.output, [
    this.reasoning = 0,
    this.cacheCreation = 0,
    this.cacheCreation1h = 0,
  ]);
  static const zero = Tokens(0, 0, 0);
  factory Tokens.fromJson(Json j) => Tokens(
    (j['input_tokens'] as num?)?.toInt() ?? 0,
    (j['cached_input_tokens'] as num? ?? j['cache_read_input_tokens'] as num?)
            ?.toInt() ??
        0,
    (j['output_tokens'] as num?)?.toInt() ?? 0,
    (j['reasoning_output_tokens'] as num?)?.toInt() ?? 0,
    (j['cache_creation_input_tokens'] as num?)?.toInt() ?? 0,
    (j['cache_creation_1h_input_tokens'] as num?)?.toInt() ?? 0,
  );
  int get total => input + output;
  Tokens get normalized => Tokens(
    math.max(0, input),
    cached.clamp(0, math.max(0, input)),
    math.max(0, output),
    reasoning.clamp(0, math.max(0, output)),
    cacheCreation.clamp(0, math.max(0, input - cached)),
    cacheCreation1h.clamp(0, math.max(0, cacheCreation)),
  );
  bool same(Tokens b) =>
      input == b.input && output == b.output && cached == b.cached;
  Tokens delta(Tokens b) => Tokens(
    math.max(0, input - b.input),
    math.max(0, cached - b.cached),
    math.max(0, output - b.output),
    math.max(0, reasoning - b.reasoning),
  ).normalized;
  Json toJson() => {
    'input_tokens': input,
    'cached_input_tokens': cached,
    'output_tokens': output,
    'reasoning_output_tokens': reasoning,
    'cache_creation_input_tokens': cacheCreation,
    'cache_creation_1h_input_tokens': cacheCreation1h,
  };
}

class UsageEvent {
  final String id, session, project, model;
  final DateTime at;
  final Tokens tokens;
  final double? cost;
  final double? outputTokensPerSecond, firstTokenSeconds;
  final bool timingEstimated;
  const UsageEvent({
    required this.id,
    required this.session,
    required this.project,
    required this.model,
    required this.at,
    required this.tokens,
    this.cost,
    this.outputTokensPerSecond,
    this.firstTokenSeconds,
    this.timingEstimated = false,
  });
  int get freshInput => math.max(0, tokens.input - tokens.cached);
}

String detailTokenCount(int value, {bool abbreviated = false}) {
  if (abbreviated && value >= 10000) {
    final scale = value >= 1000000 ? 1000000 : 1000;
    return '${(value / scale).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}${scale == 1000 ? 'K' : 'M'}';
  }
  return value.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
}

String detailTime(DateTime at) =>
    '${clockText(at)}:${at.toLocal().second.toString().padLeft(2, '0')}';
String speedText(UsageEvent e) => e.outputTokensPerSecond == null
    ? '—'
    : '${e.timingEstimated ? '≈' : ''}${e.outputTokensPerSecond!.toStringAsFixed(1)} tok/s';
String firstTokenText(UsageEvent e) => e.firstTokenSeconds == null
    ? '—'
    : '${e.timingEstimated ? '≈' : ''}${e.firstTokenSeconds!.toStringAsFixed(1)}s';

class QuotaWindow {
  final double used;
  final int minutes;
  final DateTime? resets;
  const QuotaWindow(this.used, this.minutes, this.resets);
  static QuotaWindow? fromOptional(dynamic value) {
    if (value is! Map) return null;
    final used = value['usedPercent'] ?? value['used_percent'];
    if (used is! num || !used.isFinite || used < 0 || used > 100) return null;
    return QuotaWindow.fromJson(Map<String, dynamic>.from(value));
  }

  factory QuotaWindow.fromJson(Json j) => QuotaWindow(
    (j['usedPercent'] as num? ?? j['used_percent'] as num? ?? 0)
        .toDouble()
        .clamp(0, 100),
    (j['windowDurationMins'] as num? ?? j['window_minutes'] as num? ?? 0)
        .toInt(),
    (j['resetsAt'] ?? j['resets_at']) is num
        ? DateTime.fromMillisecondsSinceEpoch(
            ((j['resetsAt'] ?? j['resets_at']) as num).toInt() * 1000,
          )
        : null,
  );
  int get remaining => (100 - used).round();
  bool expired(DateTime now) => resets != null && !resets!.isAfter(now);
  Json toJson() => {
    'usedPercent': used,
    'windowDurationMins': minutes,
    'resetsAt': resets == null ? null : resets!.millisecondsSinceEpoch ~/ 1000,
  };
}

class AccountSnapshot {
  final String? email, plan, authMode;
  final QuotaWindow? primary, secondary;
  final DateTime observed;
  final String source;
  final String? subscriptionStatus;
  final String? identityFingerprint;
  final DateTime? subscriptionExpiresAt;
  final int? availableQuotaResets;
  const AccountSnapshot({
    this.email,
    this.plan,
    this.authMode,
    this.primary,
    this.secondary,
    required this.observed,
    this.source = 'Codex CLI 登录',
    this.subscriptionStatus,
    this.identityFingerprint,
    this.subscriptionExpiresAt,
    this.availableQuotaResets,
  });
  Json toJson() => {
    'email': email,
    'plan': plan,
    'authMode': authMode,
    'primary': primary?.toJson(),
    'secondary': secondary?.toJson(),
    'observed': observed.toIso8601String(),
    'source': source,
    'subscriptionStatus': subscriptionStatus,
    'identityFingerprint': identityFingerprint,
    'subscriptionExpiresAt': subscriptionExpiresAt?.toIso8601String(),
    'availableQuotaResets': availableQuotaResets,
  };
  factory AccountSnapshot.fromJson(Json j) => AccountSnapshot(
    email: j['email'],
    plan: j['plan'],
    authMode: j['authMode'],
    primary: QuotaWindow.fromOptional(j['primary']),
    secondary: QuotaWindow.fromOptional(j['secondary']),
    observed: DateTime.parse(j['observed']),
    source: j['source'] ?? 'Codex CLI 登录',
    subscriptionStatus: j['subscriptionStatus'],
    identityFingerprint: j['identityFingerprint'],
    subscriptionExpiresAt: DateTime.tryParse(
      j['subscriptionExpiresAt']?.toString() ?? '',
    ),
    availableQuotaResets: (j['availableQuotaResets'] as num?)?.toInt(),
  );
  factory AccountSnapshot.fromRpc(
    Json accountResult,
    Json? rateLimitResult, {
    required DateTime observed,
  }) {
    final account = accountResult['account'] as Map?;
    final buckets = rateLimitResult?['rateLimitsByLimitId'] as Map?;
    final limits = buckets?['codex'] ?? rateLimitResult?['rateLimits'];
    final resetCredits = rateLimitResult?['rateLimitResetCredits'];
    final count = resetCredits is Map ? resetCredits['availableCount'] : null;
    String? plan = account?['planType'];
    if (limits is Map &&
        limits['planType'] is String &&
        limits['planType'] != 'unknown') {
      plan = limits['planType'];
    }
    return AccountSnapshot(
      email: account?['email'],
      plan: plan,
      authMode: account?['type'],
      subscriptionStatus: account?['subscriptionStatus'] as String?,
      subscriptionExpiresAt: DateTime.tryParse(
        account?['subscriptionExpiresAt']?.toString() ?? '',
      ),
      availableQuotaResets:
          count is num && count.isFinite && count >= 0 && count == count.toInt()
          ? count.toInt()
          : null,
      primary: QuotaWindow.fromOptional(
        limits is Map ? limits['primary'] : null,
      ),
      secondary: QuotaWindow.fromOptional(
        limits is Map ? limits['secondary'] : null,
      ),
      observed: observed,
    );
  }
  bool get signedIn => authMode != null;
}

class SourceProfile {
  final String root, label;
  final AiProvider provider;
  const SourceProfile(this.root, this.label, {this.provider = AiProvider.gpt});
  String get scope => provider == AiProvider.gpt ? root : 'claude:$root';
  Json toJson() => {'root': root, 'label': label, 'provider': provider.name};
  factory SourceProfile.fromJson(Json j) => SourceProfile(
    j['root'],
    j['label'],
    provider: j['provider'] == 'claude' ? AiProvider.claude : AiProvider.gpt,
  );
}

class ModelPrice {
  final String model;
  final double input, cached, output;
  final double? cacheWrite5m, cacheWrite1h;
  const ModelPrice(
    this.model,
    this.input,
    this.cached,
    this.output, {
    this.cacheWrite5m,
    this.cacheWrite1h,
  });
  double estimate(Tokens t) {
    final write = t.cacheCreation, hour = t.cacheCreation1h.clamp(0, write);
    final claude = model.startsWith('claude-');
    return ((t.input - t.cached - write).clamp(0, t.input) * input +
            t.cached * cached +
            t.output * output +
            (write - hour) * (cacheWrite5m ?? input * (claude ? 1.25 : 1)) +
            hour * (cacheWrite1h ?? input * (claude ? 2 : 1))) /
        1000000;
  }

  Json toJson() => {
    'model': model,
    'input': input,
    'cached': cached,
    'output': output,
    'cacheWrite5m': cacheWrite5m,
    'cacheWrite1h': cacheWrite1h,
  };
  factory ModelPrice.fromJson(Json j) => ModelPrice(
    j['model'],
    (j['input'] as num).toDouble(),
    (j['cached'] as num).toDouble(),
    (j['output'] as num).toDouble(),
    cacheWrite5m: (j['cacheWrite5m'] as num?)?.toDouble(),
    cacheWrite1h: (j['cacheWrite1h'] as num?)?.toDouble(),
  );
}

class UsageSummary {
  final List<UsageEvent> events;
  const UsageSummary(this.events);
  int get input => events.fold(0, (a, e) => a + e.tokens.input);
  int get output => events.fold(0, (a, e) => a + e.tokens.output);
  int get cached => events.fold(0, (a, e) => a + e.tokens.cached);
  double? get cacheHitPercent {
    final totalInput = input;
    return totalInput > 0 ? cached / totalInput * 100 : null;
  }

  int get total => input + output;
  int get requests => events.length;
  int get projects => events.map((e) => e.project).toSet().length;
  bool get fullyPriced =>
      events.isNotEmpty && events.every((e) => e.cost != null);
  double? get cost =>
      fullyPriced ? events.fold<double>(0, (a, e) => a + e.cost!) : null;
  Map<String, List<UsageEvent>> get grouped {
    final m = <String, List<UsageEvent>>{};
    for (final e in events) {
      (m[e.project] ??= []).add(e);
    }
    return m;
  }
}

String compact(num n) {
  if (n >= 100000000) {
    return '${(n / 100000000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}亿';
  }
  if (n >= 10000) {
    return '${(n / 10000).toStringAsFixed(n >= 1000000 ? 0 : 1).replaceAll(RegExp(r'\.0$'), '')}万';
  }
  if (n >= 1000) {
    return '${(n / 1000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}k';
  }
  return n.toStringAsFixed(0);
}

String clockText(DateTime? at) {
  if (at == null) return '—';
  final local = at.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String countdown(DateTime? at, DateTime now) {
  if (at == null) return '时间未提供';
  final d = at.difference(now);
  if (d.isNegative) return '等待额度更新';
  if (d.inDays > 0) return '${d.inDays}天${d.inHours % 24}小时';
  if (d.inHours > 0) return '${d.inHours}小时${d.inMinutes % 60}分';
  return '${math.max(1, d.inMinutes)}分钟';
}
