import 'dart:math';

import '../core/models.dart';

class FrequencyClass {
  const FrequencyClass(
    this.lower,
    this.upper,
    this.midpoint,
    this.frequency,
    this.relative,
    this.cumulative,
    this.cumulativeRelative,
  );
  final double lower;
  final double upper;
  final double midpoint;
  final int frequency;
  final double relative;
  final int cumulative;
  final double cumulativeRelative;
}

class DescriptiveStats {
  const DescriptiveStats({
    required this.n,
    required this.mean,
    required this.median,
    required this.minimum,
    required this.maximum,
    required this.q1,
    required this.q3,
    required this.variance,
    required this.standardDeviation,
    required this.p90,
    required this.p95,
    required this.p99,
    required this.mad,
    required this.outlierCount,
    required this.modes,
  });
  final int n;
  final double? mean;
  final double? median;
  final double? minimum;
  final double? maximum;
  final double? q1;
  final double? q3;
  final double? variance;
  final double? standardDeviation;
  final double? p90;
  final double? p95;
  final double? p99;
  final double? mad;
  final int outlierCount;
  final List<double> modes;

  double? get range => minimum == null ? null : maximum! - minimum!;
  double? get iqr => q1 == null ? null : q3! - q1!;
  double? get coefficientOfVariation =>
      mean == null || mean == 0 || standardDeviation == null
      ? null
      : standardDeviation! / mean!;
  double? get standardError =>
      standardDeviation == null ? null : standardDeviation! / sqrt(n);
}

class DescriptiveEngine {
  static DescriptiveStats calculate(Iterable<double> input) {
    final values = input.where((x) => x.isFinite).toList()..sort();
    final n = values.length;
    if (n == 0) {
      return const DescriptiveStats(
        n: 0,
        mean: null,
        median: null,
        minimum: null,
        maximum: null,
        q1: null,
        q3: null,
        variance: null,
        standardDeviation: null,
        p90: null,
        p95: null,
        p99: null,
        mad: null,
        outlierCount: 0,
        modes: [],
      );
    }
    var mean = 0.0;
    var m2 = 0.0;
    for (var i = 0; i < n; i++) {
      final delta = values[i] - mean;
      mean += delta / (i + 1);
      m2 += delta * (values[i] - mean);
    }
    final median = percentile(values, .5);
    final q1 = percentile(values, .25);
    final q3 = percentile(values, .75);
    final iqr = q3 - q1;
    final lowFence = q1 - 1.5 * iqr;
    final highFence = q3 + 1.5 * iqr;
    final deviations = values.map((v) => (v - median).abs()).toList()..sort();
    final counts = <double, int>{};
    for (final value in values) {
      counts[value] = (counts[value] ?? 0) + 1;
    }
    final maxCount = counts.values.reduce(max);
    final modes = maxCount == 1
        ? <double>[]
        : counts.entries
              .where((entry) => entry.value == maxCount)
              .map((entry) => entry.key)
              .toList();
    final variance = n > 1 ? m2 / (n - 1) : null;
    return DescriptiveStats(
      n: n,
      mean: mean,
      median: median,
      minimum: values.first,
      maximum: values.last,
      q1: q1,
      q3: q3,
      variance: variance,
      standardDeviation: variance == null ? null : sqrt(variance),
      p90: percentile(values, .9),
      p95: percentile(values, .95),
      p99: percentile(values, .99),
      mad: percentile(deviations, .5),
      outlierCount: values.where((v) => v < lowFence || v > highFence).length,
      modes: modes,
    );
  }

  /// Type-7 linear interpolation, used by R and NumPy's default method.
  static double percentile(List<double> sorted, double p) {
    if (sorted.isEmpty || p < 0 || p > 1) {
      throw ArgumentError('Percentil inválido');
    }
    final position = (sorted.length - 1) * p;
    final low = position.floor();
    final high = position.ceil();
    return sorted[low] + (sorted[high] - sorted[low]) * (position - low);
  }

  static List<FrequencyClass> frequency(
    Iterable<double> input, {
    int classes = 7,
  }) {
    if (classes < 1 || classes > 100) throw ArgumentError.value(classes);
    final values = input.where((x) => x.isFinite).toList()..sort();
    if (values.isEmpty) return [];
    final low = values.first;
    final high = values.last;
    final width = high == low ? 1.0 : (high - low) / classes;
    final counts = List<int>.filled(classes, 0);
    for (final value in values) {
      final index = min(classes - 1, ((value - low) / width).floor());
      counts[index]++;
    }
    var cumulative = 0;
    return List.generate(classes, (i) {
      cumulative += counts[i];
      final lower = low + i * width;
      final upper = low + (i + 1) * width;
      return FrequencyClass(
        lower,
        upper,
        (lower + upper) / 2,
        counts[i],
        counts[i] / values.length,
        cumulative,
        cumulative / values.length,
      );
    });
  }

  static Map<String, DescriptiveStats> byScenario(Iterable<Measurement> items) {
    final groups = <String, List<double>>{};
    for (final item in items) {
      if (!item.warmup && item.success && item.latencyMs != null) {
        groups.putIfAbsent(item.scenarioId, () => []).add(item.latencyMs!);
      }
    }
    return groups.map((key, values) => MapEntry(key, calculate(values)));
  }

  static double? successRate(Iterable<Measurement> items) {
    final values = items.where((item) => !item.warmup).toList();
    if (values.isEmpty) return null;
    return values.where((item) => item.meetsSla).length / values.length;
  }

  static double? conditionalLagMulticlient(Iterable<Measurement> items) {
    final multi = items.where((m) => !m.warmup && m.clients > 1).toList();
    if (multi.isEmpty) return null;
    return multi.where((m) => m.severeLag).length / multi.length;
  }

  static Map<double, double> criticalDistancePosterior(
    Iterable<Measurement> items,
  ) {
    final values = items.where((m) => !m.warmup).toList();
    final critical = values
        .where(
          (m) =>
              m.distanceM != null && (!m.success || (m.latencyMs ?? 0) > 100),
        )
        .toList();
    if (critical.isEmpty) return {};
    final counts = <double, int>{};
    for (final item in critical) {
      final distance = item.distanceM!;
      counts[distance] = (counts[distance] ?? 0) + 1;
    }
    return counts.map((key, count) => MapEntry(key, count / critical.length));
  }
}
