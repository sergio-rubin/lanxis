import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/core/models.dart';
import 'package:lanxis/data/lab_repository.dart';
import 'package:lanxis/export/export_service.dart';
import 'package:lanxis/network/network_lab.dart';

/// Manual hardware test: Linux hosts, Android waits as a passive client.
void main() {
  const enabled = bool.fromEnvironment('LANXIS_PHYSICAL_COORDINATED');
  const triggerFile = String.fromEnvironment(
    'LANXIS_TRIGGER_FILE',
    defaultValue: '/tmp/lanxis-trigger-coordinated',
  );
  test(
    'server initiates E1 while Android participates',
    () async {
      final repo = LabRepository.inMemory();
      final network = NetworkLab(repo);
      try {
        final port = await network.startServer(port: 8040);
        stdout.writeln('Servidor: http://192.168.1.65:$port');
        stdout.writeln('Código: ${network.pairCode}');
        stdout.writeln('Baliza Linux: ${network.bleBeaconError ?? 'activa'}');
        final deadline = DateTime.now().add(const Duration(minutes: 15));
        while (DateTime.now().isBefore(deadline) &&
            (!File(triggerFile).existsSync() || network.readyWorkers < 1)) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        expect(
          File(triggerFile).existsSync(),
          true,
          reason: 'No se activó la prueba física',
        );
        expect(
          network.readyWorkers,
          1,
          reason: 'El cliente Android no está listo',
        );
        final session = repo.createSession('Android cliente pasivo');
        final phase = repo.createPhase(session.id, 'Servidor inicia E1');
        final monitor = Timer.periodic(const Duration(seconds: 2), (_) {
          stdout.writeln(
            'Progreso: listos=${network.readyWorkers}, entregados=${network.deliveredWorkers}, terminados=${network.completedWorkers}, muestras=${network.coordinatedSamples}',
          );
        });
        int actual;
        try {
          actual = await network.runCoordinatedTrial(
            session: session,
            phase: phase,
            config: const TrialConfig(
              scenarioId: 'E1',
              clients: 1,
              distanceM: null,
              count: 5,
              warmup: 0,
              intervalMs: 300,
            ),
          );
        } catch (_) {
          stdout.writeln(
            'Muestras parciales: ${repo.measurements(session.id).length}',
          );
          rethrow;
        } finally {
          monitor.cancel();
        }
        final samples = repo.measurements(session.id);
        stdout.writeln('Recibidas: $actual/5');
        stdout.writeln('Distancia: ${samples.firstOrNull?.distanceM} m');
        stdout.writeln('Origen: ${samples.firstOrNull?.distanceSource}');
        stdout.writeln(
          'Incertidumbre: ${samples.firstOrNull?.distanceUncertaintyM} m',
        );
        stdout.writeln('Cliente: ${samples.firstOrNull?.clientId}');
        expect(actual, 5);
        expect(samples.every((m) => m.success && m.clientId != null), true);
        final output = File('dist/physical-android-client-4016.json');
        output.parent.createSync(recursive: true);
        output.writeAsStringSync(ExportService(repo).json(session.id));
        stdout.writeln('Exportación local: ${output.path}');
      } finally {
        await network.stopServer();
        repo.dispose();
        if (File(triggerFile).existsSync()) File(triggerFile).deleteSync();
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 17)),
  );
}
