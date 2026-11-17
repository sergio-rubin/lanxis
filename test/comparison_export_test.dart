import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/core/models.dart';
import 'package:lanxis/data/lab_repository.dart';
import 'package:lanxis/export/comparison_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('comparison export preserves both sessions and raw evidence', () async {
    final repo = LabRepository.inMemory();
    addTearDown(repo.dispose);
    final first = repo.createSession('Base, <LAN>');
    final second = repo.createSession('Carga alta');
    void add(String id, String sessionId, double? latency) {
      final phase = repo.createPhase(sessionId, 'Fase $id');
      final testId = repo.createTest(
        phase.id,
        'E1',
        const TrialConfig(scenarioId: 'E1', clients: 1, count: 1),
      );
      final trialId = repo.startTrial(testId);
      repo.addMeasurement(
        Measurement(
          id: id,
          sessionId: sessionId,
          phaseId: phase.id,
          testId: testId,
          trialId: trialId,
          requestId: 'request-$id',
          scenarioId: 'E1',
          clients: 1,
          timestampUtc: DateTime.utc(2026, 11, 17),
          success: latency != null,
          bytesReceived: 0,
          latencyMs: latency,
          clientId: 'device-$id',
        ),
      );
    }

    add('a', first.id, 10);
    add('b', second.id, 20);
    add('c', second.id, 30);
    add('d', second.id, null);
    final ids = [first.id, second.id];
    final service = ComparisonExportService(repo);
    final data = jsonDecode(service.json(ids)) as Map;
    final comparison = data['comparison'] as Map;
    expect((comparison['pooled'] as Map)['mean_latency_ms'], 20);
    expect((comparison['pooled'] as Map)['n_total'], 4);
    expect((data['source_sessions'] as List), hasLength(2));
    expect(
      ((data['source_sessions'] as List)[1] as Map)['measurements'],
      hasLength(3),
    );
    expect(service.csv(ids).split('\n'), hasLength(5));
    expect(service.html(ids), contains('Base, &lt;LAN&gt;'));
    final pdf = await service.pdf(ids);
    expect(pdf.take(4), [37, 80, 68, 70]);
    final archive = ZipDecoder().decodeBytes(await service.zip(ids));
    final manifest = jsonDecode(
      utf8.decode(archive.findFile('manifest.json')!.content),
    ) as Map;
    for (final entry in (manifest['files'] as Map).entries) {
      final file = archive.findFile(entry.key as String);
      expect(file, isNotNull);
      expect(
        sha256.convert(file!.content).toString(),
        (entry.value as Map)['sha256'],
      );
    }
    expect(archive.findFile('sesiones/2/session.json'), isNotNull);
  });

  test(
    'comparison PDF handles zero RTT and a session without samples',
    () async {
      final repo = LabRepository.inMemory();
      addTearDown(repo.dispose);
      final empty = repo.createSession('Sin datos');
      final zero = repo.createSession('RTT cero');
      final phase = repo.createPhase(zero.id, 'Fase');
      final testId = repo.createTest(
        phase.id,
        'E1',
        const TrialConfig(scenarioId: 'E1', clients: 1, count: 1),
      );
      final trialId = repo.startTrial(testId);
      repo.addMeasurement(
        Measurement(
          id: 'zero',
          sessionId: zero.id,
          phaseId: phase.id,
          testId: testId,
          trialId: trialId,
          requestId: 'r-zero',
          scenarioId: 'E1',
          clients: 1,
          timestampUtc: DateTime.utc(2026),
          success: true,
          bytesReceived: 0,
          latencyMs: 0,
        ),
      );
      final service = ComparisonExportService(repo);
      expect((await service.pdf([empty.id, zero.id])).take(4), [
        37,
        80,
        68,
        70,
      ]);
      expect(service.compare([empty.id, zero.id]).pooled.stats.mean, 0);
    },
  );
}
