import 'dart:math';

import 'package:data/stats.dart' as dist;
import 'package:data/special.dart' as special;

import '../core/models.dart';
import 'descriptive.dart';

class Interval {
  const Interval(
    this.lower,
    this.upper,
    this.level,
    this.method, {
    this.warning,
  });
  final double lower;
  final double upper;
  final double level;
  final String method;
  final String? warning;
}

class HypothesisResult {
  const HypothesisResult({
    required this.nullHypothesis,
    required this.alternativeHypothesis,
    required this.method,
    required this.assumptions,
    required this.alpha,
    required this.statistic,
    required this.criticalValue,
    required this.pValue,
    required this.sampleSize,
    this.degreesOfFreedom,
    this.warning,
  });
  final String nullHypothesis;
  final String alternativeHypothesis;
  final String method;
  final String assumptions;
  final double alpha;
  final double statistic;
  final double criticalValue;
  final double pValue;
  final int sampleSize;
  final double? degreesOfFreedom;
  final String? warning;
  bool get rejectNull => pValue < alpha;
  String get decision => rejectNull
      ? 'Se rechaza H0'
      : 'No hay evidencia suficiente para rechazar H0';
  String get rejectionRegion => 'Estadístico > $criticalValue';
  String get typeI => 'Riesgo de rechazar H0 cuando es verdadera: $alpha';
  String get typeII =>
      'Riesgo de no rechazar H0 cuando es falsa; depende del efecto real y la potencia.';
}

class ProbabilityEngine {
  static double? severeLagRate(Iterable<Measurement> input) {
    final items = input.where((m) => !m.warmup).toList();
    if (items.isEmpty) return null;
    return items.where((m) => m.severeLag).length / items.length;
  }

  static double? conditionalMultiGivenLag(Iterable<Measurement> input) {
    final lag = input.where((m) => !m.warmup && m.severeLag).toList();
    if (lag.isEmpty) return null;
    return lag.where((m) => m.clients > 1).length / lag.length;
  }

  static double? lagAndMulti(Iterable<Measurement> input) {
    final items = input.where((m) => !m.warmup).toList();
    if (items.isEmpty) return null;
    return items.where((m) => m.severeLag && m.clients > 1).length /
        items.length;
  }

  /// Critical: failed request or latency strictly greater than 100 ms.
  static ({
    double total,
    Map<double, double> prior,
    Map<double, double> conditional,
    Map<double, double> posterior,
  })
  criticalByDistance(Iterable<Measurement> input, {bool balanced = false}) {
    final items = input.where((m) => !m.warmup && m.distanceM != null).toList();
    if (items.isEmpty) throw ArgumentError('No hay observaciones');
    final groups = <double, List<Measurement>>{};
    for (final item in items) {
      groups.putIfAbsent(item.distanceM!, () => []).add(item);
    }
    final prior = <double, double>{};
    final conditional = <double, double>{};
    for (final entry in groups.entries) {
      prior[entry.key] = balanced
          ? 1 / groups.length
          : entry.value.length / items.length;
      conditional[entry.key] =
          entry.value
              .where((m) => !m.success || (m.latencyMs ?? 0) > 100)
              .length /
          entry.value.length;
    }
    final total = groups.keys.fold<double>(
      0,
      (sum, distance) => sum + prior[distance]! * conditional[distance]!,
    );
    final posterior = <double, double>{};
    if (total > 0) {
      for (final distance in groups.keys) {
        posterior[distance] = prior[distance]! * conditional[distance]! / total;
      }
    }
    return (
      total: total,
      prior: prior,
      conditional: conditional,
      posterior: posterior,
    );
  }

  static double binomialPmf(int n, int k, double p) {
    if (n < 0 || k < 0 || k > n || !p.isFinite || p < 0 || p > 1) {
      throw ArgumentError('Parámetros binomiales inválidos');
    }
    if (p == 0) return k == 0 ? 1 : 0;
    if (p == 1) return k == n ? 1 : 0;
    return exp(
      special.gammaLn(n + 1) -
          special.gammaLn(k + 1) -
          special.gammaLn(n - k + 1) +
          k * log(p) +
          (n - k) * log(1 - p),
    );
  }

  static double binomialCdf(int n, int k, double p) {
    if (n < 0 || !p.isFinite || p < 0 || p > 1) {
      throw ArgumentError('Parámetros binomiales inválidos');
    }
    if (k < 0) return 0;
    if (k >= n || p == 0) return 1;
    if (p == 1) return 0;
    return special.ibeta(1 - p, n - k, k + 1).clamp(0, 1);
  }

  static double geometricAttemptsMean(double p) {
    if (p < 0 || p > 1) throw ArgumentError.value(p);
    return p == 0 ? double.infinity : 1 / p;
  }

  static double geometricFailuresMean(double p) {
    if (p < 0 || p > 1) throw ArgumentError.value(p);
    return p == 0 ? double.infinity : (1 - p) / p;
  }

