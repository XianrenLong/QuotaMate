import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quota_mate/data/desktop_platform.dart';
import 'package:quota_mate/data/claude_connection.dart';
import 'package:quota_mate/data/codex_rpc.dart';

void main() {
  test(
    'Windows roots prefer USERPROFILE and preserve explicit client roots',
    () {
      final platform = DesktopPlatform(
        os: 'windows',
        environment: {
          'USERPROFILE': r'C:\Users\sample',
          'HOME': '/c/wrong-home',
          'APPDATA': r'C:\Users\sample\AppData\Roaming',
        },
      );
      expect(platform.home, r'C:\Users\sample');
      expect(platform.codexRoot, r'C:\Users\sample\.codex');
      expect(platform.claudeRoot, r'C:\Users\sample\.claude');
      expect(
        platform.supportDirectory,
        r'C:\Users\sample\AppData\Roaming\QuotaMate',
      );
      expect(
        platform.claudeHistory,
        r'C:\Users\sample\AppData\Roaming\Claude\plan-usage-history.json',
      );
      expect(
        DesktopPlatform(
          os: 'windows',
          environment: {
            'USERPROFILE': r'C:\Users\sample',
            'CODEX_HOME': r'D:\Profiles\Codex',
            'CLAUDE_CONFIG_DIR': r'D:\Profiles\Claude',
          },
        ).codexRoot,
        r'D:\Profiles\Codex',
      );
    },
  );
  test('Windows CLI discovery includes native and npm vendor executables, never shell shims', () {
    final platform = DesktopPlatform(
      os: 'windows',
      environment: {
        'USERPROFILE': r'C:\Users\sample',
        'APPDATA': r'C:\Users\sample\AppData\Roaming',
        'PATH': r'"C:\Program Files\nodejs";C:\tools;',
      },
    );
    final codex = platform.cliCandidates('codex', r'C:\tools\codex.cmd');
    expect(codex, contains(r'C:\Program Files\nodejs\codex.exe'));
    expect(
      codex,
      contains(
        r'C:\Users\sample\AppData\Roaming\npm\node_modules\@openai\codex\node_modules\@openai\codex-win32-x64\vendor\x86_64-pc-windows-msvc\codex\codex.exe',
      ),
    );
    expect(
      codex.any((v) => v.endsWith('.cmd') || v.startsWith('/Applications/')),
      false,
    );
    expect(
      platform.cliCandidates('claude'),
      contains(r'C:\Users\sample\.local\bin\claude.exe'),
    );
    expect(
      codex,
      isNot(contains('codex.exe')),
    ); // Empty PATH entries cannot search the working directory.
  });
  test('PowerShell encoding preserves Unicode and shell metacharacters as literal arguments', () {
    const root = r"C:\额度 100%\a'b & \$HOME `calc`";
    final command = DesktopPlatform.collectorCommand(
      r'C:\App Files\helper.exe',
      root,
      'account-one',
    );
    final encoded = command.split(' -EncodedCommand ')[1].split(' ').first;
    final bytes = base64Decode(encoded);
    final script = String.fromCharCodes([
      for (var i = 0; i < bytes.length; i += 2) bytes[i] | bytes[i + 1] << 8,
    ]);
    expect(
      script,
      contains("--root 'C:\\额度 100%\\a''b & \\${r'$HOME'} `calc`'"),
    );
    expect(command, contains('# quotamate-claude-statusline'));
  });
  test('macOS paths and CLI candidates retain existing locations', () {
    final platform = DesktopPlatform(
      os: 'macos',
      environment: {'HOME': '/home/sample', 'PATH': '/opt/bin'},
    );
    expect(
      platform.supportDirectory,
      '/home/sample/Library/Application Support/QuotaMate',
    );
    expect(
      platform.cliCandidates('codex'),
      contains('/Applications/Codex.app/Contents/Resources/codex'),
    );
    expect(
      platform.cliCandidates('claude'),
      contains('/opt/homebrew/bin/claude'),
    );
  });
  test('Windows native CLI protocol, login and collector settings work with spaced Unicode paths', () async {
    final fixture = Platform.environment['QUOTAMATE_TEST_CLI'];
    expect(
      fixture,
      isNotNull,
      reason: 'Windows CI must compile its synthetic native fixture',
    );
    final dir = Directory.systemTemp.createTempSync("quota 额度 '&-");
    addTearDown(() => dir.deleteSync(recursive: true));
    final cli = p.join(dir.path, 'official fixture.exe');
    File(fixture!).copySync(cli);
    final root = p.join(dir.path, 'profile');
    Directory(root).createSync();
    final status = await ClaudeConnection.authStatus(cli, root);
    expect(status['email'], 'person@example.com');
    final gpt = await CodexRpc.read(cli, root, readSubscriptionDates: false);
    expect(gpt.email, 'person@example.com');
    expect(gpt.primary?.used, 25);
    final login = await ClaudeConnection.loginCommand(cli, root, dir.path);
    final process = await Process.run('powershell.exe', [
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-EncodedCommand',
      DesktopPlatform.encodedPowerShell(await login.readAsString()),
    ]);
    expect(process.exitCode, 0);
    expect(
      File(p.join(root, 'fixture-commands')).readAsStringSync(),
      contains('auth login'),
    );
    final settings = File(p.join(root, 'settings.json'));
    settings.writeAsStringSync(
      jsonEncode({
        'statusLine': {'type': 'command', 'command': 'original-output'},
        'unrelated': true,
      }),
    );
    await ClaudeConnection.enableCollector(cli, root, cli);
    await ClaudeConnection.enableCollector(
      cli,
      root,
      cli,
    ); // Replacing an existing .exe and settings is safe.
    final enabled = jsonDecode(settings.readAsStringSync()) as Map;
    expect(enabled['statusLine']['command'], contains('-EncodedCommand'));
    expect((await ClaudeConnection.read(cli, root)).collectorEnabled, true);
    expect(await ClaudeConnection.disableCollector(root), true);
    expect(jsonDecode(settings.readAsStringSync()), {
      'statusLine': {'type': 'command', 'command': 'original-output'},
      'unrelated': true,
    });
  }, skip: !Platform.isWindows);
}
