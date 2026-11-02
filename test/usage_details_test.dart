import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:quota_mate/data/codex_parser.dart';
import 'package:quota_mate/data/models.dart';
import 'package:quota_mate/data/store.dart';

String metadata() => jsonEncode({
  'type': 'session_meta',
  'timestamp': '2026-10-31T00:00:00Z',
  'payload': {'id': 'timing-session', 'cwd': '/example'},
});
String usage({Map<String, dynamic>? timing}) => jsonEncode({
  'type': 'event_msg',
  'timestamp': '2026-10-31T00:00:03Z',
  'payload': {
    'type': 'token_count',
    'info': {
      'total_token_usage': {
        'input_tokens': 100,
        'cached_input_tokens': 40,
        'output_tokens': 20,
      },
      'timing': ?timing,
    },
  },
});
void main() {
  test('fresh input excludes cached tokens and time fields require explicit measurements', () {
    final parser = CodexParser()..parse(metadata());
    final e = parser.parse(usage())!;
    expect(e.freshInput, 60);
    expect(speedText(e), '—');
    expect(firstTokenText(e), '—');
    expect(detailTokenCount(1341), '1,341');
    expect(detailTokenCount(668000, abbreviated: true), '668K');
  });
  test(
    'timing units and invalid data are handled without inventing measurements',
    () {
      final parser = CodexParser()..parse(metadata());
      final e = parser.parse(
        usage(
          timing: {
            'output_tokens_per_second': 25.5,
            'time_to_first_token_ms': 1200,
            'estimated': true,
          },
        ),
      )!;
      expect(speedText(e), '≈25.5 tok/s');
      expect(firstTokenText(e), '≈1.2s');
      final invalid = CodexParser()..parse(metadata());
      final bad = invalid.parse(
        usage(
          timing: {
            'output_tokens_per_second': -10,
            'time_to_first_token_ms': 'unknown',
          },
        ),
      )!;
      expect(bad.outputTokensPerSecond, isNull);
      expect(bad.firstTokenSeconds, isNull);
    },
  );
  test('old database migrates without losing usage and rescanning backfills timing once', () async {
    final dir = Directory.systemTemp.createTempSync('quota-migration-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/sessions/log.jsonl');
    file.parent.createSync();
    final log =
        '${metadata()}\n${usage(timing: {'output_tokens_per_second': 25.5, 'time_to_first_token_ms': 1200})}\n';
    file.writeAsStringSync(log);
    final parser = CodexParser()..parse(metadata());
    final event = parser.parse(usage())!;
    final path = '${dir.path}/usage.db';
    final old = sqlite3.open(path);
    old.execute(
      'CREATE TABLE usage_events(scope TEXT,id TEXT,session TEXT,project TEXT,model TEXT,at INTEGER,input INTEGER,cached INTEGER,output INTEGER,reasoning INTEGER,PRIMARY KEY(scope,id))',
    );
    old.execute('INSERT INTO usage_events VALUES(?,?,?,?,?,?,?,?,?,?)', [
      dir.path,
      event.id,
      event.session,
      event.project,
      event.model,
      event.at.millisecondsSinceEpoch,
      100,
      40,
      20,
      0,
    ]);
    old.dispose();
    final store = LocalStore(path);
    addTearDown(store.close);
    expect(store.events(dir.path, DateTime(2020), []).single.tokens.total, 120);
    final legacyState = parser.state..remove('parserVersion');
    store.db.execute('INSERT INTO cursors VALUES(?,?,?,?,?,?)', [
      file.path,
      file.lengthSync(),
      file.lengthSync(),
      file.statSync().modified.microsecondsSinceEpoch,
      'legacy',
      jsonEncode(legacyState),
    ]);
    await scanCodex(path, dir.path);
    await scanCodex(path, dir.path);
    final records = store.events(dir.path, DateTime(2020), []);
    expect(records.length, 1);
    expect(records.single.tokens.total, 120);
    expect(records.single.outputTokensPerSecond, 25.5);
    expect(records.single.firstTokenSeconds, 1.2);
  });
}
