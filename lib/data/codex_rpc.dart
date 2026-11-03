import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../app_info.dart';
import 'models.dart';
import 'desktop_platform.dart';
import 'quota_reset.dart';
import 'subscription_dates.dart';

class CodexRpc {
  static Future<String?> locate([String? configured]) async {
    final candidates = DesktopPlatform().cliCandidates('codex', configured);
    for (final path in candidates) {
      if (await File(path).exists()) return path;
    }
    return null;
  }

  static Future<AccountSnapshot> readIdentity(String executable, String root) =>
      _withClient(
        executable,
        root,
        (request) async => AccountSnapshot.fromRpc(
          await request('account/read', {'refreshToken': false}),
          null,
          observed: DateTime.now(),
        ),
      );

  static Future<AccountSnapshot> read(
    String executable,
    String root, {
    bool readSubscriptionDates = true,
  }) => _withClient(executable, root, (request) async {
    final accountResult = await request('account/read', {
      'refreshToken': false,
    });
    final account = accountResult['account'] as Map?;
    final limits = account?['type'] == 'chatgpt'
        ? await request('account/rateLimits/read')
        : null;
    final dates = readSubscriptionDates && account is Map
        ? await SubscriptionDateReader.codex(
            root,
            Map<String, dynamic>.from(account),
          )
        : null;
    if (dates != null) {
      final check = await request('account/read', {'refreshToken': false});
      final current = check['account'];
      if (current is! Map ||
          [
            'type',
            'email',
            'planType',
            'workspaceName',
          ].any((key) => current[key] != account?[key])) {
        throw StateError(
          'Codex account changed while reading subscription dates',
        );
      }
    }
    return AccountSnapshot.fromRpc(
      accountResult,
      limits,
      observed: DateTime.now(),
    ).withSubscriptionDates(dates);
  });

  static Future<QuotaResetResult> resetQuota(
    String executable,
    String root,
    String email,
    String idempotencyKey,
  ) => _withClient(
    executable,
    root,
    (request) =>
        redeemQuotaReset(request, email: email, idempotencyKey: idempotencyKey),
  );

  static Future<T> _withClient<T>(
    String executable,
    String root,
    Future<T> Function(CodexRequest) action,
  ) async {
    final process = await Process.start(
      executable,
      ['app-server', '--listen', 'stdio://', '-c', 'analytics.enabled=false'],
      environment: {'CODEX_HOME': root},
    );
    final pending = <int, Completer<Json>>{};
    var next = 0;
    Future<Json> request(String method, [Json? params]) {
      final id = next++;
      final c = Completer<Json>();
      pending[id] = c;
      process.stdin.writeln(
        jsonEncode({'id': id, 'method': method, 'params': ?params}),
      );
      return c.future.timeout(const Duration(seconds: 18));
    }

    final sub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            try {
              final j = jsonDecode(line);
              if (j is! Map) return;
              final id = j['id'];
              final c = pending.remove(id);
              if (c == null) return;
              if (j['error'] != null) {
                c.completeError(StateError('官方工具暂时无法返回额度，请稍后重试。'));
              } else {
                c.complete(
                  Map<String, dynamic>.from(j['result'] as Map? ?? {}),
                );
              }
            } on FormatException {
              /* Ignore non-protocol diagnostics. Never persist or print stdout. */
            }
          },
          onError: (Object error) {
            for (final c in pending.values) {
              if (!c.isCompleted) {
                c.completeError(StateError('与 Codex 的连接已中断。'));
              }
            }
            pending.clear();
          },
        );
    // Drain diagnostics without persisting potentially sensitive CLI output.
    final err = process.stderr.listen((_) {});
    try {
      await request('initialize', {
        'clientInfo': {
          'name': 'quota_mate',
          'title': AppInfo.name,
          'version': AppInfo.version,
        },
        'capabilities': {'experimentalApi': false},
      });
      process.stdin.writeln(
        jsonEncode({'method': 'initialized', 'params': {}}),
      );
      return await action(request);
    } on TimeoutException {
      throw StateError('Codex 查询超时，已保留上次数据。');
    } finally {
      // A disconnected pipe during shutdown must not hide an acknowledged
      // redemption result or turn it into an uncertain retry.
      try {
        await sub.cancel();
        await err.cancel();
        await process.stdin.close();
      } catch (_) {
        /* The process may have closed the streams already. */
      } finally {
        process.kill();
        await process.exitCode.timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      }
    }
  }
}
