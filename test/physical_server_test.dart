import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/data/lab_repository.dart';
import 'package:lanxis/network/network_lab.dart';

/// Keeps a real Linux LANXIS server open for a phone client. Skipped in CI.
void main() {
  const enabled = bool.fromEnvironment('LANXIS_PHYSICAL_SERVER');
  const expectClient = bool.fromEnvironment(
    'LANXIS_EXPECT_CLIENT',
    defaultValue: true,
  );
  const stopFile = String.fromEnvironment(
    'LANXIS_STOP_FILE',
    defaultValue: '/tmp/lanxis-physical-server-stop',
  );
  test(
    'Linux server accepts an Android client',
    () async {
      final repository = LabRepository.inMemory();
      final network = NetworkLab(repository);
      try {
        final port = await network.startServer(port: 8040);
        stdout.writeln('Servidor Linux: http://192.168.1.65:$port');
        stdout.writeln('Baliza BLE: ${network.bleBeaconError ?? 'activa'}');
        stdout.writeln('Código: ${network.pairCode}');
        stdout.writeln(
          'Esperando al cliente Android; finalizar creando $stopFile',
        );
        final deadline = DateTime.now().add(const Duration(minutes: 20));
        while (DateTime.now().isBefore(deadline) &&
            !File(stopFile).existsSync()) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        stdout.writeln('Clientes registrados: ${network.connectedClients}');
        if (expectClient) expect(network.connectedClients, greaterThan(0));
      } finally {
        await network.stopServer();
        repository.dispose();
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 21)),
  );
}
