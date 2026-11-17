import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/core/models.dart';
import 'package:lanxis/data/lab_repository.dart';
import 'package:lanxis/network/network_lab.dart';
import 'package:lanxis/network/tcp_transfer.dart';
import 'package:lanxis/network/udp_echo.dart';

void main() {
  test('LAN discovery falls back to a verified HTTP health probe', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'name': 'LANXIS', 'version': 1}));
      await request.response.close();
    });
    final repo = LabRepository.inMemory();
    addTearDown(repo.dispose);
    final found = await NetworkLab(repo).discover(
      duration: const Duration(milliseconds: 10),
      target: InternetAddress('192.0.2.1'),
      fallbackAddresses: [InternetAddress.loopbackIPv4],
      fallbackPort: server.port,
    );
    expect(found.single.uri, Uri.parse('http://127.0.0.1:${server.port}'));
  });

  test(
    'missing ranging hardware keeps the trial and explains the gap',
    () async {
      final repo = LabRepository.inMemory();
      final network = NetworkLab(repo);
      addTearDown(() async {
        await network.stopServer();
        repo.dispose();
      });
      final port = await network.startServer(port: 0);
      final session = repo.createSession('Distancia opcional');
      final phase = repo.createPhase(session.id, 'Sin sensor');
      final samples = await network.runTrial(
        base: Uri.parse('http://127.0.0.1:$port'),
        code: network.pairCode!,
        session: session,
        phase: phase,
        config: const TrialConfig(
          scenarioId: 'E1',
          clients: 1,
          count: 1,
          warmup: 0,
          intervalMs: 0,
        ),
      );
      expect(samples.single.success, true);
      expect(samples.single.distanceM, isNull);
      expect(network.lastDistanceReason, isNotEmpty);
    },
  );

  test('client identity and result outbox survive reopening SQLite', () async {
    final directory = await Directory.systemTemp.createTemp('lanxis-outbox-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/lab.sqlite');
    final first = LabRepository.openAt(file);
    final identity = first.clientIdentity;
    final queued = first.queueResult('http://127.0.0.1:8040', '{"job_id":"j"}');
    first.dispose();
    final second = LabRepository.openAt(file);
    expect(second.clientIdentity, identity);
    expect(second.pendingResultCount, 1);
    expect(second.pendingResults('http://127.0.0.1:8040').single['id'], queued);
    second.acknowledgeResult(queued);
    expect(second.pendingResultCount, 0);
    final obsolete = second.queueResult(
      'http://127.0.0.1:8040',
      '{"job_id":"old"}',
    );
    second.markResultRejected(obsolete);
    expect(second.pendingResultCount, 0);
    expect(second.rejectedResultCount, 1);
    second.dispose();
    final third = LabRepository.openAt(file);
    expect(third.rejectedResultCount, 1);
    expect(third.pendingResults('http://127.0.0.1:8040'), isEmpty);
    third.dispose();
  });

  test('session hierarchy and duplicate request protection', () {
    final repo = LabRepository.inMemory();
    addTearDown(repo.dispose);
    final session = repo.createSession('Estudio');
    final phase = repo.createPhase(session.id, 'Fase 1');
    final testId = repo.createTest(
      phase.id,
      'E1',
      const TrialConfig(scenarioId: 'E1', clients: 1, distanceM: 1, count: 1),
    );
    final trialId = repo.startTrial(testId);
    final m = Measurement(
      id: 'm1',
      sessionId: session.id,
      phaseId: phase.id,
      testId: testId,
      trialId: trialId,
      requestId: 'request-1',
      scenarioId: 'E1',
      clients: 1,
      distanceM: 1,
      timestampUtc: DateTime.now().toUtc(),
      success: true,
      bytesReceived: 10,
      latencyMs: 12,
    );
    repo.addMeasurement(m);
    repo.addMeasurement(m);
    expect(repo.measurementCount(session.id), 1);
    expect(repo.phases(session.id).single.name, 'Fase 1');
    repo.updatePhaseStatus(session.id, phase.id, 'paused');
    expect(repo.phases(session.id).single.status, 'paused');
    repo.updateSessionStatus(session.id, 'finished');
    expect(repo.sessions().single.status, 'finished');
  });

  test(
    'HTTP server, pairing, RTT and streaming transfer on loopback',
    () async {
      final repo = LabRepository.inMemory();
      final network = NetworkLab(repo);
      addTearDown(() async {
        await network.stopServer();
        repo.dispose();
      });
      final port = await network.startServer(port: 0);
      final base = Uri.parse('http://127.0.0.1:$port');
      final health = await network.probe(base);
      expect(health['version'], 1);
      expect((health['capabilities'] as List).contains('udp-discovery'), true);
      final discovered = await network.discover(
        duration: const Duration(milliseconds: 100),
        target: InternetAddress.loopbackIPv4,
      );
      expect(discovered.any((server) => server.port == port), true);
      final registration = await network.register(base, network.pairCode!);
      expect(registration['client_id'], network.clientId);
      expect(network.connectedClients, 1);
      final session = repo.createSession('Loopback');
      final phase = repo.createPhase(session.id, 'Transferencia');
      final results = await network.runTrial(
        base: base,
        code: network.pairCode!,
        session: session,
        phase: phase,
        config: const TrialConfig(
          scenarioId: 'Libre',
          clients: 1,
          distanceM: 0,
          count: 2,
          warmup: 0,
          payloadBytes: 1024,
          intervalMs: 0,
        ),
      );
      expect(results.length, 2);
      expect(results.every((m) => m.success && m.bytesReceived == 1024), true);
      expect(repo.measurementCount(session.id), 2);
      final uploads = await network.runTrial(
        base: base,
        code: network.pairCode!,
        session: session,
        phase: phase,
        config: const TrialConfig(
          scenarioId: 'Libre',
          clients: 1,
          distanceM: 0,
          count: 2,
          warmup: 0,
          payloadBytes: 1024,
          direction: 'upload',
          intervalMs: 0,
        ),
      );
      expect(uploads.length, 2);
      expect(
        uploads.every(
          (m) =>
              m.success &&
              m.bytesSent == 1024 &&
              m.speedMbps != null &&
              m.speedMbps! > 0,
        ),
        true,
      );
      expect(repo.measurementCount(session.id), 4);
      await expectLater(
        network.runTrial(
          base: base,
          code: network.pairCode!,
          session: session,
          phase: phase,
          config: const TrialConfig(
            scenarioId: 'E4',
            clients: 4,
            distanceM: 1,
            count: 1,
          ),
        ),
        throwsUnsupportedError,
      );
    },
  );

  test('TCP engine streams both directions and records protocol', () async {
    final repo = LabRepository.inMemory();
    final network = NetworkLab(repo);
    addTearDown(() async {
      await network.stopServer();
      repo.dispose();
    });
    final port = await network.startServer(port: 0);
    final base = Uri.parse('http://127.0.0.1:$port');
    final health = await network.probe(base);
    expect((health['capabilities'] as List).contains('tcp-transfer'), true);
    expect(health['tcp_port'], isA<int>());
    await expectLater(
      TcpTransferClient.sample(
        host: '127.0.0.1',
        port: health['tcp_port'] as int,
        code: '000000',
        requestId: '00000000-0000-0000-0000-000000000000',
        direction: 'download',
        bytes: 32,
        timeout: const Duration(seconds: 5),
      ),
      throwsStateError,
    );
    final session = repo.createSession('TCP loopback');
    final phase = repo.createPhase(session.id, 'Transferencia');
    for (final direction in ['download', 'upload']) {
      final results = await network.runTrial(
        base: base,
        code: network.pairCode!,
        session: session,
        phase: phase,
        config: TrialConfig(
          scenarioId: 'Libre',
          clients: 1,
          distanceM: 0,
          count: 2,
          warmup: 0,
          intervalMs: 0,
          payloadBytes: 123457,
          protocol: 'tcp',
          direction: direction,
        ),
      );
      expect(results.length, 2);
      expect(results.every((m) => m.success && m.protocol == 'tcp'), true);
      expect(
        results.every(
          (m) => direction == 'upload'
              ? m.bytesSent == 123457 && m.speedMbps != null
              : m.bytesReceived == 123457 && m.speedMbps != null,
        ),
        true,
      );
    }
    final ping = await network.runTrial(
      base: base,
      code: network.pairCode!,
      session: session,
      phase: phase,
      config: const TrialConfig(
        scenarioId: 'Libre',
        clients: 1,
        distanceM: 0,
        count: 1,
        warmup: 0,
        intervalMs: 0,
        protocol: 'tcp',
      ),
    );
    expect(ping.single.success, true);
    expect(ping.single.bytesReceived, 0);
  });

  test('UDP echo records successful RTT and an observed timeout', () async {
    final repo = LabRepository.inMemory();
    final network = NetworkLab(repo);
    addTearDown(() async {
      await network.stopServer();
      repo.dispose();
    });
    final port = await network.startServer(port: 0);
    final base = Uri.parse('http://127.0.0.1:$port');
    final health = await network.probe(base);
    expect((health['capabilities'] as List).contains('udp-echo'), true);
    await expectLater(
      UdpEchoClient.sample(
        host: '127.0.0.1',
        port: health['udp_port'] as int,
        code: '000000',
        requestId: '00000000-0000-0000-0000-000000000000',
        payloadBytes: 8,
        timeout: const Duration(milliseconds: 150),
      ),
      throwsA(isA<TimeoutException>()),
    );
    final session = repo.createSession('UDP loopback');
    final phase = repo.createPhase(session.id, 'Eco');
    final results = await network.runTrial(
      base: base,
      code: network.pairCode!,
      session: session,
      phase: phase,
      config: const TrialConfig(
        scenarioId: 'Libre',
        clients: 1,
        distanceM: 0,
        count: 3,
        warmup: 0,
        intervalMs: 0,
        payloadBytes: 32,
        protocol: 'udp',
      ),
    );
    expect(results.length, 3);
    expect(results.every((m) => m.success && m.protocol == 'udp'), true);
    expect(
      results.every((m) => m.bytesReceived > 32 && m.speedMbps == null),
      true,
    );
    expect(results.every((m) => m.bytesSent == m.bytesReceived), true);
  });

  test('UDP burst persists packet order, loss and measured RTT', () async {
    final repo = LabRepository.inMemory();
    final network = NetworkLab(repo);
    addTearDown(() async {
      await network.stopServer();
      repo.dispose();
    });
    final port = await network.startServer(port: 0);
    final session = repo.createSession('Ráfaga UDP');
    final phase = repo.createPhase(session.id, 'Orden de llegada');
    final results = await network.runTrial(
      base: Uri.parse('http://127.0.0.1:$port'),
      code: network.pairCode!,
      session: session,
      phase: phase,
      config: const TrialConfig(
        scenarioId: 'Libre',
        clients: 1,
        distanceM: 0,
        count: 4,
        warmup: 1,
        intervalMs: 0,
        timeoutMs: 500,
        payloadBytes: 16,
        protocol: 'udp-burst',
      ),
    );
    expect(results, hasLength(4));
    expect(results.every((m) => m.success && m.protocol == 'udp-burst'), true);
    expect(network.lastUdpBurstResult?.lost, 0);
    final event = repo
        .eventsForSession(session.id)
        .firstWhere((item) => item['type'] == 'udp_burst_summary');
    final metadata = jsonDecode(event['metadata_json'] as String) as Map;
    expect(metadata['sent'], 5);
    expect(metadata['received'], 5);
    expect(metadata['lost'], 0);
    expect(metadata['packets'], hasLength(5));
  });

  test(
    'two participant instances coordinate E4 and preserve provenance',
    () async {
      final serverRepo = LabRepository.inMemory();
      final workerRepos = [LabRepository.inMemory(), LabRepository.inMemory()];
      final server = NetworkLab(serverRepo);
      final workers = workerRepos.map(NetworkLab.new).toList();
      addTearDown(() async {
        for (final worker in workers) {
          await worker.stopParticipant();
        }
        await server.stopServer();
        for (final repo in workerRepos) {
          repo.dispose();
        }
        serverRepo.dispose();
      });
      final port = await server.startServer(port: 0);
      final base = Uri.parse('http://127.0.0.1:$port');
      for (final worker in workers) {
        await worker.startParticipant(base, server.pairCode!);
      }
      for (var i = 0; i < 50 && server.readyWorkers < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(server.readyWorkers, 2);
      final session = serverRepo.createSession('Factorial');
      final phase = serverRepo.createPhase(session.id, 'Fase multicliente');
      final actual = await server.runCoordinatedTrial(
        session: session,
        phase: phase,
        config: const TrialConfig(
          scenarioId: 'E4',
          clients: 2,
          distanceM: 1,
          count: 3,
          warmup: 0,
          intervalMs: 0,
        ),
      );
      expect(actual, 6);
      final samples = serverRepo.measurements(session.id);
      expect(samples.every((m) => m.success && m.clients == 2), true);
      expect(samples.map((m) => m.clientId).toSet().length, 2);
      final local = workerRepos.first.sessions().first;
      final jobId = RegExp(r'Ensayo coordinado ([^ ]+)')
          .firstMatch(local.notes)!
          .group(1)!;
      workerRepos.first.queueResult(
        base.toString(),
        jsonEncode({
          'job_id': jobId,
          'client_id': workers.first.clientId,
          'samples': [workerRepos.first.measurements(local.id).first.toJson()],
        }),
      );
      for (var i = 0; i < 30 && workerRepos.first.pendingResultCount > 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(workerRepos.first.pendingResultCount, 0);
      expect(serverRepo.measurementCount(session.id), 6);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test('server starts an E1 trial for one passive client and records server metrics', () async {
    final serverRepo = LabRepository.inMemory();
    final clientRepo = LabRepository.inMemory();
    final server = NetworkLab(serverRepo);
    final client = NetworkLab(clientRepo);
    addTearDown(() async {
      await client.stopParticipant();
      await server.stopServer();
      clientRepo.dispose();
      serverRepo.dispose();
    });
    final port = await server.startServer(port: 0);
    final base = Uri.parse('http://127.0.0.1:$port');
    await client.startParticipant(base, server.pairCode!);
    for (var i = 0; i < 50 && server.readyWorkers < 1; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(server.readyWorkers, 1);
    final session = serverRepo.createSession('Servidor E1');
    final phase = serverRepo.createPhase(session.id, 'Única');
    final actual = await server.runCoordinatedTrial(
      session: session,
      phase: phase,
      config: const TrialConfig(
        scenarioId: 'E1',
        clients: 1,
        distanceM: null,
        count: 2,
        warmup: 0,
        intervalMs: 0,
      ),
    );
    expect(actual, 2);
    expect(
      serverRepo
          .measurements(session.id)
          .every((m) => m.clientId == client.clientId),
      true,
    );
    final completed = serverRepo
        .eventsForSession(session.id)
        .firstWhere((e) => e['type'] == 'coordinated_trial_finished');
    final metadata = jsonDecode(completed['metadata_json'] as String) as Map;
    expect(metadata['server_received_samples'], 2);
    expect(metadata['server_elapsed_ms'], isA<int>());
  }, timeout: const Timeout(Duration(seconds: 45)));
}
