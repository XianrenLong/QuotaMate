import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'claude_connection.dart';
import 'codex_rpc.dart';
import 'models.dart';
import 'provider.dart';

enum CheckState { passed, warning, failed, skipped }

enum CheckAction { executable, directory, login, refresh, collector }

class ConnectionCheck {
  final String id, title, detail;
  final CheckState state;
  final CheckAction? action;
  const ConnectionCheck(
    this.id,
    this.title,
    this.detail,
    this.state, [
    this.action,
  ]);
}

class ConnectionReport {
  final String scope;
  final DateTime checkedAt;
  final List<ConnectionCheck> checks;
  final String? executable, email;
  const ConnectionReport(
    this.scope,
    this.checkedAt,
    this.checks, {
    this.executable,
    this.email,
  });
  bool get needsAttention => checks.any(
    (c) => c.state == CheckState.failed || c.state == CheckState.warning,
  );
  Json get safeSummary => {
    'checkedAt': checkedAt.toIso8601String(),
    'checks': {for (final c in checks) c.id: c.state.name},
  };
}

class ConnectionDiagnostics {
  static Future<ConnectionReport> run(
    SourceProfile profile, {
    String? configured,
    Future<String?> Function()? locate,
    void Function(List<ConnectionCheck>)? onProgress,
    Future<AccountSnapshot> Function(String, String)? identity,
    Future<AccountSnapshot> Function(String, String)? quota,
    Future<ClaudeConnectionResult> Function(String, String)? claude,
  }) async {
    final checks = <ConnectionCheck>[];
    void add(
      String id,
      String title,
      String detail,
      CheckState state, [
      CheckAction? action,
    ]) {
      checks.add(ConnectionCheck(id, title, detail, state, action));
      onProgress?.call(List.unmodifiable(checks));
    }

    final isClaude = profile.provider == AiProvider.claude;
    String? executable, email;
    try {
      executable =
          await (locate?.call() ??
              (isClaude
                  ? ClaudeConnection.locate(configured)
                  : CodexRpc.locate(configured)));
    } catch (_) {
      /* Report unavailable paths without logging external errors. */
    }
    if (executable == null) {
      add(
        'tool',
        '客户端工具',
        '未找到可执行文件，请指定已安装的官方工具。',
        CheckState.failed,
        CheckAction.executable,
      );
    } else {
      final fallback =
          configured?.isNotEmpty == true && !p.equals(configured!, executable);
      add(
        'tool',
        '客户端工具',
        fallback ? '指定路径不可用，已自动找到其他工具；请核对是否符合预期。' : '已找到工具文件。',
        fallback ? CheckState.warning : CheckState.passed,
        CheckAction.executable,
      );
    }
    var rootAvailable = false, found = false, readable = true;
    try {
      rootAvailable = await Directory(profile.root).exists();
      if (rootAvailable) {
        for (final name
            in isClaude ? ['projects'] : ['sessions', 'archived_sessions']) {
          final directory = Directory(p.join(profile.root, name));
          if (!await directory.exists()) continue;
          found = await directory
              .list(recursive: true, followLinks: false)
              .any((e) => e is File && e.path.endsWith('.jsonl'))
              .timeout(const Duration(seconds: 8));
          if (found) break;
        }
      }
    } catch (_) {
      readable = false;
    }
    add(
      'directory',
      '配置目录',
      !readable
          ? '目录暂不可读，请检查访问权限。'
          : rootAvailable
          ? '配置目录存在。'
          : '配置目录不存在，请选择当前客户端使用的配置根目录。',
      !readable || !rootAvailable ? CheckState.failed : CheckState.passed,
      CheckAction.directory,
    );
    add(
      'records',
      '本机用量记录',
      found ? '已发现本机用量日志；统计仍受时间范围和日志格式影响。' : '尚未发现用量日志；正常使用对应客户端后再刷新。',
      found ? CheckState.passed : CheckState.warning,
      CheckAction.refresh,
    );
    if (executable == null || !rootAvailable || !readable) {
      add(
        'account',
        '所选工具账号',
        executable != null && !rootAvailable
            ? '配置目录尚未建立；可先在官方工具中登录，再重新检测。'
            : '请先处理工具和目录问题，再检测登录状态。',
        CheckState.skipped,
        executable != null && !rootAvailable ? CheckAction.login : null,
      );
      add('quota', '额度数据', '前置检查未完成，尚未读取额度。', CheckState.skipped);
      return ConnectionReport(
        profile.scope,
        DateTime.now(),
        checks,
        executable: executable,
      );
    }
    try {
      if (isClaude) {
        final result =
            await (claude?.call(executable, profile.root) ??
                ClaudeConnection.read(
                  executable,
                  profile.root,
                  readSubscriptionDates: false,
                ));
        email = result.account.email;
        if (result.authenticated &&
            (result.account.primary != null ||
                result.account.secondary != null)) {
          final at = result.account.observed
              .toLocal()
              .toString()
              .split('.')
              .first;
          add('sampleTime', '额度采集时间', at, CheckState.passed);
        }
        add(
          'account',
          '所选工具账号',
          result.authenticated
              ? '已核对所选工具的登录；桌面应用独立账号可能不同。'
              : '官方工具尚未登录，请先完成登录。',
          result.authenticated ? CheckState.passed : CheckState.failed,
          CheckAction.login,
        );
        final window = result.account.primary ?? result.account.secondary;
        final age = DateTime.now().difference(result.account.observed);
        final valid =
            window != null &&
            !window.expired(DateTime.now()) &&
            age >= const Duration(minutes: -1) &&
            age <= Duration(minutes: window.minutes);
        add(
          'quota',
          '额度数据',
          !result.authenticated
              ? '完成登录后再检查额度数据。'
              : result.account.authMode != 'claude'
              ? '当前认证方式不提供订阅额度。'
              : valid
              ? '已读取身份匹配的本地额度快照，请结合采集时间查看。'
              : '尚无可用额度快照；启用采集后正常使用新的终端会话。',
          !result.authenticated || result.account.authMode != 'claude'
              ? CheckState.skipped
              : valid
              ? CheckState.passed
              : CheckState.warning,
          CheckAction.refresh,
        );
        add(
          'collector',
          '状态栏采集',
          result.collectorEnabled
              ? '采集已配置；需由支持的终端会话产生快照。'
              : '采集尚未开启，可在设置启用并保留原状态栏。',
          result.collectorEnabled ? CheckState.passed : CheckState.warning,
          CheckAction.collector,
        );
      } else {
        final account =
            await (identity?.call(executable, profile.root) ??
                CodexRpc.readIdentity(executable, profile.root));
        email = account.email;
        add(
          'account',
          '所选工具账号',
          account.signedIn ? '已核对所选工具的登录；桌面应用独立账号可能不同。' : '官方工具尚未登录，请先完成登录。',
          account.signedIn ? CheckState.passed : CheckState.failed,
          CheckAction.login,
        );
        if (account.authMode != 'chatgpt') {
          add(
            'quota',
            '额度数据',
            account.signedIn ? '当前认证方式不提供订阅额度。' : '完成登录后再检查额度数据。',
            CheckState.skipped,
          );
        } else {
          try {
            final limits =
                await (quota?.call(executable, profile.root) ??
                    CodexRpc.read(
                      executable,
                      profile.root,
                      readSubscriptionDates: false,
                    ));
            if (limits.email != account.email ||
                limits.authMode != account.authMode) {
              email = null;
              final index = checks.indexWhere((c) => c.id == 'account');
              checks[index] = const ConnectionCheck(
                'account',
                '所选工具账号',
                '检测期间账号发生变化，请重新检测。',
                CheckState.warning,
                CheckAction.refresh,
              );
              add(
                'quota',
                '额度数据',
                '检测期间账号发生变化，请重新检测。',
                CheckState.warning,
                CheckAction.refresh,
              );
            } else {
              final valid = [
                limits.primary,
                limits.secondary,
              ].any((w) => w != null && !w.expired(DateTime.now()));
              add(
                'quota',
                '额度数据',
                valid ? '官方工具已返回当前额度。' : '登录有效，但官方工具未返回可用额度窗口。',
                valid ? CheckState.passed : CheckState.warning,
                CheckAction.refresh,
              );
            }
          } catch (_) {
            add(
              'quota',
              '额度数据',
              '登录检查已通过，但额度读取失败；请检查网络并重试。',
              CheckState.failed,
              CheckAction.refresh,
            );
          }
        }
      }
    } catch (_) {
      add(
        'account',
        '所选工具账号',
        '无法确认登录状态；请核对工具版本、配置目录和访问权限。',
        CheckState.failed,
        CheckAction.login,
      );
      add('quota', '额度数据', '登录状态未确认，尚未读取额度。', CheckState.skipped);
    }
    return ConnectionReport(
      profile.scope,
      DateTime.now(),
      checks,
      executable: executable,
      email: email,
    );
  }
}
