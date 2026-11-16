import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/core/models.dart';
import 'package:lanxis/science/inference.dart';
import 'package:lanxis/science/modeling.dart';

Measurement sample(int seconds, double latency) => Measurement(
  id: '$seconds',
  sessionId: 's',
  phaseId: 'p',
  testId: 't',
  trialId: 'r',
  requestId: 'req-$seconds',
  scenarioId: 'E1',
  clients: 1,
  distanceM: 1,
  timestampUtc: DateTime.utc(2026, 1, 1).add(Duration(seconds: seconds)),
  success: true,
  bytesReceived: 10,
  latencyMs: latency,
);

void main() {
  test('geometric and degenerate Poisson cases match exact values', () {
    expect(ProbabilityEngine.geometricPmf(3, .25), closeTo(.140625, 1e-12));
    expect(ProbabilityEngine.geometricAttemptsMean(.25), 4);
    expect(ProbabilityEngine.geometricFailuresMean(.25), 3);
    expect(ProbabilityEngine.poissonPmf(0, 0), 1);
    expect(ProbabilityEngine.poissonPmf(2, 0), 0);
  });

  test('spike intervals, exponential and Poisson rates use timestamps', () {
    final items = [
      sample(0, 80),
      sample(10, 20),
      sample(20, 90),
      sample(50, 110),
    ];
    expect(EventModels.lagProbability(items), .75);
    expect(EventModels.secondsBetweenSpikes(items), [20, 30]);
    expect(EventModels.exponentialRate(items), closeTo(.04, 1e-12));
    expect(EventModels.spikeRatePerMinute(items), closeTo(3.6, 1e-12));
  });

  test('normal fit requires enough variation and reports a diagnostic', () {
    expect(EventModels.normalFit([1, 2, 3]), isNull);
    expect(EventModels.normalFit(List.filled(10, 4)), isNull);
    final fit = EventModels.normalFit([1, 2, 3, 4, 5, 6, 7, 8]);
    expect(fit, isNotNull);
    expect(fit!.skewness.abs(), lessThan(1e-12));
    expect(fit.pValue, inInclusiveRange(0, 1));
  });
}
