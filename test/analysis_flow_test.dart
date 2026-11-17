import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lanxis/core/models.dart';
import 'package:lanxis/data/lab_repository.dart';
import 'package:lanxis/ui/distribution_explorer.dart';
import 'package:lanxis/ui/science_charts.dart';
import 'package:lanxis/ui/screens.dart';

void main() {
  testWidgets('failure-only selection has no empty grey charts', (
    tester,
  ) async {
    final repo = LabRepository.inMemory();
    addTearDown(repo.dispose);
    final session = repo.createSession('Sin respuestas');
    final phase = repo.createPhase(session.id, 'Fase');
    final testId = repo.createTest(
      phase.id,
      'E1',
      const TrialConfig(
        scenarioId: 'E1',
        clients: 1,
        distanceM: null,
        count: 1,
      ),
    );
    final trialId = repo.startTrial(testId);
    repo.addMeasurement(
      Measurement(
        id: 'm',
        sessionId: session.id,
        phaseId: phase.id,
        testId: testId,
        trialId: trialId,
        requestId: 'r',
        scenarioId: 'E1',
        clients: 1,
        timestampUtc: DateTime.utc(2026),
        success: false,
        bytesReceived: 0,
        error: 'timeout',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AnalysisScreen(repository: repo, revision: 0)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Sin RTT válido para dibujar la distribución.'),
      findsOneWidget,
    );
    expect(find.byType(BarChart), findsNothing);
    expect(find.byType(ScienceCharts), findsNothing);
    expect(find.byType(DistributionExplorer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two sessions can be selected for a pooled comparison', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = LabRepository.inMemory();
    addTearDown(repo.dispose);
    for (var index = 0; index < 2; index++) {
      final session = repo.createSession('Sesión ${index + 1}');
      final phase = repo.createPhase(session.id, 'Fase');
      final testId = repo.createTest(
        phase.id,
        'E1',
        const TrialConfig(scenarioId: 'E1', clients: 1, count: 1),
      );
      final trialId = repo.startTrial(testId);
      repo.addMeasurement(
        Measurement(
          id: 'm$index',
          sessionId: session.id,
          phaseId: phase.id,
          testId: testId,
          trialId: trialId,
          requestId: 'r$index',
          scenarioId: 'E1',
          clients: 1,
          timestampUtc: DateTime.utc(2026),
          success: true,
          bytesReceived: 0,
          latencyMs: 10 + index * 10,
        ),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AnalysisScreen(repository: repo, revision: 0)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comparar sesiones'));
    await tester.pumpAndSettle();
    final choices = find.byType(CheckboxListTile);
    expect(choices, findsNWidgets(2));
    await tester.tap(choices.at(0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -240));
    await tester.pumpAndSettle();
    await tester.tap(choices.at(1));
    await tester.pumpAndSettle();
    expect(
      find.text('2 seleccionadas · resultados descriptivos'),
      findsOneWidget,
    );
    expect(find.textContaining('media conjunta 15.00 ms'), findsOneWidget);
    expect(find.text('Comparación PDF'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
