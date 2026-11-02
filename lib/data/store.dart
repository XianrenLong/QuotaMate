import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'codex_parser.dart';
import 'claude_parser.dart';
import 'provider.dart';
import 'usage_parser.dart';
import 'models.dart';

class LocalStore {
  final Database db;
  final String path;
  LocalStore(this.path) : db = sqlite3.open(path) {
    db.execute('PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;');
    db.execute(
      '''CREATE TABLE IF NOT EXISTS usage_events (
      scope TEXT NOT NULL, id TEXT NOT NULL, session TEXT NOT NULL, project TEXT NOT NULL,
      model TEXT NOT NULL, at INTEGER NOT NULL, input INTEGER NOT NULL, cached INTEGER NOT NULL,
      output INTEGER NOT NULL, reasoning INTEGER NOT NULL, PRIMARY KEY(scope,id));
      CREATE INDEX IF NOT EXISTS usage_by_time ON usage_events(scope,at);
      CREATE TABLE IF NOT EXISTS event_sources(scope TEXT, id TEXT, file TEXT, PRIMARY KEY(scope,id,file));
      CREATE TABLE IF NOT EXISTS cursors(file TEXT PRIMARY KEY, size INTEGER, offset INTEGER, stamp INTEGER, tail TEXT, state TEXT);
      CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);''',
    );
    if (db.select('PRAGMA user_version').first['user_version'] < 3) {
      db.execute('BEGIN IMMEDIATE');
      try {
        final columns = db
            .select('PRAGMA table_info(usage_events)')
            .map((r) => r['name'])
            .toSet();
        for (final column in {
          'output_tps': 'REAL',
          'first_token_seconds': 'REAL',
          'timing_estimated': 'INTEGER NOT NULL DEFAULT 0',
          'cache_creation': 'INTEGER NOT NULL DEFAULT 0',
          'cache_creation_1h': 'INTEGER NOT NULL DEFAULT 0',
        }.entries) {
          if (!columns.contains(column.key)) {
            db.execute(
              'ALTER TABLE usage_events ADD COLUMN ${column.key} ${column.value}',
            );
          }
        }
        db.execute('PRAGMA user_version=3');
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
    }
  }
  dynamic get(String key) {
    final r = db.select('SELECT value FROM settings WHERE key=?', [key]);
    return r.isEmpty ? null : jsonDecode(r.first['value'] as String);
  }

  void set(String key, dynamic value) => db.execute(
    'INSERT OR REPLACE INTO settings VALUES(?,?)',
    [key, jsonEncode(value)],
  );
  List<UsageEvent> events(
    String scope,
    DateTime start,
    List<ModelPrice> prices,
  ) {
    final byModel = {for (final v in prices) v.model: v};
    return db
        .select(
          'SELECT * FROM usage_events WHERE scope=? AND at>=? ORDER BY at DESC',
          [scope, start.millisecondsSinceEpoch],
        )
        .map((r) {
          final t = Tokens(
            r['input'],
            r['cached'],
            r['output'],
            r['reasoning'],
            r['cache_creation'],
            r['cache_creation_1h'],
          );
          return UsageEvent(
            id: r['id'],
            session: r['session'],
            project: r['project'],
            model: r['model'],
            at: DateTime.fromMillisecondsSinceEpoch(r['at']),
            tokens: t,
            cost:
                (byModel[r['model']] ??
                        prices
                            .where(
                              (price) =>
                                  price.model.startsWith('claude-') &&
                                  ((r['model'] as String).startsWith(
                                        '${price.model}-20',
                                      ) ||
                                      r['model'] == '${price.model}-latest'),
                            )
                            .firstOrNull)
                    ?.estimate(t),
            outputTokensPerSecond: (r['output_tps'] as num?)?.toDouble(),
            firstTokenSeconds: (r['first_token_seconds'] as num?)?.toDouble(),
            timingEstimated: r['timing_estimated'] == 1,
          );
        })
        .toList();
  }

  List<String> models(String scope) => db
      .select(
        'SELECT DISTINCT model FROM usage_events WHERE scope=? ORDER BY model',
        [scope],
      )
      .map((r) => r['model'] as String)
      .toList();
  void clear() {
    db.execute('BEGIN');
    try {
      db.execute(
        'DELETE FROM usage_events; DELETE FROM event_sources; DELETE FROM cursors;',
      );
      db.execute("DELETE FROM settings WHERE key LIKE 'quota:%'");
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() => db.dispose();
}

class ScanResult {
  final int imported, files, errors;
  const ScanResult(this.imported, this.files, this.errors);
}

Future<ScanResult> scanCodex(String database, String root) =>
    Isolate.run(() => _scan(database, root, AiProvider.gpt));
Future<ScanResult> scanClaude(String database, String root) =>
    Isolate.run(() => _scan(database, root, AiProvider.claude));

Future<String> _tail(RandomAccessFile f, int offset) async {
  final start = (offset - 256).clamp(0, offset);
  await f.setPosition(start);
  return sha256.convert(await f.read(offset - start)).toString();
}

Future<ScanResult> _scan(
  String database,
  String root,
  AiProvider provider,
) async {
  final store = LocalStore(database);
  final scope = provider == AiProvider.gpt ? root : 'claude:$root';
  var imported = 0, files = 0, errors = 0;
  try {
    for (final name
        in provider == AiProvider.gpt
            ? ['sessions', 'archived_sessions']
            : ['projects']) {
      final dir = Directory(p.join(root, name));
      if (!await dir.exists()) continue;
      await for (final item in dir.list(recursive: true, followLinks: false)) {
        if (item is! File || !item.path.endsWith('.jsonl')) continue;
        RandomAccessFile? file;
        try {
          final stat = await item.stat();
          final stamp = stat.modified.microsecondsSinceEpoch;
          final existing = store.db.select(
            'SELECT * FROM cursors WHERE file=?',
            [item.path],
          );
          final old = existing.isEmpty ? null : existing.first;
          final oldState = old == null
              ? null
              : jsonDecode(old['state'] as String) as Map;
          final expectedVersion = provider == AiProvider.gpt
              ? CodexParser.version
              : ClaudeParser.version;
          final parserUpgrade =
              oldState != null &&
              (oldState['parserVersion'] != expectedVersion ||
                  (oldState['parserKind'] ?? 'gpt') !=
                      (provider == AiProvider.claude ? 'claude' : 'gpt'));
          if (old != null &&
              !parserUpgrade &&
              old['size'] == stat.size &&
              old['stamp'] == stamp) {
            continue;
          }
          files++;
          file = await item.open();
          var offset = old?['offset'] as int? ?? 0;
          var rewritten = offset > stat.size || parserUpgrade;
          if (!rewritten && offset > 0) {
            rewritten = await _tail(file, offset) != old?['tail'];
          }
          if (rewritten) offset = 0;
          Json? state;
          if (!rewritten && old != null) {
            state = Map<String, dynamic>.from(
              jsonDecode(old['state'] as String),
            );
          }
          final UsageParser parser = provider == AiProvider.gpt
              ? CodexParser(state)
              : ClaudeParser(state);
          await file.setPosition(offset);
          var readOffset = offset, committedOffset = offset;
          var line = BytesBuilder(copy: false);
          var oversized = false;
          final events = <UsageEvent>[];
          while (true) {
            final chunk = await file.read(65536);
            if (chunk.isEmpty) break;
            var begin = 0;
            for (var i = 0; i < chunk.length; i++) {
              if (chunk[i] != 10) continue;
              if (!oversized) line.add(Uint8List.sublistView(chunk, begin, i));
              if (!oversized) {
                final event = parser.parse(
                  utf8.decode(line.takeBytes(), allowMalformed: true),
                );
                if (event != null) events.add(event);
              }
              line = BytesBuilder(copy: false);
              oversized = false;
              committedOffset = readOffset + i + 1;
              begin = i + 1;
            }
            if (begin < chunk.length && !oversized) {
              line.add(Uint8List.sublistView(chunk, begin));
              if (line.length > 8 * 1024 * 1024) {
                oversized = true;
                line.clear();
              }
            }
            readOffset += chunk.length;
          }
          final tail = await _tail(file, committedOffset);
          store.db.execute('BEGIN');
          try {
            if (rewritten) {
              store.db.execute(
                'DELETE FROM event_sources WHERE scope=? AND file=?',
                [scope, item.path],
              );
            }
            final insert = store.db.prepare(
              provider == AiProvider.gpt
                  ? 'INSERT OR IGNORE INTO usage_events(scope,id,session,project,model,at,input,cached,output,reasoning,cache_creation,cache_creation_1h) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)'
                  : '''INSERT INTO usage_events(scope,id,session,project,model,at,input,cached,output,reasoning,cache_creation,cache_creation_1h) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
                 ON CONFLICT(scope,id) DO UPDATE SET session=excluded.session,project=excluded.project,model=excluded.model,at=excluded.at,
                 input=excluded.input,cached=excluded.cached,output=excluded.output,cache_creation=excluded.cache_creation,cache_creation_1h=excluded.cache_creation_1h
                 WHERE excluded.input+excluded.output>usage_events.input+usage_events.output
                 OR (excluded.input+excluded.output=usage_events.input+usage_events.output AND excluded.cache_creation_1h>usage_events.cache_creation_1h)''',
            );
            final link = store.db.prepare(
              'INSERT OR IGNORE INTO event_sources VALUES(?,?,?)',
            );
            try {
              for (final e in events) {
                insert.execute([
                  scope,
                  e.id,
                  e.session,
                  e.project,
                  e.model,
                  e.at.millisecondsSinceEpoch,
                  e.tokens.input,
                  e.tokens.cached,
                  e.tokens.output,
                  e.tokens.reasoning,
                  e.tokens.cacheCreation,
                  e.tokens.cacheCreation1h,
                ]);
                imported += store.db.updatedRows;
                if (e.outputTokensPerSecond != null ||
                    e.firstTokenSeconds != null) {
                  store.db.execute(
                    'UPDATE usage_events SET output_tps=COALESCE(?,output_tps), first_token_seconds=COALESCE(?,first_token_seconds), timing_estimated=? WHERE scope=? AND id=?',
                    [
                      e.outputTokensPerSecond,
                      e.firstTokenSeconds,
                      e.timingEstimated ? 1 : 0,
                      scope,
                      e.id,
                    ],
                  );
                }
                link.execute([scope, e.id, item.path]);
              }
            } finally {
              insert.dispose();
              link.dispose();
            }
            store.db.execute(
              'INSERT OR REPLACE INTO cursors VALUES(?,?,?,?,?,?)',
              [
                item.path,
                stat.size,
                committedOffset,
                stamp,
                tail,
                jsonEncode(parser.state),
              ],
            );
            final quota = parser.quota;
            if (quota != null &&
                (quota.primary != null || quota.secondary != null)) {
              final oldQuota = store.get('local-quota:$scope');
              if (oldQuota == null ||
                  DateTime.parse(oldQuota['observed'])
                      .isBefore(quota.observed)) {
                store.set('local-quota:$scope', quota.toJson());
              }
            }
            if (rewritten) {
              store.db.execute(
                'DELETE FROM usage_events WHERE scope=? AND NOT EXISTS(SELECT 1 FROM event_sources s WHERE s.scope=usage_events.scope AND s.id=usage_events.id)',
                [scope],
              );
            }
            store.db.execute('COMMIT');
          } catch (_) {
            store.db.execute('ROLLBACK');
            rethrow;
          }
        } catch (_) {
          errors++;
        } finally {
          await file?.close();
        }
      }
    }
  } finally {
    store.close();
  }
  return ScanResult(imported, files, errors);
}
