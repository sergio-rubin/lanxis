import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/platform/ble_scanner_linux.dart';
import 'package:lanxis/platform/distance_probe.dart';

void main() {
  final server = Platform.environment['LANXIS_PHYSICAL_BLE_SERVER'];
  test('Linux reads the matching Android BLE beacon', () async {
    final uri = Uri.parse(server!);
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(uri.resolve('/health')))
          .close();
      expect(response.statusCode, HttpStatus.ok);
      final health = jsonDecode(
        await utf8.decoder.bind(response).join(),
      ) as Map<String, dynamic>;
      final token = health['distance_beacon_token'] as String?;
      expect(token, isNotNull, reason: 'El servidor no anunció BLE.');
      final samples = await const LinuxBleScanner().sample(token!);
      // Captured data is useful for diagnosing radios and stays on this host.
      // ignore: avoid_print
      print('BlueZ RSSI samples: $samples');
      final observation = BleDistanceEstimator.estimate(
        samples,
        allowSparse: true,
      );
      expect(
        observation.source,
        startsWith('ble_rssi_estimate'),
        reason: observation.reason,
      );
      expect(observation.meters, isNotNull);
      expect(observation.uncertaintyM, greaterThan(0));
      expect(observation.rssiSamplesDbm, isNotEmpty);
      if (samples.length < 3) {
        expect(observation.source, 'ble_rssi_estimate_sparse');
        expect(observation.uncertaintyM, greaterThanOrEqualTo(3));
      }
      // ignore: avoid_print
      print(
        'BLE estimate: ${observation.meters} ±${observation.uncertaintyM} m',
      );
    } finally {
      client.close(force: true);
    }
  }, skip: server == null ? 'Requiere servidor Android físico.' : false);
}