  static double geometricPmf(int attempt, double p) {
    if (attempt < 1 || p < 0 || p > 1) {
      throw ArgumentError('Parámetros geométricos inválidos');
    }
    if (p == 0) return 0;
    return pow(1 - p, attempt - 1).toDouble() * p;
  }

  static double poissonPmf(int k, double lambda) {
    if (k < 0 || !lambda.isFinite || lambda < 0) {
      throw ArgumentError('Parámetros Poisson inválidos');
    }
    if (lambda == 0) return k == 0 ? 1 : 0;
    return exp(k * log(lambda) - lambda - special.gammaLn(k + 1));
  }

  static double poissonCdf(int k, double lambda) {
    if (!lambda.isFinite || lambda < 0) {
      throw ArgumentError('Parámetros Poisson inválidos');
    }
    if (k < 0) return 0;
    if (lambda == 0) return 1;
    return (1 - special.lowRegGamma(k + 1, lambda)).clamp(0, 1);
  }

  static double normalArea(double a, double b, double mean, double sd) {
    if (sd <= 0 || a > b) throw ArgumentError('Intervalo normal inválido');
    final model = dist.NormalDistribution(mean, sd);
    return model.cumulativeProbability(b) - model.cumulativeProbability(a);
  }

  static double exponentialCdf(double x, double lambda) {
    if (lambda <= 0) throw ArgumentError.value(lambda);
    return dist.ExponentialDistribution(lambda).cumulativeProbability(x);
  }

  static double studentCdf(double t, double degreesOfFreedom) {
    if (degreesOfFreedom <= 0) throw ArgumentError.value(degreesOfFreedom);
    return dist.StudentDistribution(degreesOfFreedom).cumulativeProbability(t);
  }

  static double chiSquareCdf(double x, double degreesOfFreedom) {
    if (degreesOfFreedom <= 0) throw ArgumentError.value(degreesOfFreedom);
    return dist.GammaDistribution(
      degreesOfFreedom / 2,
      2,
    ).cumulativeProbability(x);
  }
}

class InferenceEngine {
  static Interval meanInterval(Iterable<double> values, {double level = .95}) {
    if (level <= 0 || level >= 1) throw ArgumentError.value(level);
    final summary = DescriptiveEngine.calculate(values);
    if (summary.n < 2 || summary.standardDeviation == null) {
      throw ArgumentError('Se requieren al menos dos observaciones válidas');
    }
    final t = dist.StudentDistribution((summary.n - 1).toDouble())
        .inverseCumulativeProbability((1 + level) / 2);
    final margin = t * summary.standardDeviation! / sqrt(summary.n);
    return Interval(
      summary.mean! - margin,
      summary.mean! + margin,
      level,
      'Student t (σ desconocida)',
      warning: summary.n < 30
          ? 'Muestra pequeña: verificar forma de distribución e independencia.'
          : null,
    );
  }

  static Interval proportionWilson(int successes, int n, {double level = .95}) {
    if (n < 1 || successes < 0 || successes > n || level <= 0 || level >= 1) {
      throw ArgumentError('Proporción o nivel inválido');
    }
    final p = successes / n;
    final z = const dist.NormalDistribution.standard()
        .inverseCumulativeProbability((1 + level) / 2);
    final d = 1 + z * z / n;
    final center = (p + z * z / (2 * n)) / d;
    final radius = z / d * sqrt(p * (1 - p) / n + z * z / (4 * n * n));
    return Interval(
      max(0, center - radius),
      min(1, center + radius),
      level,
      'Wilson',
    );
  }

  static HypothesisResult meanGreater(
    Iterable<double> values,
    double baseline, {
    double alpha = .05,
  }) {
    _checkAlpha(alpha);
    final s = DescriptiveEngine.calculate(values);
    if (s.n < 2 || s.standardDeviation == null || s.standardDeviation == 0) {
      throw ArgumentError('Prueba t requiere dispersión y n ≥ 2');
    }
    final distribution = dist.StudentDistribution((s.n - 1).toDouble());
    final statistic = (s.mean! - baseline) / (s.standardDeviation! / sqrt(s.n));
    return HypothesisResult(
      nullHypothesis: 'μ = $baseline',
      alternativeHypothesis: 'μ > $baseline',
      method: 't de una muestra',
      assumptions: 'Observaciones independientes; normalidad aproximada o tamaño suficiente.',
      alpha: alpha,
      statistic: statistic,
      criticalValue: distribution.inverseCumulativeProbability(1 - alpha),
      pValue: 1 - distribution.cumulativeProbability(statistic),
      sampleSize: s.n,
      degreesOfFreedom: (s.n - 1).toDouble(),
      warning: s.n < 30 ? 'Verificar normalidad en muestra pequeña.' : null,
    );
  }

