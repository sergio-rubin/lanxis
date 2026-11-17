import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../core/models.dart';

class LabRepository {
  LabRepository._(this._db);
  final Database _db;
  static const _uuid = Uuid();

  static Future<LabRepository> open() async {
    final root = await getApplicationSupportDirectory();
    await root.create(recursive: true);
    return openAt(File('${root.path}${Platform.pathSeparator}lanxis.sqlite'));
  }

  static LabRepository openAt(File file) {
    final db = sqlite3.open(file.path);
    final repository = LabRepository._(db);
    repository._migrate();
    return repository;
  }

  static LabRepository inMemory() {
    final repository = LabRepository._(sqlite3.openInMemory());
    repository._migrate();
    return repository;
  }

  void _migrate() {
    _db.execute('PRAGMA foreign_keys = ON');
    _db.execute('PRAGMA journal_mode = WAL');
    final version = _db.select('PRAGMA user_version').first.values.first as int;
    if (version < 1) {
      _db.execute('BEGIN IMMEDIATE');
      try {
        _db.execute('''
        CREATE TABLE sessions (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, created_utc TEXT NOT NULL,
          status TEXT NOT NULL, notes TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE phases (
          id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(id),
          name TEXT NOT NULL, created_utc TEXT NOT NULL, status TEXT NOT NULL
        );
        CREATE TABLE tests (
          id TEXT PRIMARY KEY, phase_id TEXT NOT NULL REFERENCES phases(id),
          name TEXT NOT NULL, config_json TEXT NOT NULL, created_utc TEXT NOT NULL
        );
        CREATE TABLE trials (
          id TEXT PRIMARY KEY, test_id TEXT NOT NULL REFERENCES tests(id),
          started_utc TEXT NOT NULL, finished_utc TEXT, status TEXT NOT NULL
        );
        CREATE TABLE measurements (
          id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(id),
          phase_id TEXT NOT NULL REFERENCES phases(id),
          test_id TEXT NOT NULL REFERENCES tests(id),
          trial_id TEXT NOT NULL REFERENCES trials(id),
          request_id TEXT NOT NULL UNIQUE, scenario_id TEXT NOT NULL,
          clients INTEGER NOT NULL, distance_m REAL NOT NULL,
          timestamp_utc TEXT NOT NULL, protocol TEXT NOT NULL,
          latency_ms REAL, jitter_ms REAL, speed_mbps REAL,
          bytes_received INTEGER NOT NULL, success INTEGER NOT NULL,
          http_status INTEGER, error TEXT, rssi_dbm INTEGER,
          warmup INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE events (
          id TEXT PRIMARY KEY, session_id TEXT REFERENCES sessions(id),
          phase_id TEXT REFERENCES phases(id), test_id TEXT REFERENCES tests(id),
          trial_id TEXT REFERENCES trials(id), timestamp_utc TEXT NOT NULL,
          type TEXT NOT NULL, severity TEXT NOT NULL, origin TEXT NOT NULL,
          metadata_json TEXT NOT NULL DEFAULT '{}'
        );
        CREATE INDEX idx_phases_session ON phases(session_id);
        CREATE INDEX idx_measurements_session_time ON measurements(session_id, timestamp_utc);
        CREATE INDEX idx_measurements_trial ON measurements(trial_id);
        CREATE INDEX idx_events_session_time ON events(session_id, timestamp_utc);
      ''');
        _db.execute('PRAGMA user_version = 1');
        _db.execute('COMMIT');
      } catch (_) {
        _db.execute('ROLLBACK');
        rethrow;
      }
    }
    if (version < 2) {
      _db.execute('BEGIN IMMEDIATE');
      try {
        _db.execute('ALTER TABLE measurements ADD COLUMN client_id TEXT');
        _db.execute(
          'CREATE INDEX idx_measurements_client ON measurements(client_id)',
        );
        _db.execute('PRAGMA user_version = 2');
        _db.execute('COMMIT');
      } catch (_) {
        _db.execute('ROLLBACK');
        rethrow;
      }
    }
    if (version < 3) {
      _db.execute('BEGIN IMMEDIATE');
      try {
        _db.execute(
          'ALTER TABLE measurements ADD COLUMN bytes_sent INTEGER NOT NULL DEFAULT 0',
        );
        _db.execute('PRAGMA user_version = 3');
        _db.execute('COMMIT');
      } catch (_) {
        _db.execute('ROLLBACK');
        rethrow;
      }
    }
    if (version < 4) {
      _db.execute('BEGIN IMMEDIATE');
      try {
        _db.execute('''
          CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
          CREATE TABLE result_outbox (
            id TEXT PRIMARY KEY, server_url TEXT NOT NULL,
            payload_json TEXT NOT NULL, created_utc TEXT NOT NULL
          );
          CREATE INDEX idx_result_outbox_server ON result_outbox(server_url, created_utc);
        ''');
        _db.execute('PRAGMA user_version = 4');
        _db.execute('COMMIT');
      } catch (_) {
        _db.execute('ROLLBACK');
        rethrow;
      }
    }
    if (version < 5) {
      _db.execute('PRAGMA foreign_keys = OFF');
      _db.execute('BEGIN IMMEDIATE');
      try {
        _db.execute('''
          ALTER TABLE measurements RENAME TO measurements_legacy;
          CREATE TABLE measurements (
            id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(id),
            phase_id TEXT NOT NULL REFERENCES phases(id),
            test_id TEXT NOT NULL REFERENCES tests(id),
            trial_id TEXT NOT NULL REFERENCES trials(id),
            request_id TEXT NOT NULL UNIQUE, scenario_id TEXT NOT NULL,
            clients INTEGER NOT NULL, distance_m REAL,
            distance_source TEXT NOT NULL DEFAULT 'unknown',
            distance_uncertainty_m REAL,
            target_distance_m REAL, environment TEXT NOT NULL DEFAULT 'unknown',
            timestamp_utc TEXT NOT NULL, protocol TEXT NOT NULL,
            latency_ms REAL, jitter_ms REAL, speed_mbps REAL,
            bytes_received INTEGER NOT NULL, bytes_sent INTEGER NOT NULL DEFAULT 0,
            success INTEGER NOT NULL, http_status INTEGER, error TEXT,
            rssi_dbm INTEGER, warmup INTEGER NOT NULL DEFAULT 0,
            client_id TEXT
          );
          INSERT INTO measurements (
            id, session_id, phase_id, test_id, trial_id, request_id,
            scenario_id, clients, distance_m, distance_source,
            timestamp_utc, protocol, latency_ms, jitter_ms, speed_mbps,
            bytes_received, bytes_sent, success, http_status, error,
            rssi_dbm, warmup, client_id
          ) SELECT
            id, session_id, phase_id, test_id, trial_id, request_id,
            scenario_id, clients, NULLIF(distance_m, 0), 'legacy_unverified',
            timestamp_utc, protocol, latency_ms, jitter_ms, speed_mbps,
            bytes_received, bytes_sent, success, http_status, error,
            rssi_dbm, warmup, client_id
          FROM measurements_legacy;
          DROP TABLE measurements_legacy;
          CREATE INDEX idx_measurements_session_time ON measurements(session_id, timestamp_utc);
          CREATE INDEX idx_measurements_trial ON measurements(trial_id);
          CREATE INDEX idx_measurements_client ON measurements(client_id);
          CREATE TABLE scenario_templates (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, data_json TEXT NOT NULL,
            created_utc TEXT NOT NULL
          );
        ''');
        _db.execute('PRAGMA user_version = 5');
        _db.execute('COMMIT');
      } catch (_) {
        _db.execute('ROLLBACK');
        rethrow;
      } finally {
        _db.execute('PRAGMA foreign_keys = ON');
      }
    }
  }

