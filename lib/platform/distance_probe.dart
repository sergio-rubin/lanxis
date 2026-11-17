import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'ble_scanner_linux.dart';

class DistanceObservation {
  const DistanceObservation({
    this.meters,
    this.uncertaintyM,
    this.rssiDbm,
    this.rssiSamplesDbm = const [],
    this.source = 'unknown',
    this.reason,
  });
  final double? meters;
  final double? uncertaintyM;
  final int? rssiDbm;
  final List<int> rssiSamplesDbm;
  final String source;
  final String? reason;
}

class DistanceProbe {
  const DistanceProbe();
  static const _channel = MethodChannel('mx.lanxis/distance');

  Future<DistanceObservation> measure(
    Uri server, {
    String? beaconToken,
    String environment = 'indoor',
  }) async {
    try {
      if (Platform.isLinux) {
        if (beaconToken == null) {
          return const DistanceObservation(
            reason: 'El servidor no anuncia una baliza BLE para estimar la distancia.',
          );
        }
        final samples = await const LinuxBleScanner().sample(beaconToken);
        return BleDistanceEstimator.estimate(
          samples,
          environment: environment,
          allowSparse: true,
        );
      }
      final result = await _channel
          .invokeMapMethod<String, Object?>('measureToServer', {
            'host': server.host,
            'beaconToken': beaconToken,
          })
          .timeout(const Duration(seconds: 30));
      final rssiSamples =
          (result?['rssi_samples_dbm'] as List?)?.whereType<int>().toList() ??
          const <int>[];
      if (result?['source'] == 'ble_rssi_samples') {
        return BleDistanceEstimator.estimate(
          rssiSamples,
          environment: environment,
          allowSparse: true,
        );
      }
      final meters = (result?['distance_m'] as num?)?.toDouble();
      if (meters == null || !meters.isFinite || meters < 0) {
        return DistanceObservation(
          reason:
              result?['reason'] as String? ??
              'La plataforma no ofreció distancia al servidor.',
        );
      }
      return DistanceObservation(
        meters: meters,
        uncertaintyM: (result?['uncertainty_m'] as num?)?.toDouble(),
        rssiDbm: result?['rssi_dbm'] as int?,
        rssiSamplesDbm: rssiSamples,
        source: result?['source'] as String? ?? 'wifi_rtt_ap',
      );
    } on MissingPluginException {
      return const DistanceObservation(
        reason: 'Medición automática no disponible en esta plataforma.',
      );
    } on PlatformException catch (error) {
      return DistanceObservation(reason: error.message ?? error.code);
    } catch (error) {
      return DistanceObservation(reason: '$error');
    }
  }
}

class BleDistanceEstimator {
  const BleDistanceEstimator._();

  /// Uncalibrated log-distance model. Its wide margin is a quality flag, not
  /// a confidence interval or a replacement for a physical measurement.
  static DistanceObservation estimate(
    List<int> samples, {
    String environment = 'indoor',
    bool allowSparse = false,
  }) {
    final sorted =
        samples.where((value) => value >= -110 && value <= -20).toList()
          ..sort();
    if (sorted.length < (allowSparse ? 1 : 3)) {
      return const DistanceObservation(
        reason: 'La baliza Bluetooth no proporcionó suficientes lecturas.',
      );
    }
    final median = sorted[sorted.length ~/ 2];
    final lower = sorted[((sorted.length - 1) * .1).floor()];
    final upper = sorted[((sorted.length - 1) * .9).ceil()];
    final spread = (upper - lower) / 2;
    final exponent = environment == 'outdoor' ? 2.2 : 2.7;
    final meters = math
        .pow(10, (-59 - median) / (10 * exponent))
        .toDouble()
        .clamp(.2, 50.0);
    final variation = math.pow(10, math.max(4, spread) / (10 * exponent)) - 1;
    final sparse = sorted.length < 3;
    final uncertainty = sparse
        ? math.max(3.0, meters * (4 + variation))
        : math.max(1.5, meters * (1.5 + variation));
    return DistanceObservation(
      meters: meters,
      uncertaintyM: uncertainty,
      rssiDbm: median,
      rssiSamplesDbm: sorted,
      source: sparse ? 'ble_rssi_estimate_sparse' : 'ble_rssi_estimate',
    );
  }
}
