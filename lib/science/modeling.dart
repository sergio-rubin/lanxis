import 'dart:math';

import '../core/models.dart';
import 'descriptive.dart';
import 'inference.dart';

class NormalFit {
  const NormalFit({
    required this.n,
    required this.mean,
    required this.standardDeviation,
    required this.skewness,
    required this.excessKurtosis,
    required this.jarqueBera,
    required this.pValue,
  });
  final int n;
  final double mean;
  final double standardDeviation;
  final double skewness;
  final double excessKurtosis;
  final double jarqueBera;
  final double pValue;

  String get interpretation => pValue < .05
      ? 'El diagnóstico rechaza la normalidad aproximada al 5%. No use la normal como descripción confirmada.'
      : 'El diagnóstico no detecta una desviación fuerte; esto no demuestra normalidad.';
}

class EventModels {
  static double? lagProbability(Iterable<Measurement> input) {
    final items = input.where((m) => !m.warmup).toList();
    if (items.isEmpty) return null;
    return items.where((m) => m.severeLag).length / items.length;
  }

  static List<double> secondsBetweenSpikes(Iterable<Measurement> input) {
    final times =
        input
            .where((m) => !m.warmup && m.severeLag)
            .map((m) => m.timestampUtc.toUtc())
            .toList()
          ..sort();
    final intervals = <double>[];
    for (var i = 1; i < times.length; i++) {
      final value = times[i].difference(times[i - 1]).inMicroseconds / 1e6;
      if (value > 0) intervals.add(value);
    }
    return intervals;
  }

  static double? exponentialRate(Iterable<Measurement> input) {
    final intervals = secondsBetweenSpikes(input);
    if (intervals.isEmpty) return null;
    return 1 / (intervals.reduce((a, b) => a + b) / intervals.length);
  }

  static double? spikeRatePerMinute(Iterable<Measurement> input) {
    final items = input.where((m) => !m.warmup).toList();
    if (items.length < 2) return null;
    items.sort((a, b) => a.timestampUtc.compareTo(b.timestampUtc));
    final minutes =
        items.last.timestampUtc
            .difference(items.first.timestampUtc)
            .inMicroseconds /
        60000000;
    if (minutes <= 0) return null;
    return items.where((m) => m.severeLag).length / minutes;
  }

  static NormalFit? normalFit(Iterable<double> input) {
    final values = input.where((x) => x.isFinite).toList();
    if (values.length < 8) return null;
    final stats = DescriptiveEngine.calculate(values);
    if (stats.standardDeviation == null || stats.standardDeviation == 0) {
      return null;
    }
    final n = values.length;
    final mean = stats.mean!;
    final populationSd = sqrt(
      values.fold<double>(0, (sum, x) => sum + pow(x - mean, 2).toDouble()) / n,
    );
    if (populationSd == 0) return null;
    final skew =
        values.fold<double>(
          0,
          (sum, x) => sum + pow((x - mean) / populationSd, 3).toDouble(),
        ) /
        n;
    final kurtosis =
        values.fold<double>(
              0,
              (sum, x) => sum + pow((x - mean) / populationSd, 4).toDouble(),
            ) /
            n -
        3;
    final jb = n / 6 * (skew * skew + kurtosis * kurtosis / 4);
    return NormalFit(
      n: n,
      mean: mean,
      standardDeviation: stats.standardDeviation!,
      skewness: skew,
      excessKurtosis: kurtosis,
      jarqueBera: jb,
      pValue: 1 - ProbabilityEngine.chiSquareCdf(jb, 2),
    );
  }
}
