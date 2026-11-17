import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/data/lab_repository.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('version 5 pending outbox migrates without losing old results', () {
    final directory = Directory.systemTemp.createTempSync('lanxis-outbox-v5-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/legacy.sqlite');
    final db = sqlite3.open(file.path);
    db.execute('''
      CREATE TABLE result_outbox (
        id TEXT PRIMARY KEY, server_url TEXT NOT NULL,
        payload_json TEXT NOT NULL, created_utc TEXT NOT NULL
      );
      INSERT INTO result_outbox VALUES ('old', 'http://127.0.0.1:8040', '{"job_id":"j"}', '2026-11-16T00:00:00Z');
      PRAGMA user_version = 5;
    ''');
    db.close();
    final repo = LabRepository.openAt(file);
    addTearDown(repo.dispose);
    expect(repo.pendingResultCount, 1);
    repo.markResultRejected('old');
    expect(repo.pendingResultCount, 0);
    expect(repo.rejectedResultCount, 1);
  });

  test('version 4 measurements migrate without losing observations', () {
    final directory = Directory.systemTemp.createTempSync('lanxis-migration-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/legacy.sqlite');
    final db = sqlite3.open(file.path);
    db.execute('''
      CREATE TABLE measurements (
        id TEXT PRIMARY KEY, session_id TEXT NOT NULL,
        phase_id TEXT NOT NULL, test_id TEXT NOT NULL,
        trial_id TEXT NOT NULL, request_id TEXT NOT NULL UNIQUE,
        scenario_id TEXT NOT NULL, clients INTEGER NOT NULL,
        distance_m REAL NOT NULL, timestamp_utc TEXT NOT NULL,
        protocol TEXT NOT NULL, latency_ms REAL, jitter_ms REAL,
        speed_mbps REAL, bytes_received INTEGER NOT NULL,
        success INTEGER NOT NULL, http_status INTEGER, error TEXT,
        rssi_dbm INTEGER, warmup INTEGER NOT NULL DEFAULT 0,
        client_id TEXT, bytes_sent INTEGER NOT NULL DEFAULT 0
      );
      INSERT INTO measurements (
        id, session_id, phase_id, test_id, trial_id, request_id,
        scenario_id, clients, distance_m, timestamp_utc, protocol,
        latency_ms, bytes_received, success
      ) VALUES (
        'm1', 's1', 'p1', 't1', 'r1', 'req1', 'E1', 1, 6,
        '2026-11-16T00:00:00Z', 'http', 12.5, 1, 1
      );
      PRAGMA user_version = 4;
    ''');
    db.close();
    final repo = LabRepository.openAt(file);
    addTearDown(repo.dispose);
    final item = repo.measurements('s1').single;
    expect(item.latencyMs, 12.5);
    expect(item.distanceM, 6);
    expect(item.distanceSource, 'legacy_unverified');
    expect(repo.scenarioTemplates(), isEmpty);
  });
}
