import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'app_info.dart';
import 'data/codex_rpc.dart';
import 'data/desktop_platform.dart';
import 'data/demo.dart';
import 'data/models.dart';
import 'data/native_bridge.dart';
import 'data/store.dart';
import 'data/reference_pricing.dart';
import 'data/subscription_info.dart';
import 'data/quota_reset.dart';
import 'l10n/strings.dart';
import 'data/appearance.dart';
import 'data/provider.dart';
import 'data/claude_connection.dart';
import 'data/claude_pricing.dart';
import 'data/connection_diagnostics.dart';
import 'data/app_updates.dart';

class AppController extends ChangeNotifier {
  final LocalStore store;
  final QuotaResetter _quotaResetter;
  bool resettingQuota = false;
  AiProvider provider = AiProvider.gpt;
  bool claudeSignedIn = false,
      claudeCollectorEnabled = false,
      connectingClaude = false;
  String? claudeExecutable;
  bool _claudeLoginCanceled = false;
  final Map<AiProvider, int> _selectedByProvider = {};
  bool get isClaude => provider == AiProvider.claude;
  String get providerLabel => provider.label;
  AppLanguage language = AppLanguage.zh;
  AppAppearance appearance = AppAppearance.light;
  AppStrings get strings => AppStrings(language);
  bool demo = false,
      busy = false,
      scanEnabled = true,
      quotaEnabled = true,
      autoRefresh = true,
      notifications = false;
  bool readSubscriptionDates = true;
  bool closeToTray = false, launchAtLogin = false, startupBusy = false;
  bool checkingConnection = false, checkingUpdates = false;
  ConnectionReport? connectionReport;
  AppUpdate? availableUpdate;
  String? updateMessage;
  DateTime? updateCheckedAt;
  UpdateChannel updateChannel = UpdateChannel.alpha;
  bool get isWindows => Platform.isWindows;

