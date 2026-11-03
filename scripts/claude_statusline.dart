// Windows standalone relay: stdin metadata only; no credentials or networking.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'package:quota_mate/data/desktop_platform.dart';

typedef Json = Map<String, dynamic>;
Future<Json> read(File file) async {
  try {
    if (await file.length() > 8 * 1024 * 1024) return {};
    final data = jsonDecode(await file.readAsString());
    return data is Map ? Map<String, dynamic>.from(data) : {};
  } catch (_) {
    return {};
  }
}

Future<void> atomic(File file, Json data) async {
  final temporary = File(
    '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    await temporary.writeAsString(jsonEncode(data), flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', temporary.path]);
    }
    await temporary.rename(file.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

Json? window(dynamic value) {
  if (value is! Map) return null;
  final used = value['used_percentage'];
  if (used is! num || !used.isFinite || used < 0 || used > 100) return null;
  final reset = value['resets_at'];
  return {
    'used_percentage': used,
    if (reset is num && reset.isFinite && reset > 0 && reset < 4102444800)
      'resets_at': reset,
  };
}

String? bash() {
  final env = Platform.environment;
  final candidates = [
    if (env['CLAUDE_CODE_GIT_BASH_PATH'] != null)
      env['CLAUDE_CODE_GIT_BASH_PATH']!,
    for (final base in [
      env['ProgramFiles'],
      env['ProgramFiles(x86)'],
      if (env['LOCALAPPDATA'] != null) p.join(env['LOCALAPPDATA']!, 'Programs'),
    ])
      if (base != null) p.join(base, 'Git', 'bin', 'bash.exe'),
    for (final part in (env['PATH'] ?? '').split(';'))
      if (part.isNotEmpty) p.normalize(p.join(part, '..', 'bin', 'bash.exe')),
  ];
  return candidates.where((file) => File(file).existsSync()).firstOrNull;
}

Future<bool> originalOutput(Directory private, List<int> input) async {
  final saved = (await read(
    File(p.join(private.path, 'original-statusline.json')),
  ))['statusLine'];
  final command = saved is Map ? saved['command'] : null;
  if (command is! String ||
      command.isEmpty ||
      command.contains('quotamate-claude-statusline')) {
    return false;
  }
  Process? process;
  Timer? timer;
  try {
    final shell = Platform.isWindows ? bash() : '/bin/sh';
    final system = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    process = await Process.start(
      shell ??
          p.join(
            system,
            'System32',
            'WindowsPowerShell',
            'v1.0',
            'powershell.exe',
          ),
      shell != null
          ? ['-c', command]
          : [
              '-NoLogo',
              '-NoProfile',
              '-NonInteractive',
              '-EncodedCommand',
              DesktopPlatform.encodedPowerShell(command),
            ],
    );
    final running = process;
    timer = Timer(const Duration(seconds: 2), () => running.kill());
    final errors = running.stderr.listen((_) {});
    final output = running.stdout.listen(stdout.add);
    // Write concurrently: existing commands may ignore stdin or produce output first.
    unawaited(() async {
      try {
        running.stdin.add(input);
        await running.stdin.close();
      } catch (_) {}
    }());
    await running.exitCode.timeout(const Duration(seconds: 3));
    await output.cancel();
    await errors.cancel();
    return true;
  } catch (_) {
    return false;
  } finally {
    timer?.cancel();
    process?.kill();
  }
}

Future<void> main(List<String> args) async {
  try {
    String? argument(String name) {
      final i = args.indexOf(name);
      return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
    }

    final root = argument('--root'), identity = argument('--identity');
    if (root == null || identity == null) return;
    final input = <int>[];
    await for (final chunk in stdin) {
      input.addAll(chunk);
      if (input.length > 8 * 1024 * 1024) return;
    }
    final raw = jsonDecode(utf8.decode(input));
    if (raw is! Map) return;
    final private = Directory(p.join(root, 'quotamate'));
    final rates = <String, dynamic>{};
    if (raw['rate_limits'] is Map) {
      for (final key in ['five_hour', 'seven_day']) {
        final value = window(raw['rate_limits'][key]);
        if (value != null) rates[key] = value;
      }
      try {
        await private.create(recursive: true);
        if (!Platform.isWindows) {
          await Process.run('chmod', ['700', private.path]);
        }
        final sessions = Directory(p.join(private.path, 'sessions'));
        await sessions.create();
        final session = raw['session_id'] is String
            ? raw['session_id'] as String
            : 'unknown';
        final digest = sha256.convert(utf8.encode(session)).toString();
        final binding = File(p.join(sessions.path, '$digest.json'));
        var bound = (await read(binding))['identity'];
        if (bound == null) {
          await atomic(binding, {'identity': identity});
          bound = identity;
        }
        if (bound == identity) {
          await atomic(File(p.join(private.path, 'usage.json')), {
            'identity': identity,
            'capturedAt': DateTime.now().toUtc().toIso8601String(),
            'rate_limits': rates,
          });
        }
      } catch (_) {
        /* A collection failure must not interrupt Claude Code. */
      }
    }
    if (await originalOutput(private, input)) return;
    stdout.writeln(
      [
        'Claude',
        for (final key in ['five_hour', 'seven_day'])
          if (rates[key] != null)
            '${key == 'five_hour' ? '5h' : '7d'} ${(rates[key]['used_percentage'] as num).round()}%',
      ].join(' · '),
    );
  } catch (_) {
    /* Never log the original payload or credential-like fields. */
  }
}
