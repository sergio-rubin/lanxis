import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/core/models.dart';
import 'package:lanxis/science/session_comparison.dart';

void main() {
  final now = DateTime.utc(2026, 11, 17);
  LabSession session(String id) =>
      LabSession(id: id, name: 'Sesión $id', createdAt: now);
  Measurement sample(
    String id,
    String sessionId,
    double? latency, {
    String protocol = 'http',
    String scenario = 'E1',
    String clientId = 'cliente-1',
  }) => Measurement(
    id: id,
    sessionId: sessionId,
    phaseId: 'phase-$sessionId',
    testId: 'test-$sessionId',
    trialId: 'trial-$sessionId',
    requestId: 'request-$id',
    scenarioId: scenario,
    clients: 1,
    timestampUtc: now,
    success: latency != null,
    bytesReceived: 0,
    latencyMs: latency,
    protocol: protocol,
    clientId: clientId,
  );

  test('pool raw observations instead of averaging session means', () {
    final comparison = SessionComparison([
      (session: session('a'), items: [sample('a1', 'a', 10)]),
      (
        session: session('b'),
        items: [
          sample('b1', 'b', 20),
          sample('b2', 'b', 30),
          sample('b3', 'b', null),
        ],
      ),
    ]);
    expect(comparison.pooled.total, 4);
    expect(comparison.pooled.valid, 3);
    expect(comparison.pooled.stats.mean, 20);
    expect(comparison.pooled.sla, .75);
    expect(
      (comparison.toJson()['sessions']
          as List)[1]['mean_difference_from_baseline_ms'],
      15,
    );
    expect(
      comparison.toJson(includeMeasurements: true).toString(),
      contains('request-b3'),
    );
  });

  test('warn when protocols, scenarios and clients overlap', () {
    final comparison = SessionComparison([
      (session: session('a'), items: [sample('a1', 'a', 10)]),
      (
        session: session('b'),
        items: [sample('b1', 'b', 20, protocol: 'tcp', scenario: 'E4')],
      ),
    ]);
    expect(comparison.warnings.join(' '), contains('protocolos'));
    expect(comparison.warnings.join(' '), contains('escenarios'));
    expect(comparison.warnings.join(' '), contains('mismo cliente'));
  });

  test('reject duplicate or solitary sessions', () {
    expect(
      () =>
          SessionComparison([(session: session('a'), items: <Measurement>[])]),
      throwsArgumentError,
    );
    expect(
      () => SessionComparison([
        (session: session('a'), items: <Measurement>[]),
        (session: session('a'), items: <Measurement>[]),
      ]),
      throwsArgumentError,
    );
  });
}
