// Synthetic CLI used only by Windows CI; it never accesses a real account.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  if (args.length == 2 && args[0] == 'auth') {
    final root = Platform.environment['CLAUDE_CONFIG_DIR']!;
    await File(p.join(root, 'fixture-commands'))
        .writeAsString('${args.join(' ')}\n', mode: FileMode.append);
    if (args[1] == 'login') return;
    stdout.writeln(
      jsonEncode({
        'loggedIn': true,
        'authMethod': 'claude.ai',
        'orgId': 'sample-org',
        'email': 'person@example.com',
        'subscriptionType': 'pro',
        'configDirectory': root,
      }),
    );
    return;
  }
  if (args.isNotEmpty && args.first == 'app-server') {
    await for (final line
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      final input = jsonDecode(line) as Map;
      if (input['id'] == null) continue;
      final result = switch (input['method']) {
        'initialize' => <String, dynamic>{},
        'account/read' => {
          'account': {
            'type': 'chatgpt',
            'email': 'person@example.com',
            'planType': 'plus',
          },
        },
        'account/rateLimits/read' => {
          'rateLimits': {
            'primary': {'usedPercent': 25, 'windowDurationMins': 300},
          },
        },
        _ => null,
      };
      stdout.writeln(
        jsonEncode({
          'id': input['id'],
          if (result != null)
            'result': result
          else
            'error': {'message': 'Unexpected command'},
        }),
      );
    }
    return;
  }
  exitCode = 91;
}
