import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/core/models.dart';
import 'package:lanxis/data/lab_repository.dart';
import 'package:lanxis/export/export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'exports preserve hierarchy and include verifiable bundle hashes',
    () async {
      final repo = LabRepository.inMemory();
      addTearDown(repo.dispose);
      final session = repo.createSession('Estudio <LAN>');
      final phase = repo.createPhase(session.id, 'Fase 1');
      final service = ExportService(repo);
      final jsonData = jsonDecode(service.json(session.id)) as Map;
      expect((jsonData['phases'] as List).single['id'], phase.id);
      expect(jsonData['tests'], isEmpty);
      expect(jsonData['trials'], isEmpty);
      expect(jsonData['events'], isNotEmpty);
      expect(service.html(session.id), contains('Estudio &lt;LAN&gt;'));
      final lines = service.jsonl(session.id).trim().split('\n');
      expect((jsonDecode(lines.first) as Map)['type'], 'manifest');

      final archive = ZipDecoder().decodeBytes(
        await service.zip(session.id),
        verify: true,
      );
      final manifest = jsonDecode(
        utf8.decode(archive.findFile('manifest.json')!.content),
      ) as Map;
      final files = manifest['files'] as Map;
      for (final name in files.keys.cast<String>()) {
        final bytes = archive.findFile(name)!.content;
        expect(
          sha256.convert(bytes).toString(),
          (files[name] as Map)['sha256'],
        );
      }
      final workbook = ZipDecoder().decodeBytes(
        service.xlsx(session.id),
        verify: true,
      );
      expect(workbook.findFile('xl/workbook.xml'), isNotNull);
      for (var i = 1; i <= 4; i++) {
        expect(workbook.findFile('xl/worksheets/sheet$i.xml'), isNotNull);
      }
    },
  );

  test('PDF report is generated entirely offline', () async {
    final repo = LabRepository.inMemory();
    addTearDown(repo.dispose);
    final session = repo.createSession('Estudio local');
    final bytes = await ExportService(repo).pdf(session.id);
    expect(utf8.decode(bytes.take(4).toList()), '%PDF');
    expect(bytes.length, greaterThan(1000));
  });

  test('phase export contains only its measurements and metadata', () async {
    final repo = LabRepository.inMemory();
    addTearDown(repo.dispose);
    final session = repo.createSession('Dos fases');
    for (var i = 0; i < 2; i++) {
      final phase = repo.createPhase(session.id, 'Fase $i');
      final testId = repo.createTest(
        phase.id,
        'E1',
        const TrialConfig(scenarioId: 'E1', clients: 1, distanceM: 1, count: 1),
      );
      final trialId = repo.startTrial(testId);
      repo.addMeasurement(
        Measurement(
          id: 'm$i',
          sessionId: session.id,
          phaseId: phase.id,
          testId: testId,
          trialId: trialId,
          requestId: 'r$i',
          scenarioId: 'E1',
          clients: 1,
          distanceM: 1,
          timestampUtc: DateTime.utc(2026),
          success: true,
          bytesReceived: 100,
          latencyMs: 10 + i.toDouble(),
        ),
      );
    }
    final firstPhase = repo.phases(session.id).first;
    final scope = ExportScope(phaseId: firstPhase.id);
    final service = ExportService(repo);
    final data = jsonDecode(service.json(session.id, scope: scope)) as Map;
    expect((data['phases'] as List).length, 1);
    expect((data['tests'] as List).length, 1);
    expect((data['measurements'] as List).length, 1);
    expect(service.csv(session.id, scope: scope).trim().split('\n').length, 2);
    final bundle = ZipDecoder().decodeBytes(
      await service.zip(session.id, scope: scope),
    );
    final manifest = jsonDecode(
      utf8.decode(bundle.findFile('manifest.json')!.content),
    ) as Map;
    expect((manifest['scope'] as Map)['phase_id'], firstPhase.id);
    final trialId = repo.trialsForSession(session.id).first['id'] as String;
    final trialData = jsonDecode(
      service.json(session.id, scope: ExportScope(trialId: trialId)),
    ) as Map;
    expect((trialData['phases'] as List).length, 1);
    expect((trialData['tests'] as List).length, 1);
    expect((trialData['trials'] as List).length, 1);
    expect((trialData['measurements'] as List).length, 1);
  });

  test(
    'general and individual analyses agree across JSON, CSV, XLSX and PDF',
    () async {
      final repo = LabRepository.inMemory();
      addTearDown(repo.dispose);
      final session = repo.createSession('Dos clientes');
      final phase = repo.createPhase(session.id, 'Fase');
      final testId = repo.createTest(
        phase.id,
        'E4',
        const TrialConfig(
          scenarioId: 'E4',
          clients: 2,
          distanceM: null,
          count: 2,
        ),
      );
      final trialId = repo.startTrial(testId);
      for (final (id, latency) in [('cliente-a', 10.0), ('cliente-b', 80.0)]) {
        repo.addMeasurement(
          Measurement(
            id: 'm-$id',
            sessionId: session.id,
            phaseId: phase.id,
            testId: testId,
            trialId: trialId,
            requestId: 'r-$id',
            scenarioId: 'E4',
            clients: 2,
            distanceM: .5,
            distanceSource: 'server_ble_rssi_estimate',
            distanceUncertaintyM: 1.5,
            timestampUtc: DateTime.utc(2026),
            success: true,
            bytesReceived: 32,
            latencyMs: latency,
            clientId: id,
          ),
        );
      }
      final service = ExportService(repo);
      final data = jsonDecode(service.json(session.id)) as Map;
      expect(data['app_version'], '0.1.0');
      expect(data['protocol_version'], 1);
      expect(data['server_metrics_scope'], 'whole_trial_all_clients');
      final analysis = data['analysis'] as Map;
      expect((analysis['general'] as Map)['n_total'], 2);
      expect((analysis['individual'] as Map).length, 2);
      expect(
        (analysis['general'] as Map)['interpretation'],
        contains('incertidumbre'),
      );
      final csv = service.analysisCsv(session.id);
      expect(csv.split('\n').where((line) => line.isNotEmpty).length, 4);
      expect(csv, contains('cliente-a'));
      expect(service.html(session.id), contains('Análisis por cliente'));
      final workbook = ZipDecoder().decodeBytes(service.xlsx(session.id));
      expect(
        utf8.decode(workbook.findFile('xl/workbook.xml')!.content),
        contains('AnalisisClientes'),
      );
      expect((await service.pdf(session.id)).take(4), [37, 80, 68, 70]);
      final client = jsonDecode(
        service.json(
          session.id,
          scope: const ExportScope(clientId: 'cliente-a'),
        ),
      ) as Map;
      expect((client['measurements'] as List).length, 1);
      expect((client['scope'] as Map)['client_id'], 'cliente-a');
      expect(
        (client['scope_notes'] as Map)['server_metrics'],
        contains('not attributed to one client'),
      );
      expect(
        ((client['analysis'] as Map)['general'] as Map)['mean_latency_ms'],
        10,
      );
      final individualCsv = service.analysisCsv(
        session.id,
        scope: const ExportScope(clientId: 'cliente-a'),
      );
      expect(individualCsv, contains(session.id));
      expect(individualCsv, contains('lanxis_version'));
      expect(individualCsv, isNot(contains('cliente-b')));
      final individualXlsx = ZipDecoder().decodeBytes(
        service.xlsx(
          session.id,
          scope: const ExportScope(clientId: 'cliente-a'),
        ),
      );
      expect(
        utf8.decode(individualXlsx.findFile('xl/workbook.xml')!.content),
        contains('Metadatos'),
      );
    },
  );
}
