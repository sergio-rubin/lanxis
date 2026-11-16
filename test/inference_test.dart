import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/science/inference.dart';

void main() {
  test('discrete distributions match published reference values', () {
    expect(
      ProbabilityEngine.binomialPmf(20, 5, .2),
      closeTo(.1745595216, 1e-10),
    );
    expect(ProbabilityEngine.poissonPmf(2, 3), closeTo(.2240418077, 1e-10));
    expect(ProbabilityEngine.geometricAttemptsMean(.2), 5);
    expect(ProbabilityEngine.geometricAttemptsMean(0), double.infinity);
  });

  test(
    'large discrete parameters remain finite without factorial overflow',
    () {
      expect(
        ProbabilityEngine.binomialPmf(1000, 500, .5),
        closeTo(.0252250181783608, 1e-12),
      );
      expect(
        ProbabilityEngine.poissonPmf(200, 200),
        closeTo(.028197727685, 1e-10),
      );
      expect(ProbabilityEngine.binomialPmf(0, 0, 0), 1);
      expect(ProbabilityEngine.binomialPmf(20, 20, 1), 1);
      expect(ProbabilityEngine.poissonPmf(0, 0), 1);
    },
  );

  test('normal, t, exponential and chi-square probabilities', () {
    expect(
      ProbabilityEngine.normalArea(-1, 1, 0, 1),
      closeTo(.6826894921, 1e-7),
    );
    expect(ProbabilityEngine.studentCdf(0, 9), closeTo(.5, 1e-10));
    expect(ProbabilityEngine.chiSquareCdf(2, 2), closeTo(.6321205588, 1e-8));
    expect(ProbabilityEngine.exponentialCdf(1, 2), closeTo(.8646647168, 1e-8));
  });

  test('Wilson interval remains within [0,1] for zero successes', () {
    final interval = InferenceEngine.proportionWilson(0, 10);
    expect(interval.lower, 0);
    expect(interval.upper, closeTo(.2775328, 1e-5));
  });

  test('one-sample and Welch tests have coherent decisions', () {
    final one = InferenceEngine.meanGreater([12, 13, 14, 15, 16], 10);
    expect(one.rejectNull, true);
    expect(one.pValue, lessThan(.05));
    final welch = InferenceEngine.welchGreater(
      [12, 13, 14, 15, 16],
      [1, 2, 3, 4, 5],
    );
    expect(welch.rejectNull, true);
    expect(welch.degreesOfFreedom, greaterThan(0));
  });

  test('small proportion sample uses exact binomial tail', () {
    final result = InferenceEngine.slowProportionGreater(1, 10);
    expect(result.method, 'Binomial exacta unilateral');
    expect(result.pValue, closeTo(.6513215599, 1e-9));
    expect(result.rejectNull, false);
    expect(result.warning, isNotNull);
    expect(result.decision, isNotEmpty);
    final stronger = InferenceEngine.slowProportionGreater(4, 10);
    expect(stronger.pValue, closeTo(.0127951984, 1e-9));
    expect(stronger.rejectNull, true);
    final rareEvent = InferenceEngine.slowProportionGreater(
      5,
      1000,
      reference: .001,
    );
    expect(rareEvent.method, 'Binomial exacta unilateral');
    expect(rareEvent.pValue, inInclusiveRange(.003, .004));
    expect(rareEvent.rejectNull, true);
  });
}
