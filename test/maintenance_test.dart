import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quota_mate/controller.dart';
import 'package:quota_mate/data/app_updates.dart';
import 'package:quota_mate/data/connection_diagnostics.dart';
import 'package:quota_mate/data/claude_connection.dart';
import 'package:quota_mate/data/models.dart';
import 'package:quota_mate/data/native_bridge.dart';
import 'package:quota_mate/data/provider.dart';
import 'package:quota_mate/data/store.dart';
import 'package:quota_mate/l10n/strings.dart';
import 'package:quota_mate/ui/app.dart';

class _Headers implements HttpHeaders {
  final values = <String, Object>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  @override
  final int statusCode;
  final List<List<int>> chunks;
  _Response(this.statusCode, this.chunks);
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.fromIterable(chunks).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  @override
  final _Headers headers = _Headers();
  @override
  bool followRedirects = true;
  final _Response response;
  _Request(this.response);
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  @override
  Duration? connectionTimeout;
  bool closed = false;
  Uri? url;
  final _Request request;
  _Client(int status, List<List<int>> chunks)
    : request = _Request(_Response(status, chunks));
  @override
  Future<HttpClientRequest> getUrl(Uri value) async {
    url = value;
    return request;
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic> release(
    String tag, {
    bool preview = true,
    String platform = 'windows',
  }) {
    final version = tag.substring(1).split('-').first;
    final name = platform == 'windows'
        ? 'QuotaMate-$version-windows-x64-setup.exe'
        : 'QuotaMate-$version-macos-universal.dmg';
    return {
      'tag_name': tag,
      'draft': false,
      'prerelease': preview,
      'html_url':
          'https://github.com/${AppUpdates.repository}/releases/tag/$tag',
      'published_at': '2026-11-01T00:00:00Z',
      'body': 'Synthetic notes',
      'assets': [
        {
          'name': name,
          'state': 'uploaded',
          'browser_download_url':
              'https://github.com/${AppUpdates.repository}/releases/download/$tag/$name',
        },
      ],
    };
  }

  test('update channels order versions and reject draft, foreign or malformed releases', () {
    final list = [
      release('v0.1.30-alpha'),
      release('v0.1.29', preview: false),
      release('v0.1.31-alpha')..['draft'] = true,
      release('v0.1.99-alpha')..['html_url'] = 'https://example.com/redirect',
    ];
    expect(
      AppUpdates.select(
        list,
        current: '0.1.26-alpha',
        channel: UpdateChannel.alpha,
        platform: 'windows',
      )?.tag,
      'v0.1.30-alpha',
    );
    expect(
      AppUpdates.select(
        list,
        current: '0.1.26-alpha',
        channel: UpdateChannel.stable,
        platform: 'windows',
      )?.tag,
      'v0.1.29',
    );
    final update = AppUpdates.select(
      [release('v0.1.26', preview: false)],
      current: '0.1.26-alpha',
      channel: UpdateChannel.alpha,
      platform: 'windows',
    );
    expect(update?.tag, 'v0.1.26');
    expect(
      AppUpdates.select(
        [release('v0.1.25-alpha')],
        current: '0.1.26-alpha',
        channel: UpdateChannel.alpha,
        platform: 'windows',
      ),
      isNull,
    );
    expect(
      AppVersion.parse('0.1.30-alpha.10')!
          .compareTo(AppVersion.parse('0.1.30-alpha.2')!),
      greaterThan(0),
    );
    expect(AppVersion.parse('v1.0.0;download'), isNull);
  });
  test('update links bind the exact repository, version and OS installer', () {
    final raw = release('v0.1.30-alpha');
    (raw['assets'] as List).first['browser_download_url'] = 'https://github.com/another/project/releases/download/v0.1.30-alpha/untrusted.exe';
    expect(
      AppUpdates.select(
        [raw],
        current: '0.1.26-alpha',
        channel: UpdateChannel.alpha,
        platform: 'windows',
      )!.download,
      isNull,
    );
    final mac = release('v0.1.30-alpha', platform: 'macos');
    expect(
      AppUpdates.select(
        [mac],
        current: '0.1.26-alpha',
        channel: UpdateChannel.alpha,
        platform: 'windows',
      )!.download,
      isNull,
    );
    expect(
      AppUpdates.select(
        [mac],
        current: '0.1.26-alpha',
        channel: UpdateChannel.alpha,
        platform: 'macos',
      )!.download?.path,
      endsWith('-macos-universal.dmg'),
    );
  });
  test(
    'update transport is anonymous, bounded, no-redirect and always closed',
    () async {
      final client = _Client(200, [
        utf8.encode(jsonEncode([release('v0.1.30-alpha')])),
      ]);
      final result = await AppUpdates.check(
        channel: UpdateChannel.alpha,
        current: '0.1.26-alpha',
        platform: 'windows',
        client: client,
      );
      expect(result?.tag, 'v0.1.30-alpha');
      expect(client.url?.host, 'api.github.com');
      expect(client.request.followRedirects, false);
      expect(
        client.request.headers.values.keys.map((s) => s.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(client.closed, true);
      for (final status in [302, 403, 429, 500]) {
        final failed = _Client(status, []);
        await expectLater(
          AppUpdates.check(channel: UpdateChannel.alpha, client: failed),
          throwsA(isA<UpdateCheckFailure>()),
        );
        expect(failed.closed, true);
      }
      final oversized = _Client(200, [List.filled(2 * 1024 * 1024 + 1, 32)]);
      await expectLater(
        AppUpdates.check(channel: UpdateChannel.alpha, client: oversized),
        throwsA(isA<UpdateCheckFailure>()),
      );
      expect(oversized.closed, true);
    },
  );
  test(
    'connection checks identify missing prerequisites without running a CLI',
    () async {
      final dir = Directory.systemTemp.createTempSync('quota-health-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final profile = SourceProfile(p.join(dir.path, 'missing'), 'sample');
      var calls = 0;
      final report = await ConnectionDiagnostics.run(
        profile,
        locate: () async => null,
        identity: (_, _) async {
          calls++;
          throw StateError('must not launch');
        },
      );
      expect(calls, 0);
      expect(
        report.checks.firstWhere((v) => v.id == 'tool').state,
        CheckState.failed,
      );
      expect(
        report.checks.firstWhere((v) => v.id == 'directory').state,
        CheckState.failed,
      );
      expect(
        report.checks.firstWhere((v) => v.id == 'account').state,
        CheckState.skipped,
      );
    },
  );
  test('connection checks distinguish working sign-in from failed quota and redact diagnostics', () async {
    final dir = Directory.systemTemp.createTempSync('quota-health-');
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory(p.join(dir.path, 'sessions')).createSync();
    File(p.join(dir.path, 'sessions', 'sample.jsonl'))
        .writeAsStringSync('synthetic\n');
    final profile = SourceProfile(dir.path, 'sample');
    final report = await ConnectionDiagnostics.run(
      profile,
      locate: () async => '/synthetic/official',
      identity: (_, _) async => AccountSnapshot(
        observed: DateTime.now(),
        email: 'private@example.com',
        authMode: 'chatgpt',
      ),
      quota: (_, _) async => throw StateError('PRIVATE_RAW_OUTPUT'),
    );
    expect(
      report.checks.firstWhere((v) => v.id == 'records').state,
      CheckState.passed,
    );
    expect(
      report.checks.firstWhere((v) => v.id == 'account').state,
      CheckState.passed,
    );
    expect(
      report.checks.firstWhere((v) => v.id == 'quota').state,
      CheckState.failed,
    );
    final c = AppController(LocalStore(p.join(dir.path, 'test.db')));
    addTearDown(c.dispose);
    c.connectionReport = ConnectionReport(
      c.profile.scope,
      report.checkedAt,
      report.checks,
      email: report.email,
      executable: report.executable,
    );
    final safe = c.diagnostics();
    expect(safe, isNot(contains('private@example.com')));
    expect(safe, isNot(contains(dir.path)));
    expect(safe, isNot(contains('/synthetic/official')));
    expect(safe, isNot(contains('PRIVATE_RAW_OUTPUT')));
    expect(safe, contains('connectionCheck'));
  });
  test('Claude checks only use the local connection and reject expired historical samples', () async {
    final dir = Directory.systemTemp.createTempSync('quota-health-claude-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final report = await ConnectionDiagnostics.run(
      SourceProfile(dir.path, 'sample', provider: AiProvider.claude),
      locate: () async => '/synthetic/claude',
      identity: (_, _) async => throw StateError('No Codex request allowed'),
      claude: (_, _) async => ClaudeConnectionResult(
        AccountSnapshot(
          authMode: 'claude',
          observed: DateTime.now().subtract(const Duration(days: 3)),
          primary: const QuotaWindow(25, 300, null),
        ),
        true,
        false,
      ),
    );
    expect(
      report.checks.firstWhere((v) => v.id == 'quota').state,
      CheckState.warning,
    );
    expect(
      report.checks.firstWhere((v) => v.id == 'collector').action,
      CheckAction.collector,
    );
  });
  test(
    'update preference persists; checking never starts until requested',
    () async {
      final dir = Directory.systemTemp.createTempSync('quota-update-prefs-');
      addTearDown(() => dir.deleteSync(recursive: true));
      var c = AppController(LocalStore(p.join(dir.path, 'test.db')));
      expect(c.updateCheckedAt, isNull);
      expect(c.availableUpdate, isNull);
      expect(c.launchAtLogin, false);
      c.setUpdateChannel(UpdateChannel.stable);
      c.dispose();
      c = AppController(LocalStore(p.join(dir.path, 'test.db')));
      addTearDown(c.dispose);
      expect(c.updateChannel, UpdateChannel.stable);
      var requested = 0;
      await c.checkUpdates(
        fetch: (channel) async {
          requested++;
          expect(channel, UpdateChannel.stable);
          return null;
        },
      );
      expect(requested, 1);
      expect(c.updateCheckedAt, isNotNull);
      expect(c.updateMessage, '未发现更高版本。');
    },
  );
  testWidgets(
    'maintenance panels show translated synthetic results at compact widths',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('quota-maintenance-ui-');
      final c = AppController(LocalStore(p.join(dir.path, 'test.db')));
      addTearDown(() {
        c.dispose();
        dir.deleteSync(recursive: true);
      });
      tester.view.physicalSize = const Size(1000, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      c.connectionReport = ConnectionReport(
        c.profile.scope,
        DateTime(2026, 11, 3),
        const [
          ConnectionCheck(
            'tool',
            '客户端工具',
            '已找到工具文件。',
            CheckState.passed,
            CheckAction.executable,
          ),
        ],
      );
      await c.checkUpdates(
        fetch: (_) async => AppUpdate(
          'v0.1.30-alpha',
          'Synthetic notes',
          Uri.parse(
            'https://github.com/${AppUpdates.repository}/releases/tag/v0.1.30-alpha',
          ),
          null,
          true,
        ),
      );
      for (final language in AppLanguage.values) {
        c.language = language;
        await tester.pumpWidget(QuotaMateApp(controller: c));
        await tester.pumpAndSettle();
        c.navigate(4);
        await tester.pumpAndSettle();
        expect(
          find.text(language == AppLanguage.en ? 'Connection checks' : '连接诊断'),
          findsOneWidget,
        );
        expect(
          find.text(language == AppLanguage.en ? 'Software updates' : '软件更新'),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.text(language == AppLanguage.en ? 'Release notes' : '更新说明'),
        );
        await tester.tap(
          find.text(language == AppLanguage.en ? 'Release notes' : '更新说明'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Synthetic notes'), findsOneWidget);
        await tester.tap(
          find.text(language == AppLanguage.en ? 'Close' : '关闭'),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('Windows behavior calls require explicit opt in and preserve state on failure', () async {
    final dir = Directory.systemTemp.createTempSync('quota-windows-prefs-');
    final c = AppController(LocalStore(p.join(dir.path, 'test.db')));
    final calls = <MethodCall>[];
    var accepted = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeBridge.channel, (call) async {
          calls.add(call);
          return accepted;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeBridge.channel, null);
      c.dispose();
      dir.deleteSync(recursive: true);
    });
    expect(c.closeToTray, false);
    expect(c.launchAtLogin, false);
    expect(calls, isEmpty);
    await c.setCloseToTray(true);
    expect(c.closeToTray, true);
    await c.setLaunchAtLogin(true);
    expect(c.launchAtLogin, true);
    accepted = false;
    await c.setLaunchAtLogin(false);
    expect(c.launchAtLogin, true);
    expect(calls.map((v) => v.method), [
      'setWindowBehavior',
      'setLaunchAtLogin',
      'setLaunchAtLogin',
    ]);
  }, skip: !Platform.isWindows);
  test(
    'configuration-only roots can be selected before any log exists',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'quota-config-root-',
      );
      final root = p.join(directory.path, 'official-profile');
      Directory(root).createSync();
      File(p.join(root, 'config.toml'))
          .writeAsStringSync('# Synthetic official configuration');
      final store = LocalStore(p.join(directory.path, 'test.db'));
      store.set('preferences', {'scanEnabled': false, 'quotaEnabled': false});
      final c = AppController(store);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            NativeBridge.channel,
            (call) async => call.method == 'chooseDirectory' ? root : null,
          );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeBridge.channel, null);
        c.dispose();
        directory.deleteSync(recursive: true);
      });
      await c.addProfile();
      expect(c.profile.root, root);
      expect(c.all, isEmpty);
      expect(c.error, isNull);
    },
  );
  test('account changes during checks clear the displayed identity', () async {
    final directory = Directory.systemTemp.createTempSync(
      'quota-identity-check-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final report = await ConnectionDiagnostics.run(
      SourceProfile(directory.path, 'sample'),
      locate: () async => '/synthetic/tool',
      identity: (_, _) async => AccountSnapshot(
        observed: DateTime.now(),
        authMode: 'chatgpt',
        email: 'one@example.com',
      ),
      quota: (_, _) async => AccountSnapshot(
        observed: DateTime.now(),
        authMode: 'chatgpt',
        email: 'two@example.com',
      ),
    );
    expect(report.email, isNull);
    expect(
      report.checks.firstWhere((c) => c.id == 'account').state,
      CheckState.warning,
    );
  });
}
