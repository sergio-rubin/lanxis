import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/core/models.dart';
import 'package:lanxis/core/scenario_planner.dart';
import 'package:lanxis/data/lab_repository.dart';

void main() {
  test('reference plan adapts to ready participants and environment', () {
    final plan = ScenarioPlanner.reference(
      scenarioId: 'E6',
      environment: 'outdoor',
      load: 'throughput',
      readyClients: 5,
    );
    expect(plan.config.clients, 5);
    expect(plan.config.targetDistanceM, 12);
    expect(plan.config.distanceM, isNull);
    expect(plan.config.payloadBytes, 65536);
    expect(plan.config.intervalMs, 1250);
    expect(plan.config.timeoutMs, 7000);
    expect(plan.config.warmup, 5);
    expect(plan.totalSamples, 500);
    expect(plan.enoughParticipants, true);
    final waiting = ScenarioPlanner.reference(
      scenarioId: 'E4',
      environment: 'indoor',
      load: 'balanced',
      readyClients: 2,
    );
    expect(waiting.config.clients, 4);
    expect(waiting.enoughParticipants, false);
  });

  test(
    'custom scenario and missing real distance persist without a made-up value',
    () {
      final repo = LabRepository.inMemory();
      addTearDown(repo.dispose);
      final template = repo.saveScenarioTemplate(
        'Patio · TCP',
        const TrialConfig(
          scenarioId: 'Libre',
          clients: 3,
          count: 12,
          environment: 'outdoor',
          protocol: 'tcp',
          payloadBytes: 4096,
        ),
        autoClients: true,
      );
      final loaded = repo.scenarioTemplates().single;
      expect(loaded.id, template.id);
      expect(loaded.config.payloadBytes, 4096);
      expect(loaded.config.environment, 'outdoor');
      expect(loaded.autoClients, true);
      final session = repo.createSession('Prueba');
      final phase = repo.createPhase(session.id, 'Fase inicial');
      final testId = repo.createTest(
        phase.id,
        'E1',
        const TrialConfig(
          scenarioId: 'E1',
          clients: 1,
          count: 1,
          targetDistanceM: 1,
        ),
      );
      final trialId = repo.startTrial(testId);
      repo.addMeasurement(
        Measurement(
          id: 'm1',
          sessionId: session.id,
          phaseId: phase.id,
          testId: testId,
          trialId: trialId,
          requestId: 'r1',
          scenarioId: 'E1',
          clients: 1,
          targetDistanceM: 1,
          distanceSource: 'unknown',
          timestampUtc: DateTime.now().toUtc(),
          success: true,
          bytesReceived: 1,
          latencyMs: 9,
        ),
      );
      final item = repo.measurements(session.id).single;
      expect(item.distanceM, isNull);
      expect(item.targetDistanceM, 1);
      expect(item.distanceSource, 'unknown');
    },
  );
}
