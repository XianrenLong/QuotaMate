import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'models.dart';
import 'desktop_platform.dart';
import 'subscription_dates.dart';

class ClaudeAccountChanged implements Exception {}

class ClaudeConnectionResult {
  final AccountSnapshot account;
  final bool authenticated, collectorEnabled;
  final List<AccountSnapshot> samples;
  final String? notice;
  const ClaudeConnectionResult(
    this.account,
    this.authenticated,
    this.collectorEnabled, {
    this.notice,
    this.samples = const [],
  });
}

class ClaudeConnection {
  static const cachedSource = 'Claude 历史额度快照';

  // Old active-query samples remain historical, including immediately after upgrade.
  static AccountSnapshot localSnapshot(AccountSnapshot value) =>
      ['Claude Code 官方额度', 'Claude Code 查询快照'].contains(value.source)
      ? AccountSnapshot(
          email: value.email,
          plan: value.plan,
          authMode: value.authMode,
          primary: value.primary,
          secondary: value.secondary,
          observed: value.observed,
          source: cachedSource,
          identityFingerprint: value.identityFingerprint,
          subscriptionDates: value.subscriptionDates,
        )
      : value;
  static String get defaultRoot => DesktopPlatform().claudeRoot;
  static String get home => DesktopPlatform().home;
  static Map<String, String> environment(String root) =>
      p.normalize(root) == p.normalize(p.join(home, '.claude')) &&
          !Platform.environment.containsKey('CLAUDE_CONFIG_DIR')
      ? {}
      : {'CLAUDE_CONFIG_DIR': root};

