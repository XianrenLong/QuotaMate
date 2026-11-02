import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quota_mate/data/codex_parser.dart';

final base = DateTime.utc(2026, 10, 31);
String record(String type, int ms, Map<String, dynamic> payload) => jsonEncode({
  'type': type,
  'timestamp': base.add(Duration(milliseconds: ms)).toIso8601String(),
  'payload': payload,
});
CodexParser parser() =>
    CodexParser()
      ..parse(record('session_meta', 0, {'id': 'timer', 'cwd': '/example'}));
String count(int ms, {int input = 1000, int output = 300}) =>
    record('event_msg', ms, {
      'type': 'token_count',
      'info': {
        'total_token_usage': {'input_tokens': input, 'output_tokens': output},
      },
    });
void start(CodexParser p, int ms) {
  p.parse(record('event_msg', ms, {'type': 'task_started'}));
  p.parse(record('response_item', ms, {'type': 'message', 'role': 'user'}));
}

void output(CodexParser p, int end, int first) {
  p.parse(
    record('event_msg', end, {
      'type': 'item_completed',
      'started_at_ms': base.millisecondsSinceEpoch + first,
      'item': {'type': 'Reasoning'},
    }),
  );
  p.parse(record('response_item', end, {'type': 'reasoning'}));
}

void main() {
  test('real rollout item start provides first output delay; speed includes request wait', () {
    final p = parser();
    start(p, 0);
    output(p, 9000, 2000);
    final e = p.parse(count(10000))!;
    expect(e.firstTokenSeconds, 2);
    expect(e.outputTokensPerSecond, 30);
    expect(e.timingEstimated, true);
  });
  test('tool execution is not included when token count is flushed with tool result', () {
    final p = parser();
    start(p, 0);
    output(p, 9000, 2000);
    p.parse(record('response_item', 10000, {'type': 'function_call'}));
    p.parse(record('response_item', 60000, {'type': 'function_call_output'}));
    final e = p.parse(count(60001))!;
    expect(e.outputTokensPerSecond, 30);
    expect(e.firstTokenSeconds, 2);
  });
  test('request timing survives an incremental file boundary', () {
    final p = parser();
    start(p, 0);
    output(p, 9000, 2000);
    final next = CodexParser(p.state);
    final e = next.parse(count(10000))!;
    expect(e.firstTokenSeconds, 2);
    expect(e.outputTokensPerSecond, 30);
  });
  test('aborted request and user idle time do not leak into next request', () {
    final p = parser();
    start(p, 0);
    output(p, 9000, 2000);
    p.parse(record('event_msg', 11000, {'type': 'turn_aborted'}));
    start(p, 3600000);
    output(p, 3609000, 3602000);
    final e = p.parse(count(3610000))!;
    expect(e.firstTokenSeconds, 2);
    expect(e.outputTokensPerSecond, 30);
  });
  test('old output flushed after previous usage is not a new response', () {
    final p = parser();
    start(p, 0);
    output(p, 9000, 2000);
    p.parse(count(10000));
    p.parse(
      record('response_item', 10001, {'type': 'message', 'role': 'assistant'}),
    );
    p.parse(
      record('response_item', 3600000, {'type': 'message', 'role': 'user'}),
    );
    output(p, 3609000, 3602000);
    final e = p.parse(count(3610000, input: 2000, output: 600))!;
    expect(e.outputTokensPerSecond, 30);
    expect(e.firstTokenSeconds, 2);
  });
  test('small output keeps speed unknown; tool-only responses have no first-text measurement', () {
    final p = parser();
    start(p, 0);
    p.parse(record('response_item', 5000, {'type': 'function_call'}));
    final e = p.parse(count(5100, output: 50))!;
    expect(e.outputTokensPerSecond, isNull);
    expect(e.firstTokenSeconds, isNull);
  });
}
