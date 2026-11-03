import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../app_info.dart';

enum UpdateChannel { alpha, stable }

class AppVersion implements Comparable<AppVersion> {
  final List<int> numbers;
  final String? suffix;
  AppVersion(this.numbers, this.suffix);
  static AppVersion? parse(String value) {
    final match = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z][0-9A-Za-z.-]*))?$',
    ).firstMatch(value);
    if (match == null) return null;
    final numbers = [for (var i = 1; i <= 3; i++) int.tryParse(match[i]!)];
    if (numbers.any((n) => n == null)) return null;
    return AppVersion(numbers.cast<int>(), match[4]);
  }

  @override
  int compareTo(AppVersion other) {
    for (var i = 0; i < 3; i++) {
      final diff = numbers[i].compareTo(other.numbers[i]);
      if (diff != 0) return diff;
    }
    if (suffix == other.suffix) return 0;
    if (suffix == null) return 1;
    if (other.suffix == null) return -1;
    final a = suffix!.split('.'), b = other.suffix!.split('.');
    for (var i = 0; i < a.length && i < b.length; i++) {
      final left = int.tryParse(a[i]), right = int.tryParse(b[i]);
      final diff = left != null && right != null
          ? left.compareTo(right)
          : left != null
          ? -1
          : right != null
          ? 1
          : a[i].compareTo(b[i]);
      if (diff != 0) return diff;
    }
    return a.length.compareTo(b.length);
  }
}

class AppUpdate {
  final String tag, notes;
  final Uri page;
  final Uri? download;
  final bool preview;
  const AppUpdate(this.tag, this.notes, this.page, this.download, this.preview);
}

class UpdateCheckFailure implements Exception {
  final String code;
  const UpdateCheckFailure(this.code);
}

class AppUpdates {
  static const repository = 'liuzilong200049-bot/QuotaMate';
  static final releases = Uri.https(
    'api.github.com',
    '/repos/$repository/releases',
    {'per_page': '100'},
  );
  static final page = Uri.https('github.com', '/$repository/releases');

  static bool trusted(Uri value, String prefix) =>
      value.scheme == 'https' &&
      value.host == 'github.com' &&
      !value.hasPort &&
      value.userInfo.isEmpty &&
      !value.hasQuery &&
      !value.hasFragment &&
      value.path.startsWith('/$repository/releases/$prefix');

  static AppUpdate? select(
    dynamic response, {
    required String current,
    required UpdateChannel channel,
    required String platform,
  }) {
    if (response is! List) throw const UpdateCheckFailure('format');
    final installed = AppVersion.parse(current);
    if (installed == null) throw const UpdateCheckFailure('format');
    final matches = <(AppVersion, AppUpdate)>[];
    for (final raw in response) {
      if (raw is! Map ||
          raw['draft'] != false ||
          raw['prerelease'] is! bool ||
          raw['tag_name'] is! String) {
        continue;
      }
      if (channel == UpdateChannel.stable && raw['prerelease'] == true) {
        continue;
      }
      final tag = raw['tag_name'] as String;
      final version = AppVersion.parse(tag);
      if (version == null || version.compareTo(installed) <= 0) continue;
      if (channel == UpdateChannel.stable && version.suffix != null) continue;
      final url = Uri.tryParse(raw['html_url']?.toString() ?? '');
      if (url == null ||
          !trusted(url, 'tag/') ||
          url.path != '/$repository/releases/tag/$tag') {
        continue;
      }
      Uri? download;
      final base = version.numbers.join('.');
      final name = switch (platform) {
        'windows' => 'QuotaMate-$base-windows-x64-setup.exe',
        'macos' => 'QuotaMate-$base-macos-universal.dmg',
        _ => '',
      };
      for (final asset
          in (raw['assets'] is List ? raw['assets'] as List : const [])) {
        if (asset is! Map ||
            asset['name'] != name ||
            asset['state'] != 'uploaded') {
          continue;
        }
        final uri = Uri.tryParse(
          asset['browser_download_url']?.toString() ?? '',
        );
        if (uri != null &&
            trusted(uri, 'download/') &&
            uri.path == '/$repository/releases/download/$tag/$name') {
          download = uri;
        }
      }
      final notes = raw['body'] is String ? raw['body'] as String : '';
      matches.add((
        version,
        AppUpdate(
          tag,
          notes.length > 16000 ? notes.substring(0, 16000) : notes,
          url,
          download,
          raw['prerelease'] == true,
        ),
      ));
    }
    matches.sort((a, b) => b.$1.compareTo(a.$1));
    return matches.firstOrNull?.$2;
  }

  static Future<AppUpdate?> check({
    required UpdateChannel channel,
    String? current,
    String? platform,
    HttpClient? client,
  }) async {
    final http = client ?? HttpClient();
    try {
      http.connectionTimeout = const Duration(seconds: 10);
      final request = await http
          .getUrl(releases)
          .timeout(const Duration(seconds: 10));
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'QuotaMate/${AppInfo.version}',
      );
      request.headers.set('X-GitHub-Api-Version', '2026-03-10');
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode == 403 || response.statusCode == 429) {
        throw const UpdateCheckFailure('rateLimit');
      }
      if (response.statusCode != 200) throw const UpdateCheckFailure('network');
      final bytes = await response
          .fold<List<int>>(<int>[], (bytes, chunk) {
            if (bytes.length + chunk.length > 2 * 1024 * 1024) {
              throw const UpdateCheckFailure('format');
            }
            bytes.addAll(chunk);
            return bytes;
          })
          .timeout(const Duration(seconds: 15));
      return select(
        jsonDecode(utf8.decode(bytes)),
        current: current ?? '${AppInfo.version}-alpha',
        channel: channel,
        platform: platform ?? Platform.operatingSystem,
      );
    } on UpdateCheckFailure {
      rethrow;
    } on FormatException {
      throw const UpdateCheckFailure('format');
    } catch (_) {
      throw const UpdateCheckFailure('network');
    } finally {
      http.close(force: true);
    }
  }
}
