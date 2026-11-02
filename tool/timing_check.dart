import 'dart:convert';
import 'dart:io';

import 'package:quota_mate/data/codex_parser.dart';
import 'package:quota_mate/data/models.dart';

/// Read-only check. Prints only coverage and timing values, never transcript content.
Future<void> main() async {
  final root = Directory(
    '${Platform.environment['CODEX_HOME'] ?? '${Platform.environment['HOME']}/.codex'}/sessions',
  );
  final files =
      root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.jsonl'))
          .toList()
        ..sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );
  for (final f in files.take(3)) {
    final parser = CodexParser();
    final events = <UsageEvent>[];
    await for (final line
        in f
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      final e = parser.parse(line);
      if (e != null) events.add(e);
    }
    final recent = events.reversed.take(100).toList();
    stdout.writeln(
      jsonEncode({
        'recentRecords': recent.length,
        'withSpeed': recent
            .where((e) => e.outputTokensPerSecond != null)
            .length,
        'withFirstOutput': recent
            .where((e) => e.firstTokenSeconds != null)
            .length,
        'latestTimingSamples': recent
            .where(
              (e) =>
                  e.firstTokenSeconds != null ||
                  e.outputTokensPerSecond != null,
            )
            .take(3)
            .map(
              (e) => {
                'speed': e.outputTokensPerSecond,
                'firstSeconds': e.firstTokenSeconds,
                'estimated': e.timingEstimated,
              },
            )
            .toList(),
      }),
    );
  }
}