  static Future<String?> locate([String? configured]) async {
    final candidates = DesktopPlatform().cliCandidates('claude', configured);
    for (final candidate in candidates) {
      if (await File(candidate).exists()) return candidate;
    }
    if (Platform.isMacOS) {
      final base = Directory(
        p.join(home, 'Library', 'Application Support', 'Claude', 'claude-code'),
      );
      if (await base.exists()) {
        final found = <File>[];
        await for (final version in base.list(followLinks: false)) {
          if (version is! Directory) continue;
          await for (final hash in version.list(followLinks: false)) {
            if (hash is! Directory) continue;
            final file = File(
              p.join(hash.path, 'claude.app', 'Contents', 'MacOS', 'claude'),
            );
            if (await file.exists()) found.add(file);
          }
        }
        found.sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );
        if (found.isNotEmpty) return found.first.path;
      }
    }
    return null;
  }

  static Future<Json> authStatus(String executable, String root) async {
    final process = await Process.start(executable, [
      'auth',
      'status',
    ], environment: environment(root));
    final stdout = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.listen((_) {});
    try {
      final code = await process.exitCode.timeout(const Duration(seconds: 15));
      final output = await stdout;
      if (code != 0 && code != 1) {
        throw StateError('Claude authentication unavailable');
      }
      final result = jsonDecode(output);
      if (result is! Map) throw StateError('Claude authentication unavailable');
      final data = Map<String, dynamic>.from(result);
      if (data['configDirectory'] is String) {
        final expected = await Directory(root).exists()
            ? await Directory(root).resolveSymbolicLinks()
            : p.absolute(root);
        final directory = Directory(data['configDirectory']);
        final actual = await directory.exists()
            ? await directory.resolveSymbolicLinks()
            : p.absolute(directory.path);
        if (p.normalize(expected) != p.normalize(actual)) {
          throw StateError('Claude configuration directory mismatch');
        }
      }
      return data;
    } finally {
      await errors.cancel();
      process.kill();
    }
  }

  static Future<File> loginCommand(
    String executable,
    String root,
    String supportDirectory,
  ) async {
    final directory = Directory(p.join(supportDirectory, 'claude-login'));
    await directory.create(recursive: true);
    await DesktopPlatform.protectDirectory(directory);
    final file = File(
      p.join(
        directory.path,
        'login-${DateTime.now().microsecondsSinceEpoch}.${Platform.isWindows ? 'ps1' : 'command'}',
      ),
    );
    if (Platform.isWindows) {
      final env = environment(root).entries
          .map(
            (entry) =>
                '\$env:${entry.key}=${DesktopPlatform.powershellQuote(entry.value)}',
          )
          .join('\r\n');
      await file.writeAsString(
        '\ufeff$env\r\n& ${DesktopPlatform.powershellQuote(executable)} auth login\r\n',
        flush: true,
      );
    } else {
      final env = environment(root).entries
          .map((entry) => 'export ${entry.key}=${shellQuote(entry.value)}')
          .join('\n');
      await file.writeAsString(
        '#!/bin/sh\n$env\nexec ${shellQuote(executable)} auth login\n',
        flush: true,
      );
    }
    if (!Platform.isWindows) await Process.run('chmod', ['700', file.path]);
    return file;
  }

  static String identityHash(Json auth) => sha256
      .convert(
        utf8.encode(
          '${auth['authMethod']}|${auth['orgId'] ?? ''}|${auth['email'] ?? ''}',
        ),
      )
      .toString();
  static bool hasIdentity(Json auth) =>
      (auth['email'] is String && (auth['email'] as String).isNotEmpty) ||
      (auth['orgId'] is String && (auth['orgId'] as String).isNotEmpty);

  static Future<Json> readJson(String path) async {
    try {
      final file = File(path);
      if (!await file.exists() || await file.length() > 16 * 1024 * 1024) {
        return {};
      }
      final value = jsonDecode(await file.readAsString());
      return value is Map ? Map<String, dynamic>.from(value) : {};
    } on FileSystemException {
      return {};
    } on FormatException {
      return {};
    }
  }

  static String plan(dynamic subscription, dynamic tier) {
    final text = '$subscription $tier'.toLowerCase();
    if (text.contains('max')) {
      return text.contains('20')
          ? 'claude_max20'
          : text.contains('5x')
          ? 'claude_max5'
          : 'claude_max';
    }
    if (text.contains('ultra')) return 'claude_ultra';
    if (text.contains('enterprise')) return 'claude_enterprise';
    if (text.contains('team')) return 'claude_team';
    if (text.contains('pro')) return 'claude_pro';
    if (text.contains('free')) return 'claude_free';
    return 'claude_unknown';
  }

  static QuotaWindow? statusWindow(dynamic data, int minutes) {
    if (data is! Map) return null;
    final used = data['used_percentage'];
    final reset = data['resets_at'];
    if (used is! num || !used.isFinite || used < 0 || used > 100) return null;
    return QuotaWindow(
      used.toDouble(),
      minutes,
      reset is num && reset.isFinite && reset > 0 && reset < 4102444800
          ? DateTime.fromMillisecondsSinceEpoch((reset * 1000).round())
          : null,
    );
  }

  static AccountSnapshot? collected(Json value, Json auth, DateTime now) {
    if (auth['loggedIn'] != true ||
        !hasIdentity(auth) ||
        value['identity'] != identityHash(auth)) {
      return null;
    }
    final at = DateTime.tryParse(value['capturedAt']?.toString() ?? '');
    if (at == null || at.isAfter(now.add(const Duration(minutes: 1)))) {
      return null;
    }
    final rates = value['rate_limits'];
    if (rates is! Map) return null;
    return AccountSnapshot(
      email: auth['email'],
      plan: plan(auth['subscriptionType'], auth['rateLimitTier']),
      authMode: 'claude',
      observed: at,
      source: 'Claude Code 状态栏快照',
      identityFingerprint: identityHash(auth),
      primary: statusWindow(rates['five_hour'], 300),
      secondary: statusWindow(rates['seven_day'], 10080),
    );
  }

  static AccountSnapshot? desktop(Json history, Json auth, DateTime now) =>
      desktopSamples(history, auth, now).firstOrNull;

  static List<AccountSnapshot> desktopSamples(
    Json history,
    Json auth,
    DateTime now,
  ) {
    final org = auth['orgId'];
    if (auth['loggedIn'] != true ||
        org is! String ||
        org.isEmpty ||
        history['samples'] is! List) {
      return [];
    }
    final fingerprint = identityHash(auth);
    final result = <AccountSnapshot>[];
    for (final sample in (history['samples'] as List).whereType<Map>()) {
      final t = sample['t'], u = sample['u'];
      if (sample['org'] != org ||
          t is! num ||
          !t.isFinite ||
          t <= 0 ||
          t >= 4102444800000 ||
          u is! Map) {
        continue;
      }
      final at = DateTime.fromMillisecondsSinceEpoch(t.toInt());
      if (at.isAfter(now.add(const Duration(minutes: 1)))) continue;
      QuotaWindow? window(String key, int minutes) {
        final used = u[key];
        return used is num && used.isFinite && used >= 0 && used <= 100
            ? QuotaWindow(used.toDouble(), minutes, null)
            : null;
      }

      final short = window('fh', 300), week = window('sd', 10080);
      if (short == null && week == null) continue;
      result.add(
        AccountSnapshot(
          email: auth['email'],
          plan: plan(auth['subscriptionType'], auth['rateLimitTier']),
          authMode: 'claude',
          observed: at,
          source: 'Claude 桌面用量快照',
          identityFingerprint: fingerprint,
          primary: short,
          secondary: week,
        ),
      );
    }
    return result..sort((a, b) => b.observed.compareTo(a.observed));
  }

  static AccountSnapshot? profileQuota(Json profile, Json auth, DateTime now) {
    final owner = profile['oauthAccount'],
        cache = profile['cachedUsageUtilization'];
    if (auth['loggedIn'] != true ||
        !['claude.ai', 'oauth_token'].contains(auth['authMethod']) ||
        owner is! Map ||
        cache is! Map ||
        owner['accountUuid'] is! String ||
        (owner['accountUuid'] as String).isEmpty ||
        cache['accountUuid'] != owner['accountUuid'] ||
        (auth['accountUuid'] != null &&
            auth['accountUuid'] != owner['accountUuid']) ||
        (cache.containsKey('organizationUuid') &&
            cache['organizationUuid'] != auth['orgId']) ||
        (auth['orgId'] is! String || (auth['orgId'] as String).isEmpty) ||
        owner['organizationUuid'] != auth['orgId'] ||
        SubscriptionDateReader.email(auth['email']) == null ||
        SubscriptionDateReader.email(auth['email']) !=
            SubscriptionDateReader.email(owner['emailAddress'])) {
      return null;
    }
    final t = cache['fetchedAtMs'], data = cache['utilization'];
    if (t is! num ||
        !t.isFinite ||
        t <= 0 ||
        t >= 4102444800000 ||
        data is! Map) {
      return null;
    }
    final at = DateTime.fromMillisecondsSinceEpoch(t.toInt());
    if (at.isAfter(now.add(const Duration(minutes: 1)))) return null;
    QuotaWindow? window(String key, int minutes) {
      final row = data[key];
      if (row is! Map) return null;
      final used = row['utilization'];
      if (used is! num || !used.isFinite || used < 0 || used > 100) return null;
      final reset = SubscriptionDateReader.date(row['resets_at']);
      final validReset =
          reset != null &&
          reset.isAfter(at) &&
          !reset.isAfter(at.add(Duration(minutes: minutes + 1)));
      return QuotaWindow(used.toDouble(), minutes, validReset ? reset : null);
    }

    final short = window('five_hour', 300), week = window('seven_day', 10080);
    if (short == null && week == null) return null;
    return AccountSnapshot(
      email: auth['email'],
      plan: plan(auth['subscriptionType'], auth['rateLimitTier']),
      authMode: 'claude',
      observed: at,
      source: 'Claude 配置额度快照',
      identityFingerprint: identityHash(auth),
      primary: short,
      secondary: week,
    );
  }

  static Future<ClaudeConnectionResult> read(
    String? executable,
    String root, {
    Future<Json> Function(String, String)? authenticate,
    AccountSnapshot? cachedAccount,
    String? historyPath,
    bool readSubscriptionDates = true,
  }) async {
    final now = DateTime.now();
    final settings = await readJson(p.join(root, 'settings.json'));
    final line = settings['statusLine'];
    final enabled =
        line is Map &&
        (line['command'] as String? ?? '').contains(
          'quotamate-claude-statusline',
        );
    final auth = executable == null
        ? <String, dynamic>{}
        : await (authenticate ?? authStatus)(executable, root);
    if (auth['loggedIn'] == true) {
      final method = auth['authMethod'];
      final subscription = method == 'claude.ai' || method == 'oauth_token';
      var account = AccountSnapshot(
        email: auth['email'],
        plan: subscription
            ? plan(auth['subscriptionType'], auth['rateLimitTier'])
            : null,
        authMode: subscription
            ? 'claude'
            : method == 'third_party'
            ? 'thirdParty'
            : 'apiKey',
        observed: now,
        source: 'Claude Code 本机登录状态',
      );
      if (subscription) {
        if (!hasIdentity(auth)) {
          throw StateError('Claude account identity unavailable');
        }
        final identity = identityHash(auth);
        final sameAccount =
            hasIdentity(auth) && cachedAccount?.identityFingerprint == identity;
        final snapshot = collected(
          await readJson(p.join(root, 'quotamate', 'usage.json')),
          auth,
          now,
        );
        final desktopHistory =
            (historyPath != null || p.equals(root, p.join(home, '.claude')))
            ? desktopSamples(
                await readJson(historyPath ?? DesktopPlatform().claudeHistory),
                auth,
                now,
              )
            : <AccountSnapshot>[];
        final previous =
            sameAccount &&
                (readSubscriptionDates ||
                    cachedAccount!.source != 'Claude 配置额度快照') &&
                !cachedAccount!.observed.isAfter(
                  now.add(const Duration(minutes: 1)),
                )
            ? AccountSnapshot(
                email: auth['email'],
                plan: plan(auth['subscriptionType'], auth['rateLimitTier']),
                authMode: 'claude',
                observed: cachedAccount.observed,
                primary: cachedAccount.primary,
                secondary: cachedAccount.secondary,
                source: localSnapshot(cachedAccount).source,
                identityFingerprint: identity,
              )
            : null;
        final profile = readSubscriptionDates
            ? await SubscriptionDateReader.claudeProfile(root)
            : null;
        final dates = profile == null
            ? null
            : SubscriptionDateReader.fromClaude(profile, auth, now);
        final profileSample = profile == null
            ? null
            : profileQuota(profile, auth, now);
        // Re-check local identity before attributing a snapshot to the account.
        final after = await (authenticate ?? authStatus)(executable!, root);
        if (after['loggedIn'] != true || identityHash(after) != identity) {
          throw ClaudeAccountChanged();
        }
        final candidates =
            [
                ?snapshot,
                ...desktopHistory,
                ?profileSample,
                ?previous,
              ].where((v) => v.primary != null || v.secondary != null).toList()
              ..sort((a, b) => b.observed.compareTo(a.observed));
        if (candidates.isNotEmpty) account = candidates.first;
        return ClaudeConnectionResult(
          account.withSubscriptionDates(dates),
          true,
          enabled,
          samples: List.unmodifiable(
            {
              for (final sample in candidates)
                (sample.source, sample.observed): sample,
            }.values,
          ),
          notice: candidates.isEmpty
              ? '尚无本地额度快照。可在设置启用状态栏采集，正常使用 Claude Code 后读取。'
              : '额度来自本地快照，保留原采集时间；主动订阅查询已停用。',
        );
      }
      return ClaudeConnectionResult(account, true, enabled);
    }
    // A past account in a configuration file is never promoted to a current login.
    return ClaudeConnectionResult(
      AccountSnapshot(observed: now, source: 'Claude Code 未登录'),
      false,
      enabled,
    );
  }

  static String shellQuote(String value) =>
      "'${value.replaceAll("'", "'\"'\"'")}'";
  static Future<void> enableCollector(
    String executable,
    String root,
    String helper, {
    Future<Json> Function(String, String)? authenticate,
  }) async {
    final auth = await (authenticate ?? authStatus)(executable, root);
    if (auth['loggedIn'] != true ||
        !hasIdentity(auth) ||
        !['claude.ai', 'oauth_token'].contains(auth['authMethod'])) {
      throw StateError('请先登录 Claude Code 订阅账号。');
    }
    if (!await File(helper).exists()) throw StateError('额度采集组件不可用，请使用安装包。');
    final settingsFile = File(p.join(root, 'settings.json'));
    Json settings = {};
    if (await settingsFile.exists()) {
      final decoded = jsonDecode(await settingsFile.readAsString());
      if (decoded is! Map) throw StateError('Claude 设置无法读取，未修改文件。');
      settings = Map<String, dynamic>.from(decoded);
    }
    final private = Directory(p.join(root, 'quotamate'));
    await private.create(recursive: true);
    await DesktopPlatform.protectDirectory(private);
    final installed = p.join(
      private.path,
      'quotamate-claude-statusline${Platform.isWindows ? '.exe' : ''}',
    );
    final staged = '$installed.${DateTime.now().microsecondsSinceEpoch}.tmp';
    try {
      await File(helper).copy(staged);
      if (!Platform.isWindows) await Process.run('chmod', ['700', staged]);
      await File(staged).rename(installed);
    } finally {
      if (await File(staged).exists()) await File(staged).delete();
    }
    final previous = settings['statusLine'];
    final isOurs =
        previous is Map &&
        (previous['command'] as String? ?? '').contains(
          'quotamate-claude-statusline',
        );
    if (!isOurs) {
      await _atomic(File(p.join(private.path, 'original-statusline.json')), {
        'present': settings.containsKey('statusLine'),
        'statusLine': previous,
      }, private);
    }
    settings['statusLine'] = {
      if (previous is Map) ...Map<String, dynamic>.from(previous),
      'type': 'command',
      'command': Platform.isWindows
          ? DesktopPlatform.collectorCommand(
              installed,
              root,
              identityHash(auth),
            )
          : '${shellQuote(installed)} --root ${shellQuote(root)} --identity ${shellQuote(identityHash(auth))}',
    };
    final target = await settingsFile.exists()
        ? File(await settingsFile.resolveSymbolicLinks())
        : settingsFile;
    await _atomic(target, settings, private);
  }

  static Future<bool> disableCollector(String root) async {
    final file = File(p.join(root, 'settings.json'));
    final settings = await readJson(file.path);
    final current = settings['statusLine'];
    if (current is! Map ||
        !(current['command'] as String? ?? '').contains(
          'quotamate-claude-statusline',
        )) {
      return false;
    }
    final private = Directory(p.join(root, 'quotamate'));
    final backup = File(p.join(private.path, 'original-statusline.json'));
    if (!await backup.exists()) throw StateError('原状态栏备份缺失，未修改 Claude 设置。');
    final saved = await readJson(backup.path);
    if (saved['statusLine'] == null && saved['present'] != true) {
      settings.remove('statusLine');
    } else {
      settings['statusLine'] = saved['statusLine'];
    }
    await _atomic(File(await file.resolveSymbolicLinks()), settings, private);
    return true;
  }

  static Future<void> _atomic(File target, Json data, Directory private) async {
    final temp = File(
      p.join(
        private.path,
        '.settings-${DateTime.now().microsecondsSinceEpoch}-$pid.tmp',
      ),
    );
    try {
      await temp.create();
      if (!Platform.isWindows &&
          (await Process.run('chmod', ['600', temp.path])).exitCode != 0) {
        throw StateError('Claude configuration permissions unavailable');
      }
      await temp.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(data)}\n',
        flush: true,
      );
      await temp.rename(target.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }
}
