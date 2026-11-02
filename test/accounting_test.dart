import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quota_mate/data/codex_parser.dart';
import 'package:quota_mate/data/models.dart';
import 'package:quota_mate/data/store.dart';

String meta([String id = 'session-1']) => jsonEncode({
  'type': 'session_meta',
  'timestamp': '2026-10-30T08:00:00Z',
  'payload': {'id': id, 'cwd': '/projects/example'},
});
String token(
  int input,
  int output, {
  int cached = 0,
  int lastInput = 0,
  int lastOutput = 0,
  String at = '2026-10-30T08:01:00Z',
}) => jsonEncode({
  'type': 'event_msg',
  'timestamp': at,
  'payload': {
    'type': 'token_count',
    'info': {
      'total_token_usage': {
        'input_tokens': input,
        'cached_input_tokens': cached,
        'output_tokens': output,
        'reasoning_output_tokens': output ~/ 2,
      },
      'last_token_usage': {
        'input_tokens': lastInput,
        'output_tokens': lastOutput,
      },
    },
  },
});
void main() {
  test('missing or malformed quota windows stay unknown', () {
    expect(QuotaWindow.fromOptional({}), isNull);
    expect(QuotaWindow.fromOptional({'usedPercent': null}), isNull);
    expect(QuotaWindow.fromOptional({'usedPercent': -1}), isNull);
    expect(QuotaWindow.fromOptional({'usedPercent': 100})!.remaining, 0);
  });
  test('cumulative snapshots count deltas, not repeated totals', () {
    final p = CodexParser()..parse(meta());
    final a = p.parse(token(100, 20, cached: 30));
    final b = p.parse(token(250, 50, cached: 90, at: '2026-10-30T08:02:00Z'));
    expect(a!.tokens.total, 120);
    expect(b!.tokens.input, 150);
    expect(b.tokens.cached, 60);
    expect(b.tokens.output, 30);
    expect(p.parse(token(250, 50, cached: 90)), isNull);
  });
  test('cache and reasoning are subsets, not additive token categories', () {
    const t = Tokens(100, 40, 20, 10);
    expect(t.total, 120);
    expect(
      const ModelPrice('m', 10, 1, 20).estimate(t),
      closeTo(.00104, .00000001),
    );
  });
  test('first resumed snapshot uses last usage instead of inherited lifetime totals', () {
    final p = CodexParser()..parse(meta());
    expect(
      p.parse(token(10000, 2000, lastInput: 100, lastOutput: 20))!.tokens.total,
      120,
    );
  });
  test('parser cursor can resume without recounting a cumulative baseline', () {
    final a = CodexParser()..parse(meta());
    a.parse(token(100, 20));
    final b = CodexParser(a.state);
    expect(
      b.parse(token(200, 50, at: '2026-10-30T08:02:00Z'))!.tokens.total,
      130,
    );
  });
  test('counter resets start a new epoch without negative tokens', () {
    final p = CodexParser()..parse(meta());
    p.parse(token(200, 50));
    final e = p.parse(token(20, 5, at: '2026-10-30T08:02:00Z'));
    expect(e!.tokens.total, 25);
    expect(p.epoch, 1);
  });
  test('conversation and malformed records never produce usage', () {
    final p = CodexParser();
    expect(p.parse('{broken'), isNull);
    expect(
      p.parse(
        jsonEncode({
          'type': 'response_item',
          'payload': {'content': 'private text'},
        }),
      ),
      isNull,
    );
    expect(p.state.toString(), isNot(contains('private text')));
  });
  test('expired windows are not treated as restored quota', () {
    final now = DateTime(2026, 10, 30);
    final w = QuotaWindow(80, 300, now.subtract(const Duration(seconds: 1)));
    expect(w.expired(now), true);
    expect(countdown(w.resets, now), '等待额度更新');
  });
  test('incremental scan, archive dedup, torn lines and rewrites', () async {
    final temp = await Directory.systemTemp.createTemp('quota-accounting-');
    addTearDown(() => temp.delete(recursive: true));
    final root = Directory('${temp.path}/codex');
    await Directory('${root.path}/sessions').create(recursive: true);
    await Directory('${root.path}/archived_sessions').create();
    final database = '${temp.path}/usage.db';
    final store = LocalStore(database);
    addTearDown(store.close);
    final file = File('${root.path}/sessions/a.jsonl');
    final first = '${meta()}\n${token(100, 20)}\n';
    await file.writeAsString(first);
    await scanCodex(database, root.path);
    expect(store.events(root.path, DateTime(2020), []).length, 1);
    await File('${root.path}/archived_sessions/a.jsonl').writeAsString(first);
    await scanCodex(database, root.path);
    expect(store.events(root.path, DateTime(2020), []).length, 1);
    final next = token(300, 50, at: '2026-10-30T08:02:00Z');
    await file.writeAsString(
      next.substring(0, next.length ~/ 2),
      mode: FileMode.append,
    );
    await scanCodex(database, root.path);
    expect(store.events(root.path, DateTime(2020), []).length, 1);
    await file.writeAsString(
      '${next.substring(next.length ~/ 2)}\n',
      mode: FileMode.append,
    );
    await scanCodex(database, root.path);
    final s = UsageSummary(store.events(root.path, DateTime(2020), []));
    expect(s.requests, 2);
    expect(s.total, 350);
    await scanCodex(database, root.path);
    expect(
      UsageSummary(store.events(root.path, DateTime(2020), [])).total,
      350,
    );
    await file.writeAsString(
      '${meta()}\n${token(500, 70, at: '2026-10-30T08:03:00Z')}\n',
    );
    await scanCodex(database, root.path);
    expect(
      UsageSummary(store.events(root.path, DateTime(2020), [])).total,
      690,
    ); // archived120 + rewritten570
    expect(
      store.db.select('PRAGMA table_info(usage_events)').map((r) => r['name']),
      isNot(contains('content')),
    );
  });
}
