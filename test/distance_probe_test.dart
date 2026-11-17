import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/platform/distance_probe.dart';

void main() {
  test('BLE estimate orders signal strength without claiming precision', () {
    final near = BleDistanceEstimator.estimate([-56, -57, -58, -57, -56]);
    final far = BleDistanceEstimator.estimate([-81, -80, -83, -79, -82]);
    expect(near.meters, isNotNull);
    expect(far.meters!, greaterThan(near.meters!));
    expect(far.source, 'ble_rssi_estimate');
    expect(far.uncertaintyM!, greaterThan(far.meters!));
    expect(far.rssiDbm, -81);
  });

  test('BLE median resists a stray reading and needs repeated samples', () {
    final stable = BleDistanceEstimator.estimate([-70, -70, -70, -70, -70]);
    final withStray = BleDistanceEstimator.estimate([
      -70,
      -70,
      -70,
      -70,
      -70,
      -20,
    ]);
    expect(withStray.meters, stable.meters);
    expect(BleDistanceEstimator.estimate([-70, -70]).meters, isNull);
  });

  test('a sparse BlueZ reading is labelled and carries a wider margin', () {
    final sparse = BleDistanceEstimator.estimate([-52], allowSparse: true);
    expect(sparse.source, 'ble_rssi_estimate_sparse');
    expect(sparse.rssiSamplesDbm, [-52]);
    expect(sparse.uncertaintyM, greaterThanOrEqualTo(3));
    expect(BleDistanceEstimator.estimate([], allowSparse: true).meters, isNull);
  });
}
