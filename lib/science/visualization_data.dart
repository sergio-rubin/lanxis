import 'dart:math';

import '../core/models.dart';
import 'descriptive.dart';

class PolygonSeries {
  const PolygonSeries(this.label, this.bins);
  final String label;
  final List<FrequencyClass> bins;
}

class BoxSummary {
  const BoxSummary(
    this.label,
    this.minimumWhisker,
    this.q1,
    this.median,
    this.q3,
    this.maximumWhisker,
    this.outliers,
  );
  final String label;
  final double minimumWhisker;
  final double q1;
  final double median;
  final double q3;
  final double maximumWhisker;
  final List<double> outliers;
}

class ParetoCategory {
  const ParetoCategory(this.label, this.count, this.cumulative);
  final String label;
  final int count;
  final double cumulative;
}

class VisualizationData {
  static List<PolygonSeries> polygons(
    Map<String, List<double>> groups, {
    int classes = 7,
  }) {
    final all = groups.values
        .expand((values) => values)
        .where((x) => x.isFinite)
        .toList();
    if (all.isEmpty) return [];
    if (classes < 1 || classes > 100) throw ArgumentError.value(classes);
    final low = all.reduce(min);
    final high = all.reduce(max);
    final width = high == low ? 1.0 : (high - low) / classes;
    return [
      for (final entry in groups.entries)
        PolygonSeries(entry.key, _bins(entry.value, low, width, classes)),
    ];
  }

  static List<FrequencyClass> _bins(
    List<double> values,
    double low,
    double width,
    int classes,
  ) {
    final counts = List<int>.filled(classes, 0);
    final finite = values.where((x) => x.isFinite).toList();
    for (final value in finite) {
      counts[min(classes - 1, ((value - low) / width).floor())]++;
    }
    var cumulative = 0;
    return [
      for (var i = 0; i < classes; i++)
        (() {
          cumulative += counts[i];
          final lower = low + width * i;
          final upper = lower + width;
          return FrequencyClass(
            lower,
            upper,
            (lower + upper) / 2,
            counts[i],
            finite.isEmpty ? 0 : counts[i] / finite.length,
            cumulative,
            finite.isEmpty ? 0 : cumulative / finite.length,
          );
        })(),
    ];
  }

  static double? fractionBelow(Iterable<double> values, double threshold) {
    final finite = values.where((x) => x.isFinite).toList();
    if (finite.isEmpty) return null;
    return finite.where((x) => x < threshold).length / finite.length;
  }

  static Map<String, BoxSummary> boxes(Iterable<Measurement> input) {
    final groups = <String, List<double>>{};
    for (final m in input) {
      if (m.success && !m.warmup && m.latencyMs != null) {
        groups.putIfAbsent(m.scenarioId, () => []).add(m.latencyMs!);
      }
    }
    final result = <String, BoxSummary>{};
    for (final entry in groups.entries) {
      final values = entry.value..sort();
      final stats = DescriptiveEngine.calculate(values);
      final lowFence = stats.q1! - 1.5 * stats.iqr!;
      final highFence = stats.q3! + 1.5 * stats.iqr!;
      final inliers = values
          .where((x) => x >= lowFence && x <= highFence)
          .toList();
      result[entry.key] = BoxSummary(
        entry.key,
        inliers.first,
        stats.q1!,
        stats.median!,
        stats.q3!,
        inliers.last,
        values.where((x) => x < lowFence || x > highFence).toList(),
      );
    }
    return result;
  }

  static List<ParetoCategory> pareto(Iterable<Measurement> input) {
    final counts = <String, int>{};
    for (final m in input) {
      if (m.warmup) continue;
      if (m.anomaly != null) counts[m.anomaly!] = (counts[m.anomaly!] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = sorted.fold<int>(0, (sum, e) => sum + e.value);
    var cumulative = 0;
    return [
      for (final entry in sorted)
        (() {
          cumulative += entry.value;
          return ParetoCategory(entry.key, entry.value, cumulative / total);
        })(),
    ];
  }
}
