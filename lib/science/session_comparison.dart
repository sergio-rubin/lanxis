import '../core/models.dart';
import 'analysis_report.dart';

typedef SessionObservations = ({LabSession session, List<Measurement> items});

/// Descriptive comparison. Each pooled statistic is recomputed from raw rows.
class SessionComparison {
  SessionComparison(List<SessionObservations> observations)
    : entries = [
        for (final observation in observations)
          SessionComparisonEntry(observation.session, observation.items),
      ],
      pooled = AnalysisSummary('Todas las sesiones seleccionadas', [
        for (final observation in observations) ...observation.items,
      ]) {
    if (entries.length < 2 ||
        entries.map((entry) => entry.session.id).toSet().length !=
            entries.length) {
      throw ArgumentError('Selecciona al menos dos sesiones diferentes.');
    }
  }

  final List<SessionComparisonEntry> entries;
  final AnalysisSummary pooled;

  SessionComparisonEntry get baseline => entries.first;

  List<String> get warnings {
    final protocols = entries.expand((entry) => entry.protocols).toSet();
    final scenarios = entries.expand((entry) => entry.scenarios).toSet();
    final clients = entries.expand((entry) => entry.clientIds).toList();
    return [
      if (protocols.length > 1) 'Se mezclan protocolos: sus RTT miden operaciones diferentes. Filtra antes de atribuir diferencias a una sola causa.',
      if (scenarios.length > 1) 'Se mezclan escenarios o cargas. Revisa sus configuraciones antes de atribuir diferencias a la red.',
      if (clients.length != clients.toSet().length) 'Un mismo cliente participa en varias sesiones; las observaciones pueden estar correlacionadas.',
      'Comparación descriptiva. Las muestras repetidas de un cliente o ensayo no son réplicas independientes y estos resultados no prueban causalidad.',
    ];
  }

  Map<String, Object?> toJson({bool includeMeasurements = false}) => {
    'baseline_session_id': baseline.session.id,
    'pooled': pooled.toJson(),
    'sessions': [
      for (final entry in entries)
        {
          ...entry.toJson(),
          'mean_difference_from_baseline_ms':
              entry.summary.stats.mean == null ||
                  baseline.summary.stats.mean == null
              ? null
              : entry.summary.stats.mean! - baseline.summary.stats.mean!,
          if (includeMeasurements)
            'measurements': [for (final item in entry.items) item.toJson()],
        },
    ],
    'warnings': warnings,
    'method': 'Pooled statistics recomputed from original valid RTT; sample variance n-1, quantiles type 7, SLA strict < 50 ms over all attempts.',
  };
}

class SessionComparisonEntry {
  SessionComparisonEntry(this.session, this.items)
    : summary = AnalysisSummary(session.name, items),
      protocols = items.map((item) => item.protocol).toSet(),
      scenarios = items.map((item) => item.scenarioId).toSet(),
      clientIds = items
          .map((item) => item.clientId)
          .whereType<String>()
          .toSet();

  final LabSession session;
  final List<Measurement> items;
  final AnalysisSummary summary;
  final Set<String> protocols;
  final Set<String> scenarios;
  final Set<String> clientIds;

  Map<String, Object?> toJson() => {
    'session_id': session.id,
    'session_name': session.name,
    'session_created_utc': session.createdAt.toUtc().toIso8601String(),
    'session_status': session.status,
    'summary': summary.toJson(),
    'protocols': protocols.toList()..sort(),
    'scenarios': scenarios.toList()..sort(),
    'client_ids': clientIds.toList()..sort(),
  };
}
