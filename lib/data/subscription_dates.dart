import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'models.dart';
import 'desktop_platform.dart';

/// Local metadata only. Never sends, logs or persists a token, nor refreshes it.
abstract final class SubscriptionDateReader {
  static DateTime? date(dynamic value) {
    if (value is! String) return null;
    final parts = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T.+(?:Z|[+-]\d{2}:?\d{2})$')
        .firstMatch(value);
    if (parts == null) return null;
    final year = int.parse(parts[1]!),
        month = int.parse(parts[2]!),
        day = int.parse(parts[3]!);
    final calendar = DateTime.utc(year, month, day);
    if (year < 2000 ||
        year > 2100 ||
        calendar.year != year ||
        calendar.month != month ||
        calendar.day != day) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  static String? email(dynamic value) =>
      value is String && value.trim().isNotEmpty
      ? value.trim().toLowerCase()
      : null;

  static Future<Json?> _read(String path) async {
    try {
      final file = File(path);
      final before = await file.stat();
      if (before.size <= 0 || before.size > 1024 * 1024) return null;
      final text = await file.readAsString();
      final after = await file.stat();
      if (before.size != after.size || before.modified != after.modified) {
        return null;
      }
      final value = jsonDecode(text);
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } catch (_) {
      // Optional metadata must not break the primary account or quota connection.
      return null;
    }
  }

  static SubscriptionDates? fromCodex(Json data, Json account, DateTime now) {
    if (account['type'] != 'chatgpt' ||
        email(account['email']) == null ||
        (data['auth_mode'] != null && data['auth_mode'] != 'chatgpt')) {
      return null;
    }
    final tokens = data['tokens'];
    if (tokens is! Map || tokens['id_token'] is! String) return null;
    final raw = tokens['id_token'] as String;
    if (raw.length > 128 * 1024) return null;
    final parts = raw.split('.');
    if (parts.length != 3) return null;
    try {
      final value = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (value is! Map) return null;
      final profile = value['https://api.openai.com/profile'];
      final tokenEmail =
          email(value['email']) ??
          (profile is Map ? email(profile['email']) : null);
      final auth = value['https://api.openai.com/auth'];
      if (auth is! Map ||
          tokenEmail != email(account['email']) ||
          tokens['account_id'] is! String ||
          (tokens['account_id'] as String).isEmpty ||
          auth['chatgpt_account_id'] != tokens['account_id'] ||
          auth['chatgpt_plan_type'] is! String ||
          account['planType'] is! String ||
          (auth['chatgpt_plan_type'] as String).toLowerCase() !=
              (account['planType'] as String).toLowerCase()) {
        return null;
      }
      final start = date(auth['chatgpt_subscription_active_start']);
      final end = date(auth['chatgpt_subscription_active_until']);
      final checked = date(auth['chatgpt_subscription_last_checked']);
      final limit = now.add(const Duration(minutes: 5));
      if ((start == null && end == null) ||
          (start != null && start.isAfter(limit)) ||
          (checked != null && checked.isAfter(limit)) ||
          (start != null && end != null && !end.isAfter(start))) {
        return null;
      }
      // JWT exp/iat/auth_time and quota resets are deliberately never used.
      return SubscriptionDates(
        startedAt: start,
        periodEndsAt: end,
        lastCheckedAt: checked,
        source: 'codexLoginCache',
      );
    } catch (_) {
      return null;
    }
  }

  static Future<SubscriptionDates?> codex(
    String root,
    Json account, {
    Map<String, String>? environment,
  }) async {
    if ((environment ?? Platform.environment)['CODEX_ACCESS_TOKEN']
                ?.isNotEmpty ==
            true ||
        account['type'] != 'chatgpt') {
      return null;
    }
    final data = await _read(p.join(root, 'auth.json'));
    return data == null ? null : fromCodex(data, account, DateTime.now());
  }

  static SubscriptionDates? fromClaude(Json data, Json auth, DateTime now) {
    final account = data['oauthAccount'];
    if (auth['loggedIn'] != true ||
        !['claude.ai', 'oauth_token'].contains(auth['authMethod']) ||
        account is! Map ||
        email(auth['email']) == null ||
        email(account['emailAddress']) != email(auth['email']) ||
        auth['orgId'] is! String ||
        (auth['orgId'] as String).isEmpty ||
        account['organizationUuid'] != auth['orgId']) {
      return null;
    }
    final start = date(account['subscriptionCreatedAt']);
    final checked = date(account['profileFetchedAt']);
    final limit = now.add(const Duration(minutes: 5));
    if (start == null ||
        start.isAfter(limit) ||
        (checked != null && checked.isAfter(limit))) {
      return null;
    }
    // No billing interval/end is supplied here: never assume month vs year.
    // accountCreatedAt and claudeCodeTrialEndsAt are not paid subscription dates.
    return SubscriptionDates(
      startedAt: start,
      lastCheckedAt: checked,
      source: 'claudeProfile',
    );
  }

  static Future<SubscriptionDates?> claude(
    String root,
    Json auth, {
    String? home,
    Map<String, String>? environment,
  }) async {
    final data = await claudeProfile(
      root,
      home: home,
      environment: environment,
    );
    return data == null ? null : fromClaude(data, auth, DateTime.now());
  }

  static Future<Json?> claudeProfile(
    String root, {
    String? home,
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    final base = home ?? DesktopPlatform(environment: env).home;
    final standard =
        p.normalize(root) == p.normalize(p.join(base, '.claude')) &&
        !env.containsKey('CLAUDE_CONFIG_DIR');
    return _read(
      standard ? p.join(base, '.claude.json') : p.join(root, '.claude.json'),
    );
  }
}
