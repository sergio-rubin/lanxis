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
}
