import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quota_mate/controller.dart';
import 'package:quota_mate/data/models.dart';
import 'package:quota_mate/data/native_bridge.dart';
import 'package:quota_mate/data/store.dart';
import 'package:quota_mate/ui/app.dart';
import 'package:quota_mate/ui/usage_details_table.dart';

void main() {
  testWidgets(
    'project, model and chart day filter all records and both CSV buttons',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 720);
      final dir = Directory.systemTemp.createTempSync('project-usage-');
      final c = AppController(LocalStore('${dir.path}/test.db'));
      String? csv;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(NativeBridge.channel, (call) async {
        if (call.method == 'saveCsv') csv = call.arguments['content'];
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(NativeBridge.channel, null);
        c.dispose();
        dir.deleteSync(recursive: true);
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      c.now = DateTime(2030, 3, 1, 12);
      UsageEvent record(int i, String project, String model, int day) =>
          UsageEvent(
            id: '$i',
            session: 's',
            project: project,
            model: model,
            at: DateTime(2030, 3, day, 0, i),
            tokens: Tokens(i + 1, 0, 1),
          );
      c.all = [
        for (var i = 0; i < 103; i++) record(i, '/one/App', 'model-A', 0),
        record(103, '/one/App', 'model-B', 0),
        record(104, '/one/App', 'model-A', 1),
        record(105, '/two/App', 'model-A', 0),
        record(106, '/one/App', 'model-A', -9),
      ];
      await tester.pumpWidget(QuotaMateApp(controller: c));
      Future<void> tap(Finder f) async {
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      List<UsageEvent> rows() => tester
          .widget<UsageDetailsTable>(find.byType(UsageDetailsTable))
          .events;
      await tap(find.text('近7天'));
      await tap(find.text('项目用量 2'));
      await tap(find.text('App').first);
      expect(rows(), hasLength(105));
      expect(rows().every((e) => e.project == '/one/App'), isTrue);
      await tap(find.text('全部模型'));
      await tap(
        find.widgetWithText(CheckedPopupMenuItem<({String? model})>, 'model-A'),
      );
      expect(rows(), hasLength(104));
      final chart = tester.getRect(find.byType(LineChart));
      // Left axis takes 40 logical pixels. Select yesterday, index 28 of 30.
      await tester.tapAt(
        Offset(chart.left + 40 + (chart.width - 40) * 28 / 29, chart.center.dy),
      );
      await tester.pumpAndSettle();
      expect(c.historicalDay, DateTime(2030, 2, 28));
      expect(rows(), hasLength(103));
      for (final button in [find.text('导出'), find.byTooltip('导出统计')]) {
        await tap(button);
        final data = csv!.split('\r\n').skip(1).toList();
        expect(data, hasLength(rows().length));
        expect(
          data.map((line) => line.split(',').first),
          rows().map((e) => '"${e.at.toIso8601String()}"'),
        );
      }
      await tap(find.byTooltip('清除日期筛选'));
      expect(rows(), hasLength(104));
      c.navigate(1);
      expect(c.usageProject, isNull);
      expect(c.usageModel, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
