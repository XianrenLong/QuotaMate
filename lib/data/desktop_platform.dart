import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Paths and command encoding shared by the UI and the standalone relay.
class DesktopPlatform {
  final String os;
  final Map<String, String> env;
  DesktopPlatform({String? os, Map<String, String>? environment})
    : os = os ?? Platform.operatingSystem,
      env = environment ?? Platform.environment;

  bool get windows => os == 'windows';
  p.Context get path =>
      p.Context(style: windows ? p.Style.windows : p.Style.posix);
  String get home =>
      (windows
          ? env['USERPROFILE'] ?? env['HOME']
          : env['HOME'] ?? env['USERPROFILE']) ??
      '';
  String get supportDirectory => os == 'macos'
      ? path.join(home, 'Library', 'Application Support', 'QuotaMate')
      : windows
      ? path.join(
          env['APPDATA'] ?? path.join(home, 'AppData', 'Roaming'),
          'QuotaMate',
        )
      : path.join(
          env['XDG_DATA_HOME'] ?? path.join(home, '.local', 'share'),
          'QuotaMate',
        );
  String get codexRoot => env['CODEX_HOME'] ?? path.join(home, '.codex');
  String get claudeRoot =>
      env['CLAUDE_CONFIG_DIR'] ?? path.join(home, '.claude');
  String get claudeHistory => windows
      ? path.join(
          env['APPDATA'] ?? path.join(home, 'AppData', 'Roaming'),
          'Claude',
          'plan-usage-history.json',
        )
      : path.join(
          home,
          'Library',
          'Application Support',
          'Claude',
          'plan-usage-history.json',
        );

  List<String> cliCandidates(String name, [String? configured]) {
    final result = <String>[
      if (configured?.isNotEmpty == true) configured!,
      for (var part in (env['PATH'] ?? '').split(windows ? ';' : ':'))
        if (part.trim().isNotEmpty)
          path.join(
            part.replaceAll(RegExp(r'^"|"$'), ''),
            windows ? '$name.exe' : name,
          ),
      path.join(home, '.local', 'bin', windows ? '$name.exe' : name),
    ];
    if (windows && name == 'codex') {
      // npm's .cmd is a shell shim. Launch its native binary directly so paths
      // and user input never pass through cmd.exe command interpolation.
      final prefixes = {
        if (configured != null) path.dirname(configured),
        path.join(
          env['APPDATA'] ?? path.join(home, 'AppData', 'Roaming'),
          'npm',
        ),
        ...((env['PATH'] ?? '').split(';').where((s) => s.isNotEmpty)),
      };
      for (final prefix in prefixes) {
        for (final arch in ['x64', 'arm64']) {
          final triple = arch == 'x64' ? 'x86_64' : 'aarch64';
          final package = path.join(prefix, 'node_modules', '@openai', 'codex');
          for (final base in [
            package,
            path.join(package, 'node_modules', '@openai', 'codex-win32-$arch'),
          ]) {
            result.add(
              path.join(
                base,
                'vendor',
                '$triple-pc-windows-msvc',
                'codex',
                'codex.exe',
              ),
            );
          }
        }
      }
    } else if (os == 'macos') {
      if (name == 'codex') {
        result.addAll([
          '/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex',
          '/Applications/Codex.app/Contents/Resources/codex',
        ]);
      }
      result.addAll(['/opt/homebrew/bin/$name', '/usr/local/bin/$name']);
    }
    return result
        .where((v) => !windows || v.toLowerCase().endsWith('.exe'))
        .toSet()
        .toList();
  }

  static String powershellQuote(String value) =>
      "'${value.replaceAll("'", "''")}'";

  static Future<void> protectDirectory(Directory directory) async {
    if (!Platform.isWindows) {
      if ((await Process.run('chmod', ['700', directory.path])).exitCode != 0) {
        throw FileSystemException('Unable to protect local metadata directory');
      }
      return;
    }
    final system = p.join(
      Platform.environment['SystemRoot'] ?? r'C:\Windows',
      'System32',
    );
    final user = await Process.run(p.join(system, 'whoami.exe'), [
      '/user',
      '/fo',
      'csv',
      '/nh',
    ]);
    final sid = RegExp(r'S-1-(?:\d+-)*\d+')
        .firstMatch('${user.stdout}')
        ?.group(0);
    if (user.exitCode != 0 || sid == null) {
      throw FileSystemException('Unable to identify local metadata owner');
    }
    final permissions = await Process.run(p.join(system, 'icacls.exe'), [
      directory.path,
      '/inheritance:r',
      '/grant:r',
      '*$sid:(OI)(CI)F',
      '*S-1-5-18:(OI)(CI)F',
    ]);
    if (permissions.exitCode != 0) {
      throw FileSystemException('Unable to protect local metadata directory');
    }
  }

  static String encodedPowerShell(String script) => base64Encode([
    for (final unit in script.codeUnits) ...[unit & 255, unit >> 8],
  ]);
  static String collectorCommand(
    String executable,
    String root,
    String identity,
  ) {
    final command =
        r'[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false); ' +
        '& ${powershellQuote(executable)} --root ${powershellQuote(root)} --identity ${powershellQuote(identity)}';
    return 'powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand ${encodedPowerShell(command)} # quotamate-claude-statusline';
  }
}
