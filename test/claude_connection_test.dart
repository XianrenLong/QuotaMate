import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quota_mate/data/claude_connection.dart';
import 'package:quota_mate/data/models.dart';
import 'package:quota_mate/data/subscription_info.dart';

void main() {
  final now = DateTime(2026, 11, 1, 12);
  final auth = <String, dynamic>{
    'loggedIn': true,
    'authMethod': 'claude.ai',
    'email': 'sample@example.com',
    'orgId': 'org-current',
    'subscriptionType': 'max',
    'rateLimitTier': 'default_claude_max_20x',
  };
  Future<Directory> profile() async {
    final dir = await Directory.systemTemp.createTemp('quota-usage-read-');
    addTearDown(() => dir.delete(recursive: true));
    return dir;
  }

  test(
    'local-only connection does not invent quota when no snapshot exists',
    () async {
      final dir = await profile();
      final result = await ClaudeConnection.read(
        'mock',
        dir.path,
        authenticate: (_, root) async => auth,
      );
      expect(result.authenticated, true);
      expect(result.account.primary, isNull);
      expect(result.account.secondary, isNull);
      expect(result.notice, contains('尚无本地额度快照'));
    },
  );
  test('statusline samples retain zero usage, provenance and the original time on repeated reads', () async {
    final dir = await profile();
    final at = DateTime.now().subtract(const Duration(minutes: 5));
    Directory('${dir.path}/quotamate').createSync();
    File('${dir.path}/quotamate/usage.json').writeAsStringSync(
      jsonEncode({
        'identity': ClaudeConnection.identityHash(auth),
        'capturedAt': at.toIso8601String(),
        'rate_limits': {
          'five_hour': {'used_percentage': 0},
          'seven_day': {'used_percentage': 20},
        },
      }),
    );
    AccountSnapshot? previous;
    for (var i = 0; i < 2; i++) {
      final result = await ClaudeConnection.read(
        'mock',
        dir.path,
        authenticate: (_, root) async => auth,
        cachedAccount: previous,
      );
      expect(result.account.source, 'Claude Code 状态栏快照');
      expect(result.account.observed, at);
      expect(result.account.primary?.remaining, 100);
      expect(result.account.secondary?.remaining, 80);
      previous = result.account;
    }
  });
  test('upgrade treats recent active-query data as history and never refreshes its timestamp', () async {
    final dir = await profile();
    final at = DateTime.now().subtract(const Duration(seconds: 1));
    for (final identity in [
      ClaudeConnection.identityHash(auth),
      null,
      'wrong',
    ]) {
      final cached = AccountSnapshot(
        email: auth['email'],
        authMode: 'claude',
        observed: at,
        source: 'Claude Code 官方额度',
        identityFingerprint: identity,
        primary: const QuotaWindow(7, 300, null),
      );
      final result = await ClaudeConnection.read(
        'mock',
        dir.path,
        authenticate: (_, root) async => auth,
        cachedAccount: cached,
      );
      if (identity == ClaudeConnection.identityHash(auth)) {
        expect(result.account.source, ClaudeConnection.cachedSource);
        expect(result.account.observed, at);
        expect(result.account.primary?.remaining, 93);
      } else {
        expect(result.account.primary, isNull);
      }
    }
  });
  test('account changes during local reading reject the snapshot', () async {
    final dir = await profile();
    var calls = 0;
    await expectLater(
      ClaudeConnection.read(
        'mock',
        dir.path,
        authenticate: (_, root) async =>
            calls++ == 0 ? auth : {...auth, 'orgId': 'changed'},
      ),
      throwsA(isA<ClaudeAccountChanged>()),
    );
  });
  test('collected windows are bound to identity and retain zero usage, actual reset and sample time', () {
    final snapshot = <String, dynamic>{
      'identity': ClaudeConnection.identityHash(auth),
      'capturedAt': now.toIso8601String(),
      'rate_limits': {
        'five_hour': {
          'used_percentage': 0,
          'resets_at':
              now.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000,
        },
        'seven_day': {
          'used_percentage': 40,
          'resets_at':
              now.add(const Duration(days: 3)).millisecondsSinceEpoch ~/ 1000,
        },
      },
    };
    final account = ClaudeConnection.collected(snapshot, auth, now)!;
    expect(account.primary?.remaining, 100);
    expect(account.secondary?.remaining, 60);
    expect(account.observed, now);
    expect(account.availableQuotaResets, isNull);
    expect(SubscriptionInfo.read(account, now).label, 'Max X20');
    expect(SubscriptionInfo.read(account, now).isPro, false);
    expect(quotaResetText(account), '不适用');
    expect(
      ClaudeConnection.collected(snapshot, {...auth, 'orgId': 'another'}, now),
      isNull,
    );
    expect(
      ClaudeConnection.collected(
        {
          ...snapshot,
          'capturedAt': now.add(const Duration(days: 1)).toIso8601String(),
        },
        auth,
        now,
      ),
      isNull,
    );
    expect(
      ClaudeConnection.statusWindow({'used_percentage': 101}, 300),
      isNull,
    );
    expect(
      ClaudeConnection.statusWindow({'used_percentage': true}, 300),
      isNull,
    );
    expect(
      ClaudeConnection.statusWindow({
        'used_percentage': 50,
        'resets_at': 1e99,
      }, 300)?.resets,
      isNull,
    );
  });
  test('desktop history requires the matching organization and never guesses reset times', () {
    final history = <String, dynamic>{
      'samples': [
        {
          'org': 'another',
          't': now.millisecondsSinceEpoch,
          'u': {'fh': 80, 'sd': 90},
        },
        {
          'org': 'org-current',
          't': now.subtract(const Duration(minutes: 30)).millisecondsSinceEpoch,
          'u': {'fh': 25, 'sd': 40},
        },
      ],
    };
    final a = ClaudeConnection.desktop(history, auth, now)!;
    expect(a.primary?.remaining, 75);
    expect(a.primary?.resets, isNull);
    expect(a.observed, now.subtract(const Duration(minutes: 30)));
    expect(
      ClaudeConnection.desktop(history, {...auth, 'orgId': 'missing'}, now),
      isNull,
    );
  });
  test(
    'a signed-out CLI cannot promote old account metadata or an old usage file',
    () async {
      final dir = Directory.systemTemp.createTempSync('quota-claude-identity-');
      addTearDown(() => dir.deleteSync(recursive: true));
      Directory('${dir.path}/quotamate').createSync();
      File('${dir.path}/.claude.json').writeAsStringSync(
        jsonEncode({
          'oauthAccount': {'emailAddress': 'old@example.com'},
        }),
      );
      File('${dir.path}/quotamate/usage.json').writeAsStringSync(
        jsonEncode({
          'identity': ClaudeConnection.identityHash(auth),
          'capturedAt': DateTime.now().toIso8601String(),
          'rate_limits': {
            'five_hour': {'used_percentage': 12},
          },
        }),
      );
      final result = await ClaudeConnection.read(
        'mock',
        dir.path,
        authenticate: (_, root) async => {
          'loggedIn': false,
          'authMethod': 'none',
        },
      );
      expect(result.authenticated, false);
      expect(result.account.email, isNull);
      expect(result.account.primary, isNull);
    },
  );
  test('install and remove collector preserve unrelated settings and the original status line', () async {
    final dir = Directory.systemTemp.createTempSync("quota-claude space'-");
    addTearDown(() => dir.deleteSync(recursive: true));
    final helper = File('${dir.path}/original helper')
      ..writeAsStringSync('mock native helper');
    final settings = File('${dir.path}/settings.json');
    final original = {
      'statusLine': {
        'type': 'command',
        'command': 'printf original',
        'padding': 3,
      },
      'permissions': {
        'allow': ['Read'],
      },
      'env': {'EXAMPLE': 'unchanged'},
    };
    settings.writeAsStringSync(jsonEncode(original));
    Future<Json> read(String cli, String root) async => auth;
    await ClaudeConnection.enableCollector(
      'mock',
      dir.path,
      helper.path,
      authenticate: read,
    );
    var saved = jsonDecode(settings.readAsStringSync()) as Map;
    expect(saved['permissions'], original['permissions']);
    expect(saved['env'], original['env']);
    expect(saved['statusLine']['padding'], 3);
    expect(
      saved['statusLine']['command'],
      contains('quotamate-claude-statusline'),
    );
    expect(
      saved['statusLine']['command'],
      isNot(contains('sample@example.com')),
    );
    await ClaudeConnection.enableCollector(
      'mock',
      dir.path,
      helper.path,
      authenticate: read,
    );
    expect(await ClaudeConnection.disableCollector(dir.path), true);
    expect(jsonDecode(settings.readAsStringSync()), original);
    await ClaudeConnection.enableCollector(
      'mock',
      dir.path,
      helper.path,
      authenticate: read,
    );
    settings.writeAsStringSync(
      jsonEncode({
        ...original,
        'statusLine': {'type': 'command', 'command': 'printf user-changed'},
      }),
    );
    expect(await ClaudeConnection.disableCollector(dir.path), false);
    expect(
      (jsonDecode(settings.readAsStringSync()) as Map)['statusLine']['command'],
      'printf user-changed',
    );
    settings.writeAsStringSync('{ malformed config');
    await expectLater(
      ClaudeConnection.enableCollector(
        'mock',
        dir.path,
        helper.path,
        authenticate: read,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(settings.readAsStringSync(), '{ malformed config');
  });
  test(
    'sign-in command delegates only to the official terminal tool',
    () async {
      final dir = Directory.systemTemp.createTempSync("quota-login space'-");
      addTearDown(() => dir.deleteSync(recursive: true));
      final command = await ClaudeConnection.loginCommand(
        "${dir.path}/official cli'",
        '${dir.path}/profile',
        dir.path,
      );
      final text = command.readAsStringSync();
      expect(text, contains(' auth login'));
      expect(text, contains('export CLAUDE_CONFIG_DIR='));
      expect(text, isNot(contains('access_token')));
      expect((await Process.run('/bin/sh', ['-n', command.path])).exitCode, 0);
      expect(command.statSync().mode & 0x1ff, 0x1c0);
    },
  );
  test('shell quoting does not interpret spaces, apostrophes or shell metacharacters', () async {
    const value = r"a' b $HOME `printf altered`";
    final output = await Process.run('/bin/sh', [
      '-c',
      'printf %s ${ClaudeConnection.shellQuote(value)}',
    ]);
    expect(output.stdout, value);
  });
  test(
    'API keys and third-party auth never borrow subscription snapshots',
    () async {
      final dir = Directory.systemTemp.createTempSync('quota-claude-api-');
      addTearDown(() => dir.deleteSync(recursive: true));
      for (final method in ['api_key', 'third_party']) {
        final result = await ClaudeConnection.read(
          'mock',
          dir.path,
          authenticate: (_, root) async => {...auth, 'authMethod': method},
        );
        expect(result.authenticated, true);
        expect(result.account.primary, isNull);
        expect(subscriptionValidityText(result.account, now), '不适用');
        expect(quotaResetText(result.account), '不适用');
      }
    },
  );
}
