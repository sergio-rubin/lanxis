import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/core/models.dart';
import 'package:lanxis/data/lab_repository.dart';
import 'package:lanxis/export/export_service.dart';
import 'package:lanxis/network/network_lab.dart';

/// Real device-to-device check; skipped unless a local base URL and code are
/// provided through --dart-define. No credentials are stored in the repository.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const baseUrl = String.fromEnvironment('LANXIS_BASE');
  const code = String.fromEnvironment('LANXIS_CODE');
  const outputPath = String.fromEnvironment(
    'LANXIS_OUTPUT',
    defaultValue: '/tmp/lanxis-physical-smoke',
  );

  test('Android server ↔ Linux client on physical Wi-Fi', () async {
    // Flutter's default test binding replaces all outbound HTTP with 400s.
    HttpOverrides.global = null;
    final output = Directory(outputPath);
    await output.create(recursive: true);
    final repository = LabRepository.openAt(
      File('${output.path}/physical.sqlite'),
    );
    final network = NetworkLab(repository);
    final base = Uri.parse(baseUrl);
    try {
      final health = await network.probe(base);
      stdout.writeln('Servidor: $health');
      final session = repository.createSession(
        'Prueba física Android ↔ Linux',
        notes:
            'Cliente Linux ${Platform.operatingSystemVersion}; servidor ${base.host}',
      );
      final phase = repository.createPhase(session.id, 'Wi-Fi existente');
      final cases = <({String protocol, String direction, int bytes})>[
        (protocol: 'http', direction: 'download', bytes: 0),
        (protocol: 'http', direction: 'download', bytes: 65536),
        (protocol: 'http', direction: 'upload', bytes: 65536),
        (protocol: 'tcp', direction: 'download', bytes: 0),
        (protocol: 'tcp', direction: 'download', bytes: 65536),
        (protocol: 'tcp', direction: 'upload', bytes: 65536),
        (protocol: 'udp', direction: 'download', bytes: 32),
      ];
      var failures = 0;
      for (final scenario in cases) {
        final samples = await network.runTrial(
          base: base,
          code: code,
          session: session,
          phase: phase,
          config: TrialConfig(
            scenarioId: 'Libre',
            clients: 1,
            distanceM: 0,
            count: 5,
            warmup: 1,
            intervalMs: 50,
            timeoutMs: 5000,
            payloadBytes: scenario.bytes,
            protocol: scenario.protocol,
            direction: scenario.direction,
          ),
        );
        final failed = samples.where((s) => !s.success).toList();
        failures += failed.length;
        final rtts = samples
            .where((s) => s.latencyMs != null)
            .map((s) => s.latencyMs!)
            .toList();
        final average = rtts.isEmpty
            ? null
            : rtts.reduce((a, b) => a + b) / rtts.length;
        stdout.writeln(
          '${scenario.protocol} ${scenario.direction} ${scenario.bytes} B: '
          '${samples.length - failed.length}/${samples.length} correctas; '
          'RTT medio ${average?.toStringAsFixed(2) ?? '—'} ms; '
          'errores ${failed.map((s) => s.error).toList()}',
        );
      }
      final report = ExportService(repository).json(session.id);
      await File('${output.path}/physical.json').writeAsString(report);
      stdout.writeln('Dataset: ${output.path}/physical.json');
      expect(
        failures,
        0,
        reason:
            'Se encontraron fallos de red o integridad en la prueba física.',
      );
    } finally {
      repository.dispose();
    }
  }, skip: baseUrl.isEmpty || code.isEmpty);
}
