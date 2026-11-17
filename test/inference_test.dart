import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/science/inference.dart';

void main() {
  test('Dart probabilities and inference match generated SciPy cases', () {
    final reference = jsonDecode(
      File('test/fixtures/scipy_reference.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    double expected(String key) => (reference[key] as num).toDouble();
    List<double> interval(String key) => (reference[key] as List)
        .map((value) => (value as num).toDouble())
        .toList();

    expect(
      ProbabilityEngine.binomialPmf(20, 5, .2),
      closeTo(expected('binomial_pmf_20_5_p02'), 1e-10),
    );
    expect(
      ProbabilityEngine.binomialCdf(20, 5, .2),
      closeTo(expected('binomial_cdf_20_5_p02'), 1e-9),
    );
    expect(
      ProbabilityEngine.poissonCdf(2, 3),
      closeTo(expected('poisson_cdf_k2_lambda3'), 1e-9),
    );
    expect(
      ProbabilityEngine.studentCdf(1.83, 9),
      closeTo(expected('student_cdf_t183_df9'), 1e-7),
    );
    expect(
      ProbabilityEngine.chiSquareCdf(13.2, 6),
      closeTo(expected('chi_square_cdf_x132_df6'), 1e-7),
    );
    expect(
      ProbabilityEngine.normalArea(20, 50, 32, 12),
      closeTo(expected('normal_area_20_50_mu32_sd12'), 1e-7),
    );
    expect(
      ProbabilityEngine.exponentialCdf(3.4, .7),
      closeTo(expected('exponential_cdf_x34_rate07'), 1e-7),
    );

    final values = [5.0, 8.0, 9.0, 10.0, 12.0];
    final meanCi = InferenceEngine.meanInterval(values);
    final expectedMeanCi = interval('mean_ci95_sample');
    expect(meanCi.lower, closeTo(expectedMeanCi[0], 1e-6));
    expect(meanCi.upper, closeTo(expectedMeanCi[1], 1e-6));
    final wilson = InferenceEngine.proportionWilson(7, 20);
    final expectedWilson = interval('wilson_ci95_7_of_20');
    expect(wilson.lower, closeTo(expectedWilson[0], 1e-6));
    expect(wilson.upper, closeTo(expectedWilson[1], 1e-6));

    final welch = InferenceEngine.welchGreater(
      [12, 13, 14, 15, 16],
      [1, 2, 3, 4, 5],
    );
    expect(welch.statistic, closeTo(expected('welch_greater_statistic'), 1e-8));
    expect(welch.pValue, closeTo(expected('welch_greater_pvalue'), 1e-7));
    final variance = InferenceEngine.varianceGreater(values, 4);
    expect(
      variance.statistic,
      closeTo(expected('variance_greater_statistic'), 1e-8),
    );
    expect(variance.pValue, closeTo(expected('variance_greater_pvalue'), 1e-7));
    expect(
      InferenceEngine.slowProportionGreater(4, 10).pValue,
      closeTo(expected('exact_proportion_greater_4_of_10_p01'), 1e-9),
    );
  });

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
      expect(
        ProbabilityEngine.binomialCdf(20, 5, .2),
        closeTo(.8042077855, 1e-9),
      );
      expect(ProbabilityEngine.poissonCdf(2, 3), closeTo(.4231900811, 1e-9));
      expect(
        ProbabilityEngine.binomialCdf(1000, 500, .5),
        inInclusiveRange(.50, .52),
      );
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
