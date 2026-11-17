import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/core/models.dart';
import 'package:lanxis/data/lab_repository.dart';
import 'package:lanxis/network/network_lab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const baseUrl = String.fromEnvironment('LANXIS_BASE');
  const code = String.fromEnvironment('LANXIS_CODE');

  test(
    'Linux trial against Android stores BLE distance only as metadata',
    () async {
      HttpOverrides.global = null;
      final directory = await Directory.systemTemp.createTemp(
        'lanxis-ble-trial-',
      );
      final repository = LabRepository.openAt(
        File('${directory.path}/trial.sqlite'),
      );
      try {
        final network = NetworkLab(repository);
        final session = repository.createSession('Prueba BLE física');
        final phase = repository.createPhase(session.id, 'Android a Linux');
        final results = await network.runTrial(
          base: Uri.parse(baseUrl),
          code: code,
          session: session,
          phase: phase,
          config: const TrialConfig(
            scenarioId: 'E1',
            clients: 1,
            distanceM: null,
            count: 3,
            warmup: 0,
            intervalMs: 100,
            timeoutMs: 5000,
            payloadBytes: 0,
            protocol: 'http',
            direction: 'download',
          ),
        );
        expect(results, hasLength(3));
        expect(results.every((result) => result.success), isTrue);
        expect(results.every((result) => result.protocol == 'http'), isTrue);
        expect(results.first.distanceM, isNotNull);
        expect(results.first.distanceSource, startsWith('ble_rssi_estimate'));
        expect(
          results.first.rssiDbm,
          isNull,
          reason: 'El RSSI BLE no debe entrar como variable de red.',
        );
        // ignore: avoid_print
        print(
          'Physical trial: ${results.length}/3, BLE '
          '${results.first.distanceM} ±${results.first.distanceUncertaintyM} m',
        );
      } finally {
        repository.dispose();
        await directory.delete(recursive: true);
      }
    },
    skip: baseUrl.isEmpty || code.isEmpty,
  );
}
