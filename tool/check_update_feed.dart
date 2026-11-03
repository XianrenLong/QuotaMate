// Explicit developer smoke check: public GitHub feed only, no client accounts.
import 'dart:convert';
import 'dart:io';

import 'package:quota_mate/data/app_updates.dart';

Future<void> main() async {
  final update = await AppUpdates.check(channel: UpdateChannel.alpha);
  stdout.writeln(
    jsonEncode({'feedReachable': true, 'newerRelease': update?.tag}),
  );
}
