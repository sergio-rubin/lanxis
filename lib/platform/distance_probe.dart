import 'package:flutter/services.dart';

class DistanceObservation {
  const DistanceObservation({
    this.meters,
    this.uncertaintyM,
    this.source = 'unknown',
    this.reason,
  });
  final double? meters;
  final double? uncertaintyM;
  final String source;
  final String? reason;
}

class DistanceProbe {
  const DistanceProbe();
  static const _channel = MethodChannel('mx.lanxis/distance');

  Future<DistanceObservation> measure(Uri server) async {
    try {
      final result = await _channel
          .invokeMapMethod<String, Object?>('measureToServer', {
            'host': server.host,
          })
          .timeout(const Duration(seconds: 30));
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