  int page = 0, days = 1, refreshMinutes = 5, threshold = 20;
  String? error, message, executable;
  List<SourceProfile> _allProfiles = [];
  List<SourceProfile> get profiles =>
      _allProfiles.where((profile) => profile.provider == provider).toList();
  int selected = 0;
  List<ModelPrice> prices = [];
  List<UsageEvent> all = [];
  AccountSnapshot? account;
  bool accountVerified = false;
  DateTime now = DateTime.now();
  DateTime? lastScan;
  Timer? _timer;
  bool _disposed = false;
  AppController(
    this.store, {
    bool forceDemo = false,
    QuotaResetter? quotaResetter,
  }) : _quotaResetter = quotaResetter ?? CodexRpc.resetQuota {
    final root = DesktopPlatform().codexRoot;
    final s = store.get('preferences') as Map? ?? {};
    language = s['language'] == 'en' ? AppLanguage.en : AppLanguage.zh;
    appearance = AppAppearance.values.firstWhere(
      (value) => value.name == s['appearance'],
      orElse: () => AppAppearance.light,
    );
    // Demo is session-only: old persisted QA preferences must not masquerade as a login.
    demo = forceDemo;
    scanEnabled = s['scanEnabled'] != false;
    quotaEnabled = s['quotaEnabled'] != false;
    autoRefresh = s['autoRefresh'] != false;
    notifications = s['notifications'] == true;
    readSubscriptionDates = s['readSubscriptionDates'] != false;
    closeToTray = s['closeToTray'] == true;
    updateChannel = s['updateChannel'] == 'stable'
        ? UpdateChannel.stable
        : UpdateChannel.alpha;
    refreshMinutes = (s['refreshMinutes'] as int? ?? 5).clamp(1, 60);
    threshold = (s['threshold'] as int? ?? 20).clamp(1, 99);
    executable = s['executable'];
    claudeExecutable = s['claudeExecutable'];
    provider = s['provider'] == 'claude' ? AiProvider.claude : AiProvider.gpt;
    _allProfiles = (s['profiles'] as List? ?? [])
        .map((j) => SourceProfile.fromJson(Map<String, dynamic>.from(j)))
        .toList();
    if (!_allProfiles.any((v) => v.provider == AiProvider.gpt)) {
      _allProfiles.add(SourceProfile(root, '个人账号'));
    }
    if (!_allProfiles.any((v) => v.provider == AiProvider.claude)) {
      _allProfiles.add(
        SourceProfile(
          ClaudeConnection.defaultRoot,
          '个人账号',
          provider: AiProvider.claude,
        ),
      );
    }
    final selections = s['selectedByProvider'] as Map? ?? {};
    for (final item in AiProvider.values) {
      _selectedByProvider[item] =
          selections[item.name] as int? ??
          (item == AiProvider.gpt ? s['selected'] as int? ?? 0 : 0);
    }
    selected = (_selectedByProvider[provider] ?? 0).clamp(
      0,
      profiles.length - 1,
    );
    prices = (s['prices'] as List? ?? [])
        .map((j) => ModelPrice.fromJson(Map<String, dynamic>.from(j)))
        .toList();
    prices = ReferencePricing.seed(store, s, prices);
    prices = ClaudePricing.seed(
      store,
      store.get('preferences') as Map? ?? s,
      prices,
    );
    NativeBridge.channel.setMethodCallHandler((call) async {
      if (call.method == 'refresh') await refresh();
    });
    _load();
  }
  SourceProfile get profile => profiles[selected];
  bool get stale =>
      !demo &&
      account != null &&
      (!accountVerified ||
          !quotaEnabled ||
          now.difference(account!.observed) > const Duration(minutes: 10) ||
          (isClaude &&
              (account!.primary != null || account!.secondary != null)) ||
          account!.source == '本机会话快照');
  QuotaWindow? get activeWindow =>
      isClaude && (account?.primary == null || account!.primary!.expired(now))
      ? account?.secondary
      : account?.primary;
  bool get quotaValid =>
      !stale && activeWindow != null && !activeWindow!.expired(now);
  // Historical presentation is separate from fresh data used by alerts and tray.
  QuotaWindow? presentedQuota(QuotaWindow? window) {
    if (window == null || window.expired(now)) return null;
    if (!stale) return window;
    if (!isClaude ||
        !accountVerified ||
        !quotaEnabled ||
        account?.authMode != 'claude' ||
        account?.identityFingerprint == null ||
        account?.source.contains('快照') != true) {
      return null;
    }
    final age = now.difference(account!.observed);
    return age >= const Duration(minutes: -1) &&
            age <= Duration(minutes: window.minutes)
        ? window
        : null;
  }

  QuotaWindow? get presentedWindow =>
      presentedQuota(activeWindow) ??
      (isClaude ? presentedQuota(account?.secondary) : null);
  bool get quotaHistorical => stale && presentedWindow != null;
  bool get hasClaudeQuotaSnapshot =>
      isClaude && (account?.primary != null || account?.secondary != null);
  String get quotaSampleLabel => hasClaudeQuotaSnapshot
      ? '快照 · ${account!.observed.toLocal().month}/${account!.observed.toLocal().day} ${clockText(account!.observed)}'
      : '尚无额度快照';
  String get quotaSampleDetails => hasClaudeQuotaSnapshot
      ? '${account!.source}\n采集于 ${account!.observed.toLocal()}\n仅显示已采集的快照，不代表实时额度。'
      : '读取已有状态栏或桌面额度快照；不主动查询 Claude 订阅接口。';
  String get claudeEmptyUsageText {
    if (!scanEnabled) return '本机用量扫描已关闭，可在账号页开启。';
    if (all.isEmpty) {
      return '尚未发现本机 Claude Code 用量记录。\n正常使用终端 Claude Code 后刷新；网页与普通桌面聊天暂无 Token 明细。';
    }
    final latest = all
        .reduce((a, b) => a.at.isAfter(b.at) ? a : b)
        .at
        .toLocal();
    return '该周期没有本机 Claude Code 记录，最近记录：${latest.year}/${latest.month}/${latest.day}。\n网页与普通桌面聊天暂无 Token 明细。';
  }

