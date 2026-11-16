import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/core/models.dart';
import 'package:lanxis/science/descriptive.dart';

void main() {
  test('mean, sample variance and type-7 quartiles match reference', () {
    final x = DescriptiveEngine.calculate([1, 2, 3, 4]);
    expect(x.mean, closeTo(2.5, 1e-12));
    expect(x.variance, closeTo(5 / 3, 1e-12));
    expect(x.median, 2.5);
    expect(x.q1, 1.75);
    expect(x.q3, 3.25);
    expect(x.modes, isEmpty);
  });

  test('empty, singleton, constant and non-finite samples', () {
    expect(DescriptiveEngine.calculate([]).mean, isNull);
    expect(DescriptiveEngine.calculate([1]).variance, isNull);
    expect(DescriptiveEngine.calculate([2, 2, 2]).variance, 0);
    expect(DescriptiveEngine.calculate([1, double.nan, 3]).n, 2);
  });

  test('frequency table counts all values including upper boundary', () {
    final bins = DescriptiveEngine.frequency([0, 1, 2, 3, 4], classes: 2);
    expect(bins.map((b) => b.frequency), [2, 3]);
    expect(bins.last.cumulativeRelative, 1);
  });

  test('exact 50 ms fails SLA but is not severe lag', () {
    final m = Measurement(
      id: 'm',
      sessionId: 's',
      phaseId: 'p',
      testId: 't',
      trialId: 'r',
      requestId: 'q',
      scenarioId: 'E1',
      clients: 1,
      distanceM: 1,
      timestampUtc: DateTime.utc(2026),
      success: true,
      bytesReceived: 0,
      latencyMs: 50,
    );
    expect(m.meetsSla, false);
    expect(m.severeLag, false);
  });

  test('reference matrix has six scenarios and configurable sample size', () {
    final scenarios = TrialConfig.referenceScenarios(count: 42);
    expect(scenarios.length, 6);
    expect(scenarios.map((s) => s.distanceM), [1, 6, 12, 1, 6, 12]);
    expect(scenarios.every((s) => s.count == 42), true);
  });
}
