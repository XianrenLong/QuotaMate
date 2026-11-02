import 'models.dart';

/// Approximate request timing from rollout metadata, never from conversation text.
/// See docs/data-sources.md for attribution and limitations.
class RequestTiming {
  int? boundary, completed, start, outputEnd, toolAfter, first, usageEnd;
  Tokens? usage;
  RequestTiming([Json? saved]) {
    boundary = saved?['boundary'];
    completed = saved?['completed'];
    start = saved?['start'];
    outputEnd = saved?['outputEnd'];
    toolAfter = saved?['toolAfter'];
    first = saved?['first'];
    usageEnd = saved?['usageEnd'];
    if (saved?['usage'] is Map) {
      usage = Tokens.fromJson(Map<String, dynamic>.from(saved!['usage']));
    }
  }
  Json get state => {
    'boundary': boundary,
    'completed': completed,
    'start': start,
    'outputEnd': outputEnd,
    'toolAfter': toolAfter,
    'first': first,
    'usageEnd': usageEnd,
    'usage': usage?.toJson(),
  };
  void clear() {
    start = null;
    outputEnd = null;
    toolAfter = null;
    first = null;
    usageEnd = null;
    usage = null;
  }

  void moveBoundary(int time) {
    if (boundary == null || time > boundary!) boundary = time;
  }

  bool trailing(int time) =>
      start == null && completed != null && time <= completed! + 100;
  void observe(Json record) {
    final p = record['payload'];
    if (p is! Map) return;
    final time = DateTime.tryParse(record['timestamp']?.toString() ?? '')
        ?.millisecondsSinceEpoch;
    if (time == null) return;
    final type = p['type'];
    if (record['type'] == 'turn_context') {
      moveBoundary(time);
      return;
    }
    if (record['type'] == 'token_usage_record') {
      if (p['usage'] is Map) {
        usageEnd = time;
        usage = Tokens.fromJson(Map<String, dynamic>.from(p['usage']))
            .normalized;
      }
      return;
    }
    if (record['type'] == 'event_msg') {
      if (type == 'task_started' ||
          type == 'turn_aborted' ||
          type == 'task_complete') {
        clear();
        moveBoundary(time);
        return;
      }
      if (type == 'user_message') {
        moveBoundary(time);
        return;
      }
      if (type == 'item_completed') {
        final item = p['item'];
        final started = p['started_at_ms'];
        if (item is Map &&
            ['Reasoning', 'AgentMessage'].contains(item['type']) &&
            started is num &&
            started.isFinite &&
            !trailing(time)) {
          final value = started.toInt();
          if (value <= time && (first == null || value < first!)) first = value;
        }
      }
      return;
    }
    if (record['type'] != 'response_item') return;
    if (type == 'message' && p['role'] != 'assistant') {
      moveBoundary(time);
      return;
    }
    if (type is String && type.endsWith('_output')) {
      moveBoundary(time);
      if (outputEnd != null) toolAfter = time;
      return;
    }
    if (type == 'reasoning' ||
        (type == 'message' && p['role'] == 'assistant') ||
        (type is String && type.endsWith('_call'))) {
      if (trailing(time)) return;
      start ??= boundary;
      outputEnd = time;
      toolAfter = null;
    }
  }

  ({double? speed, double? firstSeconds}) finish(
    int time,
    Tokens delta,
    Tokens? last,
  ) {
    final begin = start ?? boundary;
    final matchingUsage = usage != null && usage!.same(last ?? delta);
    final waitedForTools =
        toolAfter != null && time >= toolAfter! && time - toolAfter! <= 100;
    final end = matchingUsage ? usageEnd : (waitedForTools ? outputEnd : time);
    final firstAt = first;
    final observedOutput = outputEnd != null;
    clear();
    moveBoundary(time);
    completed = time;
    if (!observedOutput ||
        begin == null ||
        end == null ||
        end - begin <= 100 ||
        end - begin > 21600000 ||
        (last != null && last.total > 0 && !delta.same(last))) {
      return (speed: null, firstSeconds: null);
    }
    return (
      speed: delta.output >= 200 ? delta.output * 1000 / (end - begin) : null,
      firstSeconds: firstAt != null && firstAt >= begin && firstAt <= end
          ? (firstAt - begin) / 1000
          : null,
    );
  }
}
