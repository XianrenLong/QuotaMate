import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quota_mate/data/claude_parser.dart';
import 'package:quota_mate/data/models.dart';
import 'package:quota_mate/data/store.dart';

String record({
  String id = 'message-1',
  int output = 20,
  String type = 'assistant',
  String model = 'claude-opus-5',
}) => jsonEncode({
  'type': type,
  'uuid': 'block-$output',
  'sessionId': 'session',
  'cwd': '/sample/project',
  'timestamp': '2026-11-01T04:00:00Z',
  'message': {
    'id': id,
    'model': model,
    'content': [
      {'type': 'text', 'text': 'PRIVATE CONTENT MUST NOT BE STORED'},
    ],
    'usage': {
      'input_tokens': 5,
      'output_tokens': output,
      'cache_read_input_tokens': 7,
      'cache_creation_input_tokens': 3,
      'cache_creation': {
        'ephemeral_1h_input_tokens': 1,
        'ephemeral_5m_input_tokens': 2,
      },
    },
  },
});

void main() {
  test('Claude input includes reads and writes exactly once; cache TTL changes reference cost', () {
    final parser = ClaudeParser();
    final e = parser.parse(record())!;
    expect(e.tokens.input, 15);
    expect(e.tokens.cached, 7);
    expect(e.tokens.cacheCreation, 3);
    expect(e.tokens.cacheCreation1h, 1);
    expect(e.tokens.total, 35);
    expect(e.freshInput, 8);
    expect(
      const ModelPrice('claude-example', 10, 1, 50).estimate(e.tokens),
      closeTo(1102 / 1000000, .000000001),
    );
    expect(e.outputTokensPerSecond, isNull);
    expect(e.firstTokenSeconds, isNull);
    expect(jsonEncode(parser.state), isNot(contains('PRIVATE')));
    final clone = ClaudeParser()
      ..parse(
        jsonEncode({'type': 'user', 'sessionId': 'clone', 'cwd': '/other'}),
      );
    expect(clone.parse(record())!.id, e.id);
  });
  test('malformed, user, synthetic, zero-usage and error records do not invent usage', () {
    final p = ClaudeParser();
    expect(p.parse('{'), isNull);
    expect(p.parse(record(type: 'user')), isNull);
    expect(p.parse(record(model: '<synthetic>')), isNull);
    final j = jsonDecode(record()) as Map<String, dynamic>;
    j['isApiErrorMessage'] = true;
    expect(p.parse(jsonEncode(j)), isNull);
    j.remove('isApiErrorMessage');
    j['timestamp'] = 'invalid';
    expect(p.parse(jsonEncode(j)), isNull);
  });
  test('streamed blocks, cloned files, incremental tails and rewrites preserve one response', () async {
    final dir = Directory.systemTemp.createTempSync('quota-claude-count-');
    final db = '${dir.path}/data.db', root = '${dir.path}/claude';
    final project = Directory('$root/projects/sample')
      ..createSync(recursive: true);
    final file = File('${project.path}/session.jsonl')
      ..writeAsStringSync('${record(output: 10)}\n${record(output: 20)}\n');
    addTearDown(() => dir.deleteSync(recursive: true));
    await scanClaude(db, root);
    var store = LocalStore(db);
    var events = store.events('claude:$root', DateTime(2026), [
      const ModelPrice('claude-opus-5', 5, .5, 25),
    ]);
    expect(events, hasLength(1));
    expect(events.single.tokens.output, 20);
    expect(events.single.tokens.cacheCreation1h, 1);
    expect(store.events(root, DateTime(2026), []), isEmpty);
    expect(
      jsonEncode(
        store.db
            .select('SELECT * FROM usage_events')
            .map((v) => Map<String, dynamic>.from(v))
            .toList(),
      ),
      isNot(contains('PRIVATE')),
    );
    store.close();
    final clone = File('${project.path}/clone.jsonl')
      ..writeAsStringSync('${record(output: 20)}\n');
    await file.writeAsString(record(id: 'message-2'), mode: FileMode.append);
    await scanClaude(db, root);
    store = LocalStore(db);
    expect(store.events('claude:$root', DateTime(2026), []), hasLength(1));
    store.close();
    await file.writeAsString('\n', mode: FileMode.append);
    await scanClaude(db, root);
    store = LocalStore(db);
    expect(store.events('claude:$root', DateTime(2026), []), hasLength(2));
    store.close();
    file.writeAsStringSync('${record(id: 'message-2')}\n');
    await scanClaude(db, root);
    store = LocalStore(db);
    expect(store.events('claude:$root', DateTime(2026), []), hasLength(2));
    store.close();
    clone.writeAsStringSync('');
    await scanClaude(db, root);
    store = LocalStore(db);
    events = store.events('claude:$root', DateTime(2026), []);
    expect(events, hasLength(1));
    expect(events.single.tokens.output, 20);
    store.close();
  });
}
