import '../core/models.dart';
import 'descriptive.dart';

/// Descriptive report shared by the screen and every export format.
class AnalysisSummary {
  AnalysisSummary(this.label, List<Measurement> items)
    : total = items.length,
      valid = items.where((m) => m.success && m.latencyMs != null).length,
      failed = items.where((m) => !m.success).length,
      withoutValidRtt = items
          .where((m) => !m.success || m.latencyMs == null)
          .length,
      stats = DescriptiveEngine.calculate(
        items
            .where((m) => m.success && m.latencyMs != null)
            .map((m) => m.latencyMs!),
      ),
      sla = DescriptiveEngine.successRate(items),
      distances = items
          .where((m) => m.distanceM != null)
          .map((m) => m.distanceM!)
          .toList(),
      distanceSources = items
          .where((m) => m.distanceM != null)
          .map((m) => m.distanceSource)
          .toSet(),
      protocols = items.map((m) => m.protocol).toSet(),
      uncertainty = items
          .where((m) => m.distanceUncertaintyM != null)
          .map((m) => m.distanceUncertaintyM!)
          .toList();

  final String label;
  final int total;
  final int valid;
  final int failed;
  final int withoutValidRtt;
  final DescriptiveStats stats;
  final double? sla;
  final List<double> distances;
  final Set<String> distanceSources;
  final Set<String> protocols;
  final List<double> uncertainty;

  double? get medianDistanceM =>
      distances.isEmpty ? null : DescriptiveEngine.calculate(distances).median;
  double? get maxUncertaintyM =>
      uncertainty.isEmpty ? null : uncertainty.reduce((a, b) => a > b ? a : b);

  String get interpretation {
    if (total == 0) return 'No hay observaciones para interpretar.';
    if (valid == 0) {
      return 'No hubo respuestas con RTT válido. La latencia no puede estimarse; $failed de $total observaciones fallaron.';
    }
    final mean = stats.mean!.toStringAsFixed(2);
    final p95 = stats.p95!.toStringAsFixed(2);
    final rate = sla == null
        ? 'sin dato'
        : '${(sla! * 100).toStringAsFixed(1)} %';
    final distance = medianDistanceM == null
        ? 'No se obtuvo distancia para esta selección.'
        : 'Distancia mediana registrada: ${medianDistanceM!.toStringAsFixed(2)} m${maxUncertaintyM == null ? '' : ' (incertidumbre orientativa máxima ±${maxUncertaintyM!.toStringAsFixed(2)} m)'}. ${distanceSources.any((source) => source.contains('ble_rssi_estimate')) ? 'La estimación BLE por RSSI requiere calibración y no es una medición precisa.' : ''}';
    return 'De $total observaciones, $valid tuvieron RTT válido, $failed fallaron y $withoutValidRtt no aportaron RTT válido. RTT medio $mean ms; P95 muestral (cuantil tipo 7) $p95 ms. El criterio SLA estricto (< 50 ms) se cumplió en $rate de todas las observaciones. Protocolos incluidos: ${protocols.join(', ')}; si hay más de uno, el RTT conjunto mezcla operaciones distintas. $distance Las muestras repetidas de un dispositivo pueden estar correlacionadas; estas cifras son descriptivas y no demuestran causalidad.';
  }

  Map<String, Object?> toJson() => {
    'label': label,
    'n_total': total,
    'n_valid': valid,
    'n_failed': failed,
    'n_without_valid_rtt': withoutValidRtt,
    'mean_latency_ms': stats.mean,
    'median_latency_ms': stats.median,
    'p95_latency_ms': stats.p95,
    'sample_sd_ms': stats.standardDeviation,
    'sla_probability': sla,
    'median_distance_m': medianDistanceM,
    'max_distance_uncertainty_m': maxUncertaintyM,
    'distance_sources': distanceSources.toList(),
    'protocols': protocols.toList(),
    'interpretation': interpretation,
  };
}

class AnalysisReport {
  AnalysisReport(List<Measurement> items)
    : general = AnalysisSummary('Todos los clientes', items),
      individual = {
        for (final id
            in items.map((m) => m.clientId ?? 'Sin identificador').toSet())
          id: AnalysisSummary(
            id,
            items
                .where((m) => (m.clientId ?? 'Sin identificador') == id)
                .toList(),
          ),
      };

  final AnalysisSummary general;
  final Map<String, AnalysisSummary> individual;

  Map<String, Object?> toJson() => {
    'general': general.toJson(),
    'individual': {
      for (final entry in individual.entries) entry.key: entry.value.toJson(),
    },
  };
}