  String get clientIdentity {
    final rows = _db.select(
      "SELECT value FROM app_settings WHERE key = 'client_id'",
    );
    if (rows.isNotEmpty) return rows.first['value'] as String;
    final id = _uuid.v4();
    _db.execute('INSERT INTO app_settings (key, value) VALUES (?, ?)', [
      'client_id',
      id,
    ]);
    return id;
  }

  String queueResult(String serverUrl, String payloadJson) {
    final id = _uuid.v4();
    _db.execute(
      'INSERT INTO result_outbox (id, server_url, payload_json, created_utc) VALUES (?, ?, ?, ?)',
      [id, serverUrl, payloadJson, DateTime.now().toUtc().toIso8601String()],
    );
    return id;
  }

  List<Map<String, Object?>> pendingResults(String serverUrl) => _db
      .select(
        'SELECT * FROM result_outbox WHERE server_url = ? ORDER BY created_utc, rowid',
        [serverUrl],
      )
      .map((row) => Map<String, Object?>.from(row))
      .toList();

  int get pendingResultCount =>
      _db.select('SELECT COUNT(*) AS n FROM result_outbox').first['n'] as int;

  List<ScenarioTemplate> scenarioTemplates() => _db
      .select('SELECT * FROM scenario_templates ORDER BY created_utc DESC')
      .map(ScenarioTemplate.fromRow)
      .toList();