  static HypothesisResult welchGreater(
    Iterable<double> experimental,
    Iterable<double> baseline, {
    double alpha = .05,
  }) {
    _checkAlpha(alpha);
    final a = DescriptiveEngine.calculate(experimental);
    final b = DescriptiveEngine.calculate(baseline);
    if (a.n < 2 || b.n < 2 || a.variance == null || b.variance == null) {
      throw ArgumentError('Welch requiere n ≥ 2 en ambos grupos');
    }
    final va = a.variance! / a.n;
    final vb = b.variance! / b.n;
    if (va + vb <= 0) throw ArgumentError('Varianza nula');
    final df =
        pow(va + vb, 2) / (pow(va, 2) / (a.n - 1) + pow(vb, 2) / (b.n - 1));
    final t = (a.mean! - b.mean!) / sqrt(va + vb);
    final distribution = dist.StudentDistribution(df.toDouble());
    return HypothesisResult(
      nullHypothesis: 'μ experimental = μ base',
      alternativeHypothesis: 'μ experimental > μ base',
      method: 'Welch de dos muestras',
      assumptions:
          'Grupos independientes; varianzas no necesariamente iguales.',
      alpha: alpha,
      statistic: t,
      criticalValue: distribution.inverseCumulativeProbability(1 - alpha),
      pValue: 1 - distribution.cumulativeProbability(t),
      sampleSize: a.n + b.n,
      degreesOfFreedom: df.toDouble(),
      warning: 'Si las muestras provienen de ensayos repetidos del mismo dispositivo, usar un método pareado o jerárquico.',
    );
  }

  static HypothesisResult varianceGreater(
    Iterable<double> values,
    double referenceVariance, {
    double alpha = .05,
  }) {
    _checkAlpha(alpha);
    final s = DescriptiveEngine.calculate(values);
    if (s.n < 2 || referenceVariance <= 0) {
      throw ArgumentError('Varianza de referencia inválida');
    }
    final distribution = dist.GammaDistribution((s.n - 1) / 2, 2);
    final statistic = (s.n - 1) * s.variance! / referenceVariance;
    return HypothesisResult(
      nullHypothesis: 'σ² = $referenceVariance',
      alternativeHypothesis: 'σ² > $referenceVariance',
      method: 'Chi cuadrada para una varianza',
      assumptions: 'Observaciones independientes de una población aproximadamente normal.',
      alpha: alpha,
      statistic: statistic,
      criticalValue: distribution.inverseCumulativeProbability(1 - alpha),
      pValue: 1 - distribution.cumulativeProbability(statistic),
      sampleSize: s.n,
      degreesOfFreedom: (s.n - 1).toDouble(),
      warning: 'Muy sensible a la falta de normalidad.',
    );
  }

  static HypothesisResult slowProportionGreater(
    int slow,
    int n, {
    double reference = .10,
    double alpha = .05,
  }) {
    _checkAlpha(alpha);
    if (n < 1 ||
        slow < 0 ||
        slow > n ||
        !reference.isFinite ||
        reference <= 0 ||
        reference >= 1) {
      throw ArgumentError('Datos de proporción inválidos');
    }
    if (n * reference < 5 || n * (1 - reference) < 5) {
      final upperTails = List<double>.filled(n + 2, 0);
      for (var k = n; k >= 0; k--) {
        upperTails[k] =
            (upperTails[k + 1] + ProbabilityEngine.binomialPmf(n, k, reference))
                .clamp(0.0, 1.0);
      }

      var firstRejected = n + 1;
      for (var k = 0; k <= n; k++) {
        if (upperTails[k] <= alpha) {
          firstRejected = k;
          break;
        }
      }
      return HypothesisResult(
        nullHypothesis: 'p = $reference',
        alternativeHypothesis: 'p > $reference',
        method: 'Binomial exacta unilateral',
        assumptions: 'Ensayos Bernoulli independientes con probabilidad constante bajo H0.',
        alpha: alpha,
        statistic: slow.toDouble(),
        criticalValue: (firstRejected - 1).toDouble(),
        pValue: upperTails[slow],
        sampleSize: n,
        warning: 'Muestra pequeña: se usa la distribución binomial exacta en vez de aproximación normal.',
      );
    }
    final statistic =
        (slow / n - reference) / sqrt(reference * (1 - reference) / n);
    final normal = const dist.NormalDistribution.standard();
    return HypothesisResult(
      nullHypothesis: 'p = $reference',
      alternativeHypothesis: 'p > $reference',
      method: 'Z de una proporción',
      assumptions: 'Observaciones independientes; n·p₀ y n·(1−p₀) suficientemente grandes.',
      alpha: alpha,
      statistic: statistic,
      criticalValue: normal.inverseCumulativeProbability(1 - alpha),
      pValue: 1 - normal.cumulativeProbability(statistic),
      sampleSize: n,
      warning: n * reference < 5 || n * (1 - reference) < 5
          ? 'Aproximación normal débil; usar binomial exacta.'
          : null,
    );
  }

  static void _checkAlpha(double alpha) {
    if (!alpha.isFinite || alpha <= 0 || alpha >= 1) {
      throw ArgumentError.value(alpha);
    }
  }
}
