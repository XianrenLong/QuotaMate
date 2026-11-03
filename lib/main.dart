import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'controller.dart';
import 'data/store.dart';
import 'data/desktop_platform.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final entry in {
      'QuotaMate': 'LICENSE',
      'CC Switch (timing reference)': 'docs/cc-switch-LICENSE.txt',
      'Lucide / Feather': 'docs/licenses/lucide.txt',
      'SQLite engine (Windows)': 'docs/licenses/sqlite-engine.txt',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString(entry.value));
    }
  });
  final directory = Directory(DesktopPlatform().supportDirectory);
  await directory.create(recursive: true);
  await DesktopPlatform.protectDirectory(directory);
  final store = LocalStore(p.join(directory.path, 'usage.sqlite3'));
  final controller = AppController(
    store,
    forceDemo: const bool.fromEnvironment('QUOTA_DEMO'),
  );
  runApp(QuotaMateApp(controller: controller));
  await controller.initialize();
}
