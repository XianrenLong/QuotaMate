import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quota_mate/controller.dart';
import 'package:quota_mate/data/models.dart';
import 'package:quota_mate/data/quota_reset.dart';
import 'package:quota_mate/data/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const email = 'test@example.com';
  Json identity([String address = email]) => {
    'account': {'type': 'chatgpt', 'email': address, 'planType': 'prolite'},
  };

  test(
    'each acknowledged outcome refreshes limits without guessing new values',
    () async {
      for (final outcome in QuotaResetOutcome.values) {
        final calls = <String>[];
        Future<Json> request(String method, [Json? params]) async {
          calls.add(method);
          if (method == 'account/read') return identity();
          if (method == 'account/rateLimitResetCredit/consume') {
            expect(params, {'idempotencyKey': 'same-logical-attempt'});
            return {'outcome': outcome.name};
          }
          return {
            'rateLimits': {
              'primary': {'usedPercent': 17, 'windowDurationMins': 300},
            },
            'rateLimitResetCredits': {'availableCount': 0},
          };
        }

        final result = await redeemQuotaReset(
          request,
          email: email,
          idempotencyKey: 'same-logical-attempt',
        );
        expect(result.outcome, outcome);
        expect(result.account?.primary?.remaining, 83);
        expect(result.account?.availableQuotaResets, 0);
        expect(calls, [
          'account/read',
          'account/rateLimitResetCredit/consume',
          'account/read',
          'account/rateLimits/read',
        ]);
      }
    },
  );
  test('changed login is rejected before a credit can be consumed', () async {
    var consumed = false;
    Future<Json> request(String method, [Json? params]) async {
      if (method.contains('/consume')) consumed = true;
      return identity('another@example.com');
    }

    await expectLater(
      redeemQuotaReset(request, email: email, idempotencyKey: 'attempt'),
      throwsA(isA<ResetAccountChanged>()),
    );
    expect(consumed, false);
  });
  test('successful redemption remains successful when the subsequent refresh fails', () async {
    var reads = 0;
    Future<Json> request(String method, [Json? params]) async {
      if (method == 'account/read' && reads++ == 0) return identity();
      if (method.contains('/consume')) return {'outcome': 'reset'};
      throw TimeoutException('mock offline');
    }

    final result = await redeemQuotaReset(
      request,
      email: email,
      idempotencyKey: 'attempt',
    );
    expect(result.outcome, QuotaResetOutcome.reset);
    expect(result.account, isNull);
  });

  late Directory dir;
  late LocalStore store;
  late String executable;
  AccountSnapshot snapshot(int count) => AccountSnapshot(
    email: email,
    plan: 'prolite',
    authMode: 'chatgpt',
    observed: DateTime.now(),
    availableQuotaResets: count,
  );
  setUp(() {
    dir = Directory.systemTemp.createTempSync('quota-reset-');
    executable = '${dir.path}/mock-codex';
    File(executable).writeAsStringSync('mock executable; never launched');
    store = LocalStore('${dir.path}/data.db');
    store.set('preferences', {
      'scanEnabled': false,
      'executable': executable,
      'profiles': [
        {'root': dir.path, 'label': 'test'},
      ],
    });
    store.set('quota:${dir.path}', snapshot(1).toJson());
  });
  tearDown(() {
    dir.deleteSync(recursive: true);
  });
  test(
    'uncertain redemption reuses its persisted key across app restarts',
    () async {
      final keys = <String>[];
      Future<QuotaResetResult> reset(
        String cli,
        String root,
        String address,
        String key,
      ) async {
        keys.add(key);
        expect(cli, executable);
        expect(address, email);
        if (keys.length == 1) throw TimeoutException('mock uncertain result');
        return QuotaResetResult(QuotaResetOutcome.alreadyRedeemed, snapshot(0));
      }

      var c = AppController(store, quotaResetter: reset)
        ..accountVerified = true;
      expect(c.canResetQuota, true);
      await c.resetQuota();
      expect(c.accountVerified, false);
      expect(c.canResetQuota, false);
      c.dispose();
      store = LocalStore('${dir.path}/data.db');
      c = AppController(store, quotaResetter: reset)..accountVerified = true;
      addTearDown(c.dispose);
      await c.resetQuota();
      expect(keys, hasLength(2));
      expect(keys[0], keys[1]);
      expect(
        keys[0],
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(c.account?.availableQuotaResets, 0);
      expect(c.accountVerified, true);
      expect(c.canResetQuota, false);
      expect(store.get('quota-reset:${dir.path}:$email'), isNull);
    },
  );
  test(
    'rapid repeated clicks send one redemption and lock account switching',
    () async {
      final response = Completer<QuotaResetResult>();
      var sent = 0;
      final c = AppController(
        store,
        quotaResetter: (_, root, email, key) {
          sent++;
          return response.future;
        },
      )..accountVerified = true;
      addTearDown(c.dispose);
      final pending = c.resetQuota();
      await Future<void>.delayed(Duration.zero);
      expect(c.resettingQuota, true);
      expect(c.canResetQuota, false);
      await c.resetQuota();
      expect(sent, 1);
      response.complete(QuotaResetResult(QuotaResetOutcome.reset, snapshot(0)));
      await pending;
      expect(c.busy, false);
      expect(c.resettingQuota, false);
      expect(c.message, '额度已重置。');
    },
  );
}