  ScenarioTemplate saveScenarioTemplate(
    String name,
    TrialConfig config, {
    bool autoClients = false,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('El nombre es obligatorio');
    final id = 'custom-${_uuid.v4()}';
    final item = ScenarioTemplate(
      id: id,
      name: trimmed,
      config: config.withScenario(id),
      autoClients: autoClients,
    );
    _db.execute(
      'INSERT INTO scenario_templates '
      '(id, name, data_json, created_utc) VALUES (?, ?, ?, ?)',
      [
        id,
        trimmed,
        jsonEncode(item.toJson()),
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
    return item;
  }

  void deleteScenarioTemplate(String id) =>
      _db.execute('DELETE FROM scenario_templates WHERE id = ?', [id]);

  void acknowledgeResult(String id) =>
      _db.execute('DELETE FROM result_outbox WHERE id = ?', [id]);

  List<LabSession> sessions() => _db
      .select('SELECT * FROM sessions ORDER BY created_utc DESC')
      .map(LabSession.fromRow)
      .toList();

  List<LabPhase> phases(String sessionId) => _db
      .select(
        'SELECT * FROM phases WHERE session_id = ? ORDER BY created_utc',
        [sessionId],
      )
      .map(LabPhase.fromRow)
      .toList();

  LabSession createSession(String name, {String notes = ''}) {
    final item = LabSession(
      id: _uuid.v4(),
      name: name.trim(),
      createdAt: DateTime.now().toUtc(),
      notes: notes,
    );
    if (item.name.isEmpty) {
      throw ArgumentError('El nombre de sesión es obligatorio');
    }
    _db.execute(
      'INSERT INTO sessions (id, name, created_utc, status, notes) VALUES (?, ?, ?, ?, ?)',
      [
        item.id,
        item.name,
        item.createdAt.toIso8601String(),
        item.status,
        item.notes,
      ],
    );
    addEvent('session_created', sessionId: item.id);
    return item;
  }

  LabPhase createPhase(String sessionId, String name) {
    final item = LabPhase(
      id: _uuid.v4(),
      sessionId: sessionId,
      name: name.trim(),
      createdAt: DateTime.now().toUtc(),
    );
    if (item.name.isEmpty) {
      throw ArgumentError('El nombre de fase es obligatorio');
    }
    _db.execute(
      'INSERT INTO phases (id, session_id, name, created_utc, status) VALUES (?, ?, ?, ?, ?)',
      [
        item.id,
        item.sessionId,
        item.name,
        item.createdAt.toIso8601String(),
        item.status,
      ],
    );
    addEvent('phase_created', sessionId: sessionId, phaseId: item.id);
    return item;
  }

  String createTest(String phaseId, String name, TrialConfig config) {
    final id = _uuid.v4();
    _db.execute(
      'INSERT INTO tests (id, phase_id, name, config_json, created_utc) VALUES (?, ?, ?, ?, ?)',
      [
        id,
        phaseId,
        name.trim(),
        encodeConfig(config),
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
    return id;
  }

  String startTrial(String testId) {
    final id = _uuid.v4();
    _db.execute(
      'INSERT INTO trials (id, test_id, started_utc, status) VALUES (?, ?, ?, ?)',
      [id, testId, DateTime.now().toUtc().toIso8601String(), 'running'],
    );
    return id;
  }

  void finishTrial(String trialId, String status) {
    _db.execute('UPDATE trials SET finished_utc = ?, status = ? WHERE id = ?', [
      DateTime.now().toUtc().toIso8601String(),
      status,
      trialId,
    ]);
  }

  void addMeasurement(Measurement item) {
    _db.execute(
      '''INSERT OR IGNORE INTO measurements (
      id, session_id, phase_id, test_id, trial_id, request_id,
      scenario_id, clients, distance_m, distance_source,
      distance_uncertainty_m,
      target_distance_m, environment, timestamp_utc, protocol,
      latency_ms, jitter_ms, speed_mbps, bytes_received, success,
      http_status, error, rssi_dbm, warmup, client_id, bytes_sent
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        item.id,
        item.sessionId,
        item.phaseId,
        item.testId,
        item.trialId,
        item.requestId,
        item.scenarioId,
        item.clients,
        item.distanceM,
        item.distanceSource,
        item.distanceUncertaintyM,
        item.targetDistanceM,
        item.environment,
        item.timestampUtc.toUtc().toIso8601String(),
        item.protocol,
        item.latencyMs,
        item.jitterMs,
        item.speedMbps,
        item.bytesReceived,
        item.success ? 1 : 0,
        item.httpStatus,
        item.error,
        item.rssiDbm,
        item.warmup ? 1 : 0,
        item.clientId,
        item.bytesSent,
      ],
    );
  }

  List<Measurement> measurements(
    String sessionId, {
    bool includeWarmup = false,
  }) => _db
      .select(
        'SELECT * FROM measurements WHERE session_id = ? ${includeWarmup ? '' : 'AND warmup = 0'} ORDER BY timestamp_utc',
        [sessionId],
      )
      .map(Measurement.fromRow)
      .toList();

  List<Map<String, Object?>> testsForSession(String sessionId) => _db
      .select(
        '''SELECT t.* FROM tests t JOIN phases p ON t.phase_id = p.id
        WHERE p.session_id = ? ORDER BY t.created_utc''',
        [sessionId],
      )
      .map((row) => Map<String, Object?>.from(row))
      .toList();

  List<Map<String, Object?>> trialsForSession(String sessionId) => _db
      .select(
        '''SELECT r.* FROM trials r JOIN tests t ON r.test_id = t.id
        JOIN phases p ON t.phase_id = p.id WHERE p.session_id = ?
        ORDER BY r.started_utc''',
        [sessionId],
      )
      .map((row) => Map<String, Object?>.from(row))
      .toList();

  List<Map<String, Object?>> eventsForSession(String sessionId) => _db
      .select(
        'SELECT * FROM events WHERE session_id = ? ORDER BY timestamp_utc',
        [sessionId],
      )
      .map((row) => Map<String, Object?>.from(row))
      .toList();

  int measurementCount(String sessionId) =>
      _db.select(
            'SELECT COUNT(*) AS n FROM measurements WHERE session_id = ? AND warmup = 0',
            [sessionId],
          ).first['n']
          as int;

  int trialMeasurementCount(String trialId) =>
      _db.select(
            'SELECT COUNT(*) AS n FROM measurements WHERE trial_id = ? AND warmup = 0',
            [trialId],
          ).first['n']
          as int;

  void updateSessionStatus(String id, String status) {
    if (!{'active', 'paused', 'finished'}.contains(status)) {
      throw ArgumentError.value(status);
    }
    _db.execute('UPDATE sessions SET status = ? WHERE id = ?', [status, id]);
    addEvent('session_$status', sessionId: id);
  }

  void updatePhaseStatus(String sessionId, String phaseId, String status) {
    if (!{'active', 'paused', 'finished'}.contains(status)) {
      throw ArgumentError.value(status);
    }
    _db.execute(
      'UPDATE phases SET status = ? WHERE id = ? AND session_id = ?',
      [status, phaseId, sessionId],
    );
    addEvent('phase_$status', sessionId: sessionId, phaseId: phaseId);
  }

  void addEvent(
    String type, {
    String? sessionId,
    String? phaseId,
    String? testId,
    String? trialId,
    String severity = 'info',
    String origin = 'local',
    String metadataJson = '{}',
  }) {
    _db.execute(
      'INSERT INTO events (id, session_id, phase_id, test_id, trial_id, timestamp_utc, type, severity, origin, metadata_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        _uuid.v4(),
        sessionId,
        phaseId,
        testId,
        trialId,
        DateTime.now().toUtc().toIso8601String(),
        type,
        severity,
        origin,
        metadataJson,
      ],
    );
  }

  void dispose() => _db.close();
}