  bool get canResetQuota =>
      !isClaude &&
      !demo &&
      !busy &&
      quotaEnabled &&
      !stale &&
      accountVerified &&
      account?.authMode == 'chatgpt' &&
      account?.email?.isNotEmpty == true &&
      (account?.availableQuotaResets ?? 0) > 0;
  List<UsageEvent> get events {
    final cutoff = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days - 1));
    return all
        .where((e) => !e.at.isBefore(cutoff) && !e.at.isAfter(now))
        .toList();
  }

  UsageSummary get summary => UsageSummary(events);
  UsageSummary get today => UsageSummary(
    all
        .where(
          (e) =>
              !e.at.isBefore(DateTime(now.year, now.month, now.day)) &&
              !e.at.isAfter(now),
        )
        .toList(),
  );
  List<double> values({bool requests = false, int? period}) {
    final n = period ?? days;
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: n - 1));
    final result = List<double>.filled(n, 0);
    for (final e in all) {
      final d = DateTime(
        e.at.year,
        e.at.month,
        e.at.day,
      ).difference(start).inDays;
      if (d >= 0 && d < n && !e.at.isAfter(now)) {
        result[d] += requests ? 1 : e.tokens.total.toDouble();
      }
    }
    return result;
  }

  List<double>? costValues({int period = 7}) {
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: period - 1));
    final result = List<double>.filled(period, 0);
    for (final e in all) {
      if (e.at.isBefore(start) || e.at.isAfter(now)) continue;
      if (e.cost == null) return null;
      final day = DateTime(
        e.at.year,
        e.at.month,
        e.at.day,
      ).difference(start).inDays;
      if (day >= 0 && day < period) result[day] += e.cost!;
    }
    return result;
  }

  String get status => demo
      ? '演示数据'
      : busy
      ? '正在同步'
      : error != null
      ? '同步待重试'
      : stale
      ? '历史快照'
      : account?.signedIn == true
      ? isClaude
            ? '本地采集'
            : '已同步'
      : all.isNotEmpty
      ? '本机记录'
      : '尚未连接';
  SubscriptionInfo get subscription => demo
      ? const SubscriptionInfo('示例订阅', SubscriptionTone.neutral)
      : SubscriptionInfo.read(account, now);
  String get planName => subscription.label;
  AccountSnapshot? accountForProfile(int index) {
    if (index == selected) return account;
    final cached = store.get('quota:${profiles[index].scope}');
    return cached is Map
        ? AccountSnapshot.fromJson(Map<String, dynamic>.from(cached))
        : null;
  }

  SubscriptionInfo subscriptionForProfile(int index) => index == selected
      ? subscription
      : SubscriptionInfo.read(accountForProfile(index), now);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _load({bool resetAccount = true}) {
    if (demo) {
      account = demoAccount(now, claude: isClaude);
      all = demoEvents(now, claude: isClaude);
    } else {
      if (resetAccount || account == null) {
        accountVerified = false;
        final cached =
            store.get('quota:${profile.scope}') ??
            store.get('local-quota:${profile.scope}');
        account = cached is Map
            ? AccountSnapshot.fromJson(Map<String, dynamic>.from(cached))
            : null;
        if (isClaude && account != null) {
          account = ClaudeConnection.localSnapshot(account!);
        }
        if (!readSubscriptionDates && account != null) {
          account = account!.withSubscriptionDates(null);
        }
      }
      all = store.events(
        profile.scope,
        now.subtract(const Duration(days: 365)),
        prices,
      );
    }
  }

  Future<void> initialize() async {
    await _syncLanguage();
    await _syncAppearance();
    await _syncWindows();
    await refresh();
    var ticks = 0;
    _timer = Timer.periodic(const Duration(seconds: 30), (_) async {
      now = DateTime.now();
      ticks++;
      _notify();
      if (!autoRefresh || demo || busy) return;
      if (ticks % 2 == 0) {
        await refresh(remote: ticks % (refreshMinutes * 2) == 0);
      }
    });
  }

  Future<void> refresh({bool remote = true}) async {
    if (busy) return;
    busy = true;
    if (remote) error = null;
    connectionReport = null;
    if ((remote || isClaude) && quotaEnabled) accountVerified = false;
    now = DateTime.now();
    _notify();
    final root = profile.root;
    final scope = profile.scope;
    try {
      if (demo) {
        account = demoAccount(now, claude: isClaude);
        all = demoEvents(now, claude: isClaude);
      } else {
        if (scanEnabled) {
          final result = isClaude
              ? await scanClaude(store.path, root)
              : await scanCodex(store.path, root);
          lastScan = now;
          if (result.errors > 0) {
            message = '有 ${result.errors} 个记录文件暂未读取，其他统计已保留。';
          }
        }
        _load(resetAccount: false);
        if ((remote || isClaude) && quotaEnabled) {
          if (isClaude) {
            final cli = await ClaudeConnection.locate(claudeExecutable);
            if (cli == null) {
              error = '未找到 Claude Code，可在设置中指定路径。';
            } else {
              final result = await ClaudeConnection.read(
                cli,
                root,
                cachedAccount: account,
                readSubscriptionDates: readSubscriptionDates,
              );
              if (profile.scope == scope) {
                account = result.account;
                accountVerified = true;
                claudeSignedIn = result.authenticated;
                claudeCollectorEnabled = result.collectorEnabled;
                store.set('quota:$scope', account!.toJson());
                if (!claudeSignedIn) {
                  message = 'Claude Code 尚未登录，本机历史已保留。可点击登录连接账号。';
                } else {
                  message = result.notice;
                }
              }
            }
          } else {
            final cli = await CodexRpc.locate(executable);
            if (cli == null) {
              error = '未找到 Codex。可在设置中指定已安装的工具。';
            } else {
              final snapshot = await CodexRpc.read(
                cli,
                root,
                readSubscriptionDates: readSubscriptionDates,
              );
              if (profile.scope == scope) {
                account = snapshot;
                accountVerified = true;
                store.set('quota:$scope', snapshot.toJson());
                if (!snapshot.signedIn) message = '请先在 Codex 中登录，随后刷新额度。';
                if (snapshot.authMode == 'apiKey') {
                  message = 'API Key 模式可统计本机用量，不提供订阅剩余百分比。';
                }
              }
            }
          }
        }
      }
      await _checkAlerts();
    } catch (failure) {
      accountVerified = false;
      error = failure is ClaudeAccountChanged
          ? '读取期间 Claude 账号已变化，请重新读取本地数据。'
          : isClaude
          ? '暂时无法读取 Claude 本机状态，已保留上次数据。请检查工具路径和目录权限。'
          : '暂时无法完成同步，已保留上次数据。请检查 Codex 登录状态与网络。';
    } finally {
      busy = false;
      try {
        await _updateTray();
      } catch (_) {
        /* Tray availability must not affect account state. */
      }
      _notify();
    }
  }

  Future<void> resetQuota() async {
    if (!canResetQuota) return;
    final root = profile.root;
    final email = account!.email!;
    final pendingKey = 'quota-reset:$root:${email.toLowerCase()}';
    final savedKey = store.get(pendingKey);
    final requestKey = savedKey is String && savedKey.isNotEmpty
        ? savedKey
        : newQuotaResetKey();
    // Persist before sending so a retry after a timeout or restart reuses it.
    store.set(pendingKey, requestKey);
    busy = true;
    resettingQuota = true;
    error = null;
    message = null;
    _notify();
    try {
      final cli = await CodexRpc.locate(executable);
      if (cli == null) throw StateError('Codex unavailable');
      final result = await _quotaResetter(cli, root, email, requestKey);
      store.set(pendingKey, null);
      now = DateTime.now();
      accountVerified = result.account != null;
      if (result.account != null) {
        account = result.account;
        store.set('quota:$root', account!.toJson());
      }
      message = switch (result.outcome) {
        QuotaResetOutcome.reset => '额度已重置。',
        QuotaResetOutcome.alreadyRedeemed => '本次额度重置已完成，未重复使用次数。',
        QuotaResetOutcome.nothingToReset => '当前没有可重置的额度窗口，未使用重置次数。',
        QuotaResetOutcome.noCredit => '当前没有可用的额度重置次数。',
      };
      if (result.account == null) message = '$message 额度信息暂未更新，请刷新。';
    } on ResetAccountChanged {
      accountVerified = false;
      error = 'Codex 登录账号已变化，请先刷新确认账号，再重置额度。';
    } catch (_) {
      accountVerified = false;
      error = '尚未确认重置结果，请刷新后重试；同一次操作不会重复使用次数。';
    } finally {
      resettingQuota = false;
      busy = false;
      try {
        await _updateTray();
      } catch (_) {
        /* Tray is optional. */
      }
      _notify();
    }
  }

  Future<void> _updateTray() async {
    await NativeBridge.call('updateTray', {
      'title': strings.text(
        demo
            ? '$providerLabel 演示'
            : quotaValid
            ? '$providerLabel ${activeWindow!.remaining}%'
            : '$providerLabel —',
      ),
      'tooltip': strings.text(
        quotaValid
            ? '当前窗口剩余 ${activeWindow!.remaining}% · ${countdown(activeWindow!.resets, now)}后重置'
            : '${AppInfo.name} · $status',
      ),
    });
  }

  Future<void> _checkAlerts() async {
    if (demo || !notifications || stale || !quotaValid) return;
    for (final entry in [
      MapEntry('当前窗口', account!.primary),
      MapEntry('较长窗口', account!.secondary),
    ]) {
      final w = entry.value;
      if (w == null || w.expired(now) || w.remaining > threshold) continue;
      final key =
          'alert:${profile.scope}:${entry.key}:${w.resets?.millisecondsSinceEpoch}:$threshold';
      if (store.get(key) == true) continue;
      await NativeBridge.call('notify', {
        'id': key,
        'title': strings.text('$providerLabel ${entry.key}额度提醒'),
        'body': strings.text(
          '剩余 ${w.remaining}%，${countdown(w.resets, now)}后重置。',
        ),
      });
      store.set(key, true);
    }
  }

  void navigate(int index) {
    page = index;
    message = null;
    _notify();
  }

  void setDays(int value) {
    days = value;
    _notify();
  }

  Future<void> selectProvider(AiProvider value) async {
    if (busy || provider == value) return;
    _selectedByProvider[provider] = selected;
    connectionReport = null;
    provider = value;
    selected = (_selectedByProvider[value] ?? 0).clamp(0, profiles.length - 1);
    error = null;
    message = null;
    claudeSignedIn = false;
    _load();
    save();
    _notify();
    await refresh();
  }

  Future<void> loginClaude() async {
    if (!isClaude || demo || busy) return;
    busy = true;
    connectingClaude = true;
    _claudeLoginCanceled = false;
    error = null;
    message = null;
    _notify();
    File? command;
    try {
      final cli = await ClaudeConnection.locate(claudeExecutable);
      if (_claudeLoginCanceled || _disposed) return;
      if (cli == null) throw StateError('Claude Code unavailable');
      var auth = await ClaudeConnection.authStatus(cli, profile.root);
      if (auth['loggedIn'] != true && !_claudeLoginCanceled && !_disposed) {
        command = await ClaudeConnection.loginCommand(
          cli,
          profile.root,
          p.dirname(store.path),
        );
        final launched = await NativeBridge.call<bool>('launchClaudeLogin', {
          'path': command.path,
          if (Platform.isWindows)
            'encoded': DesktopPlatform.encodedPowerShell(
              await command.readAsString(),
            ),
        });
        if (launched != true) {
          throw StateError('Official sign-in terminal unavailable');
        }
        for (
          var attempt = 0;
          attempt < 90 && !_claudeLoginCanceled && !_disposed;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(seconds: 2));
          if (_claudeLoginCanceled || _disposed) break;
          auth = await ClaudeConnection.authStatus(cli, profile.root);
          if (auth['loggedIn'] == true) break;
        }
      }
      if (auth['loggedIn'] == true && !_claudeLoginCanceled && !_disposed) {
        final result = await ClaudeConnection.read(
          cli,
          profile.root,
          readSubscriptionDates: readSubscriptionDates,
        );
        if (!_disposed) {
          account = result.account;
          accountVerified = true;
          claudeSignedIn = result.authenticated;
          claudeCollectorEnabled = result.collectorEnabled;
          store.set('quota:${profile.scope}', account!.toJson());
          message = 'Claude Code 登录完成，正在更新账号。';
        }
      } else {
        message = '已停止等待。官方终端中的登录可继续完成，之后刷新即可。';
      }
    } catch (_) {
      error = '无法启动 Claude Code 登录，请在设置中检查工具路径。';
    } finally {
      if (command != null && await command.exists()) await command.delete();
      connectingClaude = false;
      busy = false;
      _notify();
    }
    if (!_disposed) await refresh();
  }

  void cancelClaudeLogin() {
    _claudeLoginCanceled = true;
  }

  Future<void> setClaudeCollector(bool enabled) async {
    if (!isClaude || demo || busy) return;
    busy = true;
    error = null;
    message = null;
    _notify();
    try {
      if (enabled) {
        final cli = await ClaudeConnection.locate(claudeExecutable);
        final helper = await NativeBridge.call<String>('claudeHelperPath');
        if (cli == null || helper == null) {
          throw StateError('Collector unavailable');
        }
        await ClaudeConnection.enableCollector(cli, profile.root, helper);
        message = '额度采集已启用，原状态栏输出会保留。请新开 Claude Code 会话，首个响应后刷新。';
      } else {
        final restored = await ClaudeConnection.disableCollector(profile.root);
        message = restored ? '额度采集已关闭，原状态栏已恢复。' : 'Claude 状态栏已变化，未覆盖当前设置。';
      }
      claudeCollectorEnabled = enabled;
    } catch (_) {
      error = '未能配置额度采集。请先登录 Claude Code，确认配置可写；原设置已保留。';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> selectProfile(int index) async {
    if (busy) return;
    connectionReport = null;
    selected = index;
    _selectedByProvider[provider] = index;
    error = null;
    _load();
    save();
    _notify();
    await refresh();
  }

  Future<void> addProfile() async {
    final root = await NativeBridge.call<String>('chooseDirectory', {
      'provider': providerLabel,
    });
    if (root == null) return;
    final markers = isClaude
        ? ['projects', 'settings.json', '.claude.json']
        : ['sessions', 'archived_sessions', 'auth.json', 'config.toml'];
    var recognized = false;
    for (final marker in markers) {
      if (await FileSystemEntity.type(p.join(root, marker)) !=
          FileSystemEntityType.notFound) {
        recognized = true;
        break;
      }
    }
    if (!recognized) {
      message = '未发现对应配置或会话目录，请选择官方工具使用的配置根目录。';
      _notify();
      return;
    }
    final index = profiles.indexWhere((e) => e.root == root);
    if (index >= 0) {
      await selectProfile(index);
      return;
    }
    _allProfiles.add(
      SourceProfile(root, '账号 ${profiles.length + 1}', provider: provider),
    );
    await selectProfile(profiles.length - 1);
  }

  Future<void> chooseExecutable() async {
    final file = await NativeBridge.call<String>('chooseExecutable', {
      'provider': providerLabel,
    });
    if (file != null) {
      connectionReport = null;
      if (isClaude) {
        claudeExecutable = file;
      } else {
        executable = file;
      }
      save();
      _notify();
    }
  }

  void save() {
    store.set('preferences', {
      'language': language.name,
      'appearance': appearance.name,
      'scanEnabled': scanEnabled,
      'quotaEnabled': quotaEnabled,
      'autoRefresh': autoRefresh,
      'notifications': notifications,
      'readSubscriptionDates': readSubscriptionDates,
      'closeToTray': closeToTray,
      'updateChannel': updateChannel.name,
      'refreshMinutes': refreshMinutes,
      'threshold': threshold,
      'executable': executable,
      'profiles': _allProfiles.map((e) => e.toJson()).toList(),
      'selected': _selectedByProvider[AiProvider.gpt] ?? 0,
      'selectedByProvider': {
        for (final item in AiProvider.values)
          item.name: item == provider
              ? selected
              : _selectedByProvider[item] ?? 0,
      },
      'provider': provider.name,
      'claudeExecutable': claudeExecutable,
      'prices': prices.map((e) => e.toJson()).toList(),
    });
  }

  void setting(void Function() update) {
    update();
    save();
    _notify();
  }

  Future<void> runConnectionChecks() async {
    if (busy || demo || _disposed) return;
    busy = true;
    checkingConnection = true;
    accountVerified = false;
    connectionReport = null;
    _notify();
    try {
      final result = await ConnectionDiagnostics.run(
        profile,
        configured: isClaude ? claudeExecutable : executable,
        onProgress: (steps) {
          if (!_disposed) {
            connectionReport = ConnectionReport(
              profile.scope,
              DateTime.now(),
              steps,
            );
            _notify();
          }
        },
      );
      if (!_disposed && result.scope == profile.scope) {
        connectionReport = result;
      }
    } catch (_) {
      if (!_disposed) message = '检测暂未完成，请稍后重试。';
    } finally {
      busy = false;
      checkingConnection = false;
      _notify();
    }
  }

  Future<void> checkUpdates({
    Future<AppUpdate?> Function(UpdateChannel)? fetch,
  }) async {
    if (checkingUpdates || _disposed) return;
    checkingUpdates = true;
    availableUpdate = null;
    updateMessage = null;
    final channel = updateChannel;
    _notify();
    try {
      final result =
          await (fetch?.call(channel) ?? AppUpdates.check(channel: channel));
      if (!_disposed && channel == updateChannel) {
        availableUpdate = result;
        updateCheckedAt = DateTime.now();
        updateMessage = result == null ? '未发现更高版本。' : '发现可用更新。';
      }
    } catch (failure) {
      if (!_disposed) {
        updateMessage =
            failure is UpdateCheckFailure && failure.code == 'rateLimit'
            ? '更新服务请求较多，请稍后重试。'
            : '无法检查更新，请检查网络或打开版本页面。';
      }
    } finally {
      checkingUpdates = false;
      _notify();
    }
  }

  void setUpdateChannel(UpdateChannel channel) {
    if (checkingUpdates) return;
    updateChannel = channel;
    availableUpdate = null;
    updateMessage = null;
    updateCheckedAt = null;
    save();
    _notify();
  }

  Future<void> _syncWindows() async {
    if (!isWindows) return;
    try {
      final enabled = await NativeBridge.call<bool>('setWindowBehavior', {
        'closeToTray': closeToTray,
      });
      if (closeToTray && enabled != true) closeToTray = false;
      launchAtLogin =
          await NativeBridge.call<bool>('getLaunchAtLogin') ?? false;
    } catch (_) {
      /* Optional system integration must not block startup. */
    }
    _notify();
  }

  Future<void> setCloseToTray(bool enabled) async {
    if (!isWindows || startupBusy) return;
    try {
      final accepted = await NativeBridge.call<bool>('setWindowBehavior', {
        'closeToTray': enabled,
      });
      if (accepted != true) throw StateError('Tray unavailable');
      closeToTray = enabled;
      save();
    } catch (_) {
      message = '系统托盘暂不可用，关闭窗口仍会退出。';
    }
    _notify();
  }

  Future<void> setLaunchAtLogin(bool enabled) async {
    if (!isWindows || startupBusy) return;
    startupBusy = true;
    _notify();
    try {
      final accepted = await NativeBridge.call<bool>('setLaunchAtLogin', {
        'enabled': enabled,
      });
      if (accepted != true) {
        throw StateError('Startup registration unavailable');
      }
      launchAtLogin = enabled;
    } catch (_) {
      message = '未能修改开机启动，请检查系统设置；原设置已保留。';
    } finally {
      startupBusy = false;
      _notify();
    }
  }

  Future<void> setSubscriptionDateReading(bool enabled) async {
    if (busy || demo) return;
    setting(() {
      readSubscriptionDates = enabled;
      if (!enabled && account != null) {
        account = account!.withSubscriptionDates(null);
      }
    });
    if (enabled) await refresh();
  }

  Future<void> _syncLanguage() async {
    try {
      await NativeBridge.call('setLanguage', {'language': language.name});
    } catch (_) {
      // Native menus are optional on platforms without a bridge.
    }
  }

  Future<void> setLanguage(AppLanguage value) async {
    if (language == value) return;
    language = value;
    save();
    _notify();
    await _syncLanguage();
    try {
      await _updateTray();
    } catch (_) {
      /* Tray is optional. */
    }
  }

  Future<void> _syncAppearance() async {
    try {
      await NativeBridge.call('setAppearance', {'appearance': appearance.name});
    } catch (_) {
      /* Native appearance is optional on unsupported platforms. */
    }
  }

  Future<void> setAppearance(AppAppearance value) async {
    if (appearance == value) return;
    appearance = value;
    save();
    _notify();
    await _syncAppearance();
  }

  Future<void> setDemo(bool value) async {
    demo = value;
    error = null;
    message = null;
    _load();
    save();
    _notify();
    await refresh();
  }

  Future<void> setNotifications(bool value) async {
    if (value) {
      final ok = await NativeBridge.call<bool>('requestNotifications');
      notifications = ok == true;
      if (!notifications) message = '通知未开启，可在系统设置中允许额度管家发送通知。';
    } else {
      notifications = false;
    }
    save();
    _notify();
  }

  void addPrice(ModelPrice price) {
    prices.removeWhere((e) => e.model == price.model);
    prices.add(price);
    save();
    _load();
    _notify();
  }

  void removePrice(String model) {
    prices.removeWhere((e) => e.model == model);
    save();
    _load();
    _notify();
  }

  Future<void> clear() async {
    store.clear();
    _load();
    _notify();
  }

  Future<void> export() async {
    String cell(String s) {
      final safe = RegExp(r'^[=+@\-\t\r]').hasMatch(s) ? "'$s" : s;
      return '"${safe.replaceAll('"', '""')}"';
    }

    final lines = <String>[
      strings.text('时间,模型,成本（USD估算）,新增输入,输出,缓存命中,速度（tok/s）,首字（秒）,计时是否估算'),
    ];
    for (final e in events) {
      lines.add(
        [
          cell(e.at.toIso8601String()),
          cell(e.model),
          e.cost?.toStringAsFixed(6) ?? '',
          '${e.freshInput}',
          '${e.tokens.output}',
          '${e.tokens.cached}',
          e.outputTokensPerSecond?.toString() ?? '',
          e.firstTokenSeconds?.toString() ?? '',
          e.outputTokensPerSecond == null && e.firstTokenSeconds == null
              ? ''
              : e.timingEstimated
              ? strings.text('是')
              : strings.text('否'),
        ].join(','),
      );
    }
    final path = await NativeBridge.call<String>('saveCsv', {
      'name': strings.text(
        '$providerLabel-用量统计-${now.year}-${now.month}-${now.day}.csv',
      ),
      'content': '\uFEFF${lines.join('\r\n')}',
    });
    if (path != null) {
      message = '统计已导出。未包含对话内容和凭证。';
      _notify();
    }
  }

  String diagnostics() => const JsonEncoder.withIndent('  ').convert({
    'version': AppInfo.version,
    'platform': Platform.operatingSystem,
    'mode': demo ? 'demo' : 'local',
    'profiles': profiles.length,
    'events': all.length,
    'quotaSource': account?.source,
    'quotaAgeMinutes': account == null
        ? null
        : now.difference(account!.observed).inMinutes,
    'authMode': account?.authMode,
    'scanEnabled': scanEnabled,
    'quotaEnabled': quotaEnabled,
    'lastSyncFailed': error != null,
    if (connectionReport != null && connectionReport!.scope == profile.scope)
      'connectionCheck': connectionReport!.safeSummary,
  });
  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _claudeLoginCanceled = true;
    NativeBridge.channel.setMethodCallHandler(null);
    store.close();
    super.dispose();
  }
}
