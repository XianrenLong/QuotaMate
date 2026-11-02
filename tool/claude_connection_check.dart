import 'dart:convert';
import 'dart:io';

import 'package:quota_mate/data/claude_connection.dart';
import 'package:quota_mate/data/claude_pricing.dart';
import 'package:quota_mate/data/models.dart';
import 'package:quota_mate/data/store.dart';

Future<void> main() async {
  final directory = await Directory.systemTemp.createTemp(
    'quotamate-claude-check-',
  );
  try {
    final root = ClaudeConnection.defaultRoot;
    final cli = await ClaudeConnection.locate();
    final connection = await ClaudeConnection.read(cli, root);
    final database = '${directory.path}/usage.db';
    final scan = await scanClaude(database, root);
    final store = LocalStore(database);
    final events = store.events(
      'claude:$root',
      DateTime(2000),
      ClaudePricing.presets,
    );
    final summary = UsageSummary(events);
    stdout.writeln(
      jsonEncode({
        'cliFound': cli != null,
        'authenticated': connection.authenticated,
        'authMode': connection.account.authMode,
        'hasEmail': connection.account.email != null,
        'hasQuota':
            connection.account.primary != null ||
            connection.account.secondary != null,
        'source': connection.account.source,
        'fiveHourRemaining': connection.account.primary?.remaining,
        'weeklyRemaining': connection.account.secondary?.remaining,
        'hasResetTime': connection.account.primary?.resets != null,
        'ageSeconds': DateTime.now()
            .difference(connection.account.observed)
            .inSeconds,
        'notice': connection.notice,
        'collectorEnabled': connection.collectorEnabled,
        'files': scan.files,
        'errors': scan.errors,
        'records': events.length,
        'tokens': summary.total,
        'cacheWriteTokens': events.fold<int>(
          0,
          (v, e) => v + e.tokens.cacheCreation,
        ),
        'pricedRecords': events.where((e) => e.cost != null).length,
      }),
    );
    store.close();
  } catch (_) {
    stdout.writeln(
      'Claude check unavailable; no credentials or raw account responses logged.',
    );
    exitCode = 1;
  } finally {
    await directory.delete(recursive: true);
  }
}
