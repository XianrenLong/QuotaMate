import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'models.dart';
import 'request_timing.dart';
import 'usage_parser.dart';

/// Only metadata and token counters leave this parser. Conversation content is discarded.
class CodexParser implements UsageParser {
  static const version = 3;
  late final RequestTiming requestTiming;
  String session = '', project = '', model = '未识别模型';
  String? parent;
  DateTime? created;
  Tokens? previous;
  int epoch = 0;
  @override
  AccountSnapshot? quota;
  CodexParser([Json? state]) {
    requestTiming = RequestTiming(
      state?['requestTiming'] is Map
          ? Map<String, dynamic>.from(state!['requestTiming'])
          : null,
    );
    if (state == null) return;
    session = state['session'] ?? '';
    project = state['project'] ?? '';
    model = state['model'] ?? '未识别模型';
    parent = state['parent'];
    created = DateTime.tryParse(state['created'] ?? '');
    epoch = state['epoch'] ?? 0;
    if (state['previous'] is Map) {
      previous = Tokens.fromJson(Map<String, dynamic>.from(state['previous']));
    }
  }
  @override
  Json get state => {
    'parserVersion': version,
    'requestTiming': requestTiming.state,
    'session': session,
    'project': project,
    'model': model,
    'parent': parent,
    'created': created?.toIso8601String(),
    'previous': previous?.toJson(),
    'epoch': epoch,
  };
  @override
  UsageEvent? parse(String line) {
    if (!line.contains('"session_meta"') &&
        !line.contains('"turn_context"') &&
        !line.contains('"event_msg"') &&
        !line.contains('"response_item"') &&
        !line.contains('"token_usage_record"')) {
      return null;
    }
    Json j;
    try {
      final value = jsonDecode(line);
      if (value is! Map) return null;
      j = Map<String, dynamic>.from(value);
    } on FormatException {
      return null;
    }
    final p = j['payload'];
    if (p is! Map) return null;
    final at = DateTime.tryParse(j['timestamp']?.toString() ?? '');
    requestTiming.observe(j);
    if (j['type'] == 'session_meta') {
      session = p['id']?.toString() ?? session;
      project = p['cwd']?.toString() ?? project;
      parent = p['forked_from_id']?.toString();
      created = at;
      return null;
    }
    if (j['type'] == 'turn_context') {
      model = p['model']?.toString() ?? model;
      project = p['cwd']?.toString() ?? project;
      return null;
    }
    if (j['type'] != 'event_msg' || p['type'] != 'token_count') return null;
    if (at != null && p['rate_limits'] is Map) {
      final r = Map<String, dynamic>.from(p['rate_limits']);
      // Missing windows are unknown, not 0% used.
      quota = AccountSnapshot(
        primary: QuotaWindow.fromOptional(r['primary']),
        secondary: QuotaWindow.fromOptional(r['secondary']),
        observed: at,
        source: '本机会话快照',
      );
    }
    final info = p['info'];
    if (info is! Map || at == null || session.isEmpty) return null;
    final total = info['total_token_usage'] is Map
        ? Tokens.fromJson(Map<String, dynamic>.from(info['total_token_usage']))
              .normalized
        : null;
    final last = info['last_token_usage'] is Map
        ? Tokens.fromJson(Map<String, dynamic>.from(info['last_token_usage']))
              .normalized
        : null;
    if (total == null && last == null) return null;
    Tokens delta;
    if (total != null) {
      if (previous != null && total.same(previous!)) return null;
      final reset =
          previous != null &&
          (total.input < previous!.input || total.output < previous!.output);
      if (reset) epoch++;
      delta = previous == null || reset
          ? (last != null && last.total > 0 ? last : total)
          : total.delta(previous!);
      previous = total;
    } else {
      delta = last!;
    }
    if (delta.total == 0) return null;
    // Forks may copy earlier parent records. Attribute those records to their original session.
    final canonicalSession =
        parent != null && created != null && at.isBefore(created!)
        ? parent!
        : session;
    final signature =
        '$canonicalSession|$epoch|${total?.input}|${total?.cached}|${total?.output}|${at.toUtc().toIso8601String()}|${total == null ? jsonEncode(delta.toJson()) : ''}';
    final estimated = requestTiming.finish(
      at.millisecondsSinceEpoch,
      delta,
      last,
    );
    final timing = info['timing'] ?? p['timing'];
    double? positive(dynamic value) =>
        value is num && value.isFinite && value >= 0 ? value.toDouble() : null;
    final speed = timing is Map
        ? positive(timing['output_tokens_per_second'])
        : null;
    final firstMs = timing is Map
        ? positive(timing['time_to_first_token_ms'])
        : null;
    return UsageEvent(
      id: sha256.convert(utf8.encode(signature)).toString(),
      session: canonicalSession,
      project: project,
      model: model,
      at: at,
      tokens: delta,
      outputTokensPerSecond: speed ?? estimated.speed,
      firstTokenSeconds: firstMs == null
          ? estimated.firstSeconds
          : firstMs / 1000,
      timingEstimated:
          (timing is Map && timing['estimated'] == true) ||
          (speed == null && estimated.speed != null) ||
          (firstMs == null && estimated.firstSeconds != null),
    );
  }
}
