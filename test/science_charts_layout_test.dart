import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lanxis/core/models.dart';
import 'package:lanxis/ui/science_charts.dart';

void main() {
  testWidgets('box chart stays bounded when filters include many scenarios', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final items = [
      for (var i = 0; i < 12; i++)
        Measurement(
          id: 'm$i',
          sessionId: 's',
          phaseId: 'p',
          testId: 't',
          trialId: 'r',
          requestId: 'q$i',
          scenarioId: 'E$i',
          clients: 1,
          timestampUtc: DateTime.utc(2026),
          success: true,
          bytesReceived: 1,
          latencyMs: 10 + i.toDouble(),
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ScienceCharts(items: items)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final viewport = find.byKey(const ValueKey('box-chart-viewport'));
    expect(viewport, findsOneWidget);
    expect(tester.getSize(viewport).height, 320);
    expect(tester.takeException(), isNull);
  });
}
