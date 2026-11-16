import 'dart:convert';

class LabSession {
  const LabSession({
    required this.id,
    required this.name,
    required this.createdAt,
    this.status = 'active',
    this.notes = '',
  });
  final String id;
  final String name;
  final DateTime createdAt;
  final String status;
  final String notes;

  factory LabSession.fromRow(Map<String, Object?> row) => LabSession(
    id: row['id'] as String,
    name: row['name'] as String,
    createdAt: DateTime.parse(row['created_utc'] as String),
    status: row['status'] as String,
    notes: row['notes'] as String? ?? '',
  );
}

class LabPhase {
  const LabPhase({
    required this.id,
    required this.sessionId,
    required this.name,
    required this.createdAt,
    this.status = 'active',
  });
  final String id;
  final String sessionId;
  final String name;
  final DateTime createdAt;
  final String status;

  factory LabPhase.fromRow(Map<String, Object?> row) => LabPhase(
    id: row['id'] as String,
    sessionId: row['session_id'] as String,
    name: row['name'] as String,
    createdAt: DateTime.parse(row['created_utc'] as String),
    status: row['status'] as String,
  );
}

class TrialConfig {
  const TrialConfig({
    required this.scenarioId,
    required this.clients,
    required this.distanceM,
    required this.count,
    this.payloadBytes = 0,
    this.intervalMs = 100,
    this.timeoutMs = 5000,
    this.warmup = 3,
    this.protocol = 'http',
    this.direction = 'download',
  });
  final String scenarioId;
  final int clients;
  final double distanceM;
  final int count;
  final int payloadBytes;
  final int intervalMs;
  final int timeoutMs;
  final int warmup;
  final String protocol;
  final String direction;

  Map<String, Object?> toJson() => {
    'scenario_id': scenarioId,
    'clients': clients,
    'distance_m': distanceM,
    'count': count,
    'payload_bytes': payloadBytes,
    'interval_ms': intervalMs,
    'timeout_ms': timeoutMs,
    'warmup': warmup,
    'protocol': protocol,
    'direction': direction,
  };

  factory TrialConfig.fromJson(Map<String, Object?> data) => TrialConfig(
    scenarioId: data['scenario_id'] as String,
    clients: data['clients'] as int,
    distanceM: (data['distance_m'] as num).toDouble(),
    count: data['count'] as int,
    payloadBytes: data['payload_bytes'] as int? ?? 0,
    intervalMs: data['interval_ms'] as int? ?? 100,
    timeoutMs: data['timeout_ms'] as int? ?? 5000,
    warmup: data['warmup'] as int? ?? 3,
    protocol: data['protocol'] as String? ?? 'http',
    direction: data['direction'] as String? ?? 'download',
  );

  static List<TrialConfig> referenceScenarios({
    int count = 100,
    int multiClients = 4,
  }) => [
    for (var i = 0; i < 6; i++)
      TrialConfig(
        scenarioId: 'E${i + 1}',
        clients: i < 3 ? 1 : multiClients,
        distanceM: [1.0, 6.0, 12.0][i % 3],
        count: count,
      ),
  ];
}

class Measurement {
  const Measurement({
    required this.id,
    required this.sessionId,
    required this.phaseId,
    required this.testId,
    required this.trialId,
    required this.requestId,
    required this.scenarioId,
    required this.clients,
    required this.distanceM,
    required this.timestampUtc,
    required this.success,
    required this.bytesReceived,
    this.bytesSent = 0,
    this.latencyMs,
    this.jitterMs,
    this.speedMbps,
    this.httpStatus,
    this.error,
    this.rssiDbm,
    this.warmup = false,
    this.protocol = 'http',
    this.clientId,
  });
  final String id;
  final String sessionId;
  final String phaseId;
  final String testId;
  final String trialId;
  final String requestId;
  final String scenarioId;
  final int clients;
  final double distanceM;
  final DateTime timestampUtc;
  final bool success;
  final int bytesReceived;
  final int bytesSent;
  final double? latencyMs;
  final double? jitterMs;
  final double? speedMbps;
  final int? httpStatus;
  final String? error;
  final int? rssiDbm;
  final bool warmup;
  final String protocol;
  final String? clientId;

  bool get meetsSla => success && latencyMs != null && latencyMs! < 50;
  bool get severeLag => latencyMs != null && latencyMs! > 50;

  Map<String, Object?> toJson() => {
    'id': id,
    'session_id': sessionId,
    'phase_id': phaseId,
    'test_id': testId,
    'trial_id': trialId,
    'request_id': requestId,
    'id_escenario': scenarioId,
    'clientes': clients,
    'distancia_m': distanceM,
    'rssi_dbm': rssiDbm,
    'latencia_ms': latencyMs,
    'jitter_ms': jitterMs,
    'velocidad_mbps': speedMbps,
    'success': success,
    'exito_sla': meetsSla ? 1 : 0,
    'calidad_red': quality,
    'tipo_anomalia': anomaly,
    'timestamp_utc': timestampUtc.toUtc().toIso8601String(),
    'protocolo': protocol,
    'bytes_recibidos': bytesReceived,
    'bytes_enviados': bytesSent,
    'http_status': httpStatus,
    'error': error,
    'warmup': warmup,
    'client_id': clientId,
  };

  String get quality {
    if (!success) return 'Mala';
    final ms = latencyMs;
    if (ms == null) return 'Sin clasificar';
    if (ms < 20) return 'Excelente';
    if (ms < 50) return 'Buena';
    if (ms < 100) return 'Regular';
    return 'Mala';
  }

  String? get anomaly {
    if (!success) {
      if (error?.toLowerCase().contains('timeout') == true) return 'Timeout';
      if (httpStatus != null) return 'HTTP $httpStatus';
      return 'Error de red';
    }
    if (latencyMs != null && latencyMs! > 100) return 'Spike Severo';
    if (latencyMs != null && latencyMs! > 50) return 'Lag Moderado';
    return null;
  }

  factory Measurement.fromRow(Map<String, Object?> row) => Measurement(
    id: row['id'] as String,
    sessionId: row['session_id'] as String,
    phaseId: row['phase_id'] as String,
    testId: row['test_id'] as String,
    trialId: row['trial_id'] as String,
    requestId: row['request_id'] as String,
    scenarioId: row['scenario_id'] as String,
    clients: row['clients'] as int,
    distanceM: (row['distance_m'] as num).toDouble(),
    timestampUtc: DateTime.parse(row['timestamp_utc'] as String),
    success: (row['success'] as int) == 1,
    bytesReceived: row['bytes_received'] as int,
    bytesSent: row['bytes_sent'] as int? ?? 0,
    latencyMs: (row['latency_ms'] as num?)?.toDouble(),
    jitterMs: (row['jitter_ms'] as num?)?.toDouble(),
    speedMbps: (row['speed_mbps'] as num?)?.toDouble(),
    httpStatus: row['http_status'] as int?,
    error: row['error'] as String?,
    rssiDbm: row['rssi_dbm'] as int?,
    warmup: (row['warmup'] as int) == 1,
    protocol: row['protocol'] as String,
    clientId: row['client_id'] as String?,
  );
}

String encodeConfig(TrialConfig config) => jsonEncode(config.toJson());
