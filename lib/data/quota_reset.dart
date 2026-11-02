import 'dart:math';

import 'models.dart';

typedef CodexRequest = Future<Json> Function(String method, [Json? params]);
typedef QuotaResetter = Future<QuotaResetResult> Function(
  String executable,
  String root,
  String email,
  String idempotencyKey,
);

enum QuotaResetOutcome { reset, alreadyRedeemed, nothingToReset, noCredit }

class QuotaResetResult {
  final QuotaResetOutcome outcome;
  final AccountSnapshot? account;
  const QuotaResetResult(this.outcome, this.account);
}

class ResetAccountChanged implements Exception {}

String newQuotaResetKey() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

Future<QuotaResetResult> redeemQuotaReset(
  CodexRequest request, {
  required String email,
  required String idempotencyKey,
}) async {
  final identity = await request('account/read', {'refreshToken': false});
  void checkIdentity(Json response) {
    final account = response['account'] as Map?;
    if (email.trim().isEmpty ||
        account?['type'] != 'chatgpt' ||
        (account?['email'] as String?)?.toLowerCase() != email.toLowerCase()) {
      throw ResetAccountChanged();
    }
  }

  checkIdentity(identity);
  final response = await request('account/rateLimitResetCredit/consume', {
    'idempotencyKey': idempotencyKey,
  });
  final outcome = QuotaResetOutcome.values.firstWhere(
    (value) => value.name == response['outcome'],
    orElse: () => throw StateError('无法确认重置结果。'),
  );
  // The redemption is already acknowledged. A failed refresh must not turn
  // it into an unconfirmed redemption or cause a second credit to be spent.
  try {
    final updatedIdentity = await request('account/read', {
      'refreshToken': false,
    });
    checkIdentity(updatedIdentity);
    final limits = await request('account/rateLimits/read');
    return QuotaResetResult(
      outcome,
      AccountSnapshot.fromRpc(
        updatedIdentity,
        limits,
        observed: DateTime.now(),
      ),
    );
  } catch (_) {
    return QuotaResetResult(outcome, null);
  }
}
