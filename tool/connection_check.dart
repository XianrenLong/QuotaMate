import 'dart:convert';
import 'dart:io';

import 'package:quota_mate/data/codex_rpc.dart';
import 'package:quota_mate/data/subscription_info.dart';

Future<void> main() async {
  final cli = await CodexRpc.locate();
  if (cli == null) {
    stdout.writeln('Codex not found');
    exitCode = 1;
    return;
  }
  final home =
      Platform.environment['CODEX_HOME'] ??
      '${Platform.environment['HOME']}/.codex';
  try {
    final a = await CodexRpc.read(cli, home);
    stdout.writeln(
      jsonEncode({
        'authMode': a.authMode,
        'planType': a.plan,
        'planDisplay': SubscriptionInfo.read(a, DateTime.now()).label,
        'hasQuota': a.primary != null,
        'primaryRemaining': a.primary?.remaining,
        'secondaryRemaining': a.secondary?.remaining,
        'hasSubscriptionExpiry': a.subscriptionExpiresAt != null,
        'hasSubscriptionPeriodEnd': a.subscriptionDates?.periodEndsAt != null,
        'hasSubscriptionStart': a.subscriptionDates?.startedAt != null,
        'subscriptionDateSource': a.subscriptionDates?.source,
        'availableQuotaResets': a.availableQuotaResets,
        'source': a.source,
      }),
    );
  } catch (_) {
    stdout.writeln(
      'Quota query unavailable; no credentials or raw responses logged.',
    );
    exitCode = 1;
  }
}
