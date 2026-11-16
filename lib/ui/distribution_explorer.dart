import 'dart:math' as math;

import 'package:data/stats.dart' as dist;
import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../science/inference.dart';
import 'visuals.dart';

/// Theoretical models are deliberately separate from the empirical session.
class DistributionExplorer extends StatefulWidget {
  const DistributionExplorer({super.key});

  @override
  State<DistributionExplorer> createState() => _DistributionExplorerState();
}

class _DistributionExplorerState extends State<DistributionExplorer> {
  static const models = [
    'Bernoulli',
    'Binomial',
    'Geométrica',
    'Poisson',
    'Normal',
    'Exponencial',
    'Student t',
    'Chi cuadrada',
  ];
  final fields = <String, TextEditingController>{
    'n': TextEditingController(text: '20'),
    'k': TextEditingController(text: '5'),
    'p': TextEditingController(text: '0.2'),
    'λ': TextEditingController(text: '3'),
    'μ': TextEditingController(text: '50'),
    'σ': TextEditingController(text: '10'),
    'gl': TextEditingController(text: '9'),
    'a': TextEditingController(text: '40'),
    'b': TextEditingController(text: '60'),
  };
  String model = 'Binomial';
  bool cumulative = false;

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  bool get discrete => models.indexOf(model) < 4;

  List<String> get parameters => switch (model) {
    'Bernoulli' => ['k', 'p'],
    'Binomial' => ['n', 'k', 'p'],
    'Geométrica' => ['k', 'p'],
    'Poisson' => ['k', 'λ'],
    'Normal' => ['μ', 'σ', 'a', 'b'],
    'Exponencial' => ['λ', 'a', 'b'],
    'Student t' || 'Chi cuadrada' => ['gl', 'a', 'b'],
    _ => [],
  };

  double _value(String key) =>
      double.parse(fields[key]!.text.replaceAll(',', '.'));
  int _integer(String key) {
    final value = _value(key);
    if (!value.isFinite || value != value.roundToDouble()) {
      throw const FormatException('n y k deben ser enteros.');
    }
    return value.toInt();
  }

  ({List<FlSpot> density, List<FlSpot> cdf, double result, String detail})
  _calculate() {
    for (final key in parameters) {
      if (!_value(key).isFinite) {
        throw const FormatException('Introduce números finitos.');
      }
    }
    if (discrete) {
      final k = _integer('k');
      final p = model == 'Poisson' ? 0.0 : _value('p');
      final lambda = model == 'Poisson' ? _value('λ') : 0.0;
      final n = model == 'Binomial' ? _integer('n') : 1;
      if (k < (model == 'Geométrica' ? 1 : 0) ||
          n < 0 ||
          p < 0 ||
          p > 1 ||
          lambda < 0 ||
          (model == 'Bernoulli' && k > 1) ||
          (model == 'Binomial' && k > n)) {
        throw const FormatException('Revisa el dominio de n, k, p y λ.');
      }
      double mass(int x) => switch (model) {
        'Bernoulli' =>
          x == 0
              ? 1 - p
              : x == 1
              ? p
              : 0,
        'Binomial' => ProbabilityEngine.binomialPmf(n, x, p),
        'Geométrica' => ProbabilityEngine.geometricPmf(x, p),
        _ => ProbabilityEngine.poissonPmf(x, lambda),
      };
      double accumulated(int x) => switch (model) {
        'Bernoulli' =>
          x < 0
              ? 0
              : x == 0
              ? 1 - p
              : 1,
        'Binomial' => ProbabilityEngine.binomialCdf(n, x, p),
        'Geométrica' => x < 1 ? 0 : 1 - math.pow(1 - p, x).toDouble(),
        _ => ProbabilityEngine.poissonCdf(x, lambda),
      };
      final start = model == 'Geométrica' ? 1 : 0;
      final naturalEnd = switch (model) {
        'Bernoulli' => 1,
        'Binomial' => n,
        'Geométrica' =>
          p == 0 ? math.max(20, k) : math.max(k, math.max(12, (6 / p).ceil())),
        _ => math.max(k, math.max(12, (lambda + 5 * math.sqrt(lambda)).ceil())),
      };
      // Keep k visible while preserving the exact CDF at the window edge.
      final first = naturalEnd - start > 80
          ? (k - 40).clamp(start, naturalEnd - 80).toInt()
          : start;
      final end = math.min(naturalEnd, first + 80);
      final density = <FlSpot>[];
      final cdf = <FlSpot>[];
      var running = accumulated(first - 1);
      for (var x = first; x <= end; x++) {
        final y = mass(x);
        running += y;
        density.add(FlSpot(x.toDouble(), y));
        cdf.add(FlSpot(x.toDouble(), running.clamp(0, 1)));
      }
      return (density: density, cdf: cdf, result: mass(k), detail: 'P(X = $k)');
    }
    final a = _value('a');
    final b = _value('b');
    if (a > b) throw const FormatException('El límite a debe ser ≤ b.');
    final lambda = model == 'Exponencial' ? _value('λ') : 1.0;
    final mu = model == 'Normal' ? _value('μ') : 0.0;
    final sigma = model == 'Normal' ? _value('σ') : 1.0;
    final df = model == 'Student t' || model == 'Chi cuadrada'
        ? _value('gl')
        : 1.0;
    if (lambda <= 0 || sigma <= 0 || df <= 0) {
      throw const FormatException(
        'λ, σ y grados de libertad deben ser positivos.',
      );
    }
    final distribution = switch (model) {
      'Normal' => dist.NormalDistribution(mu, sigma),
      'Exponencial' => dist.ExponentialDistribution(lambda),
      'Student t' => dist.StudentDistribution(df),
      _ => dist.GammaDistribution(df / 2, 2),
    };
    final (low, high) = switch (model) {
      'Normal' => (mu - 4 * sigma, mu + 4 * sigma),
      'Exponencial' => (0.0, 7 / lambda),
      'Student t' => (-6.0, 6.0),
      _ => (0.0, df + 6 * math.sqrt(2 * df)),
    };
    final density = <FlSpot>[];
    final cdf = <FlSpot>[];
    for (var i = 0; i <= 120; i++) {
      final x = low + (high - low) * i / 120;
      final pdf = distribution.probability(x);
      final cumulative = distribution.cumulativeProbability(x);
      density.add(FlSpot(x, pdf.isFinite ? pdf.clamp(0, 1000) : 0));
      cdf.add(FlSpot(x, cumulative.isFinite ? cumulative.clamp(0, 1) : 0));
    }
    final area =
        distribution.cumulativeProbability(b) -
        distribution.cumulativeProbability(a);
    return (
      density: density,
      cdf: cdf,
      result: area.clamp(0, 1),
      detail:
          'P(${a.toStringAsPrecision(3)} ≤ X ≤ ${b.toStringAsPrecision(3)})',
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final textColor = Theme.of(context).colorScheme.onSurface;
    ({List<FlSpot> density, List<FlSpot> cdf, double result, String detail})?
    data;
    String? error;
    try {
      data = _calculate();
    } on FormatException catch (e) {
      error = e.message;
    } on RangeError {
      error = 'Los parámetros son demasiado grandes para calcular la gráfica.';
    } on ArgumentError {
      error = 'Los parámetros están fuera del dominio de la distribución.';
    }
    final spots = cumulative ? data?.cdf : data?.density;
    return AcrylicPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Explorador de distribuciones',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text(
            'Modelo teórico. Ajusta parámetros; no implica que los datos observados sigan esta distribución.',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 230,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: model,
                  decoration: const InputDecoration(labelText: 'Distribución'),
                  items: [
                    for (final name in models)
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: (value) => setState(() => model = value ?? model),
                ),
              ),
              for (final key in parameters)
                SizedBox(
                  width: 94,
                  child: TextField(
                    controller: fields[key],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: InputDecoration(labelText: key),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                label: Text(discrete ? 'Masa' : 'Densidad'),
              ),
              const ButtonSegment(value: true, label: Text('Acumulada')),
            ],
            selected: {cumulative},
            onSelectionChanged: (value) =>
                setState(() => cumulative = value.first),
          ),
          const SizedBox(height: 12),
          if (error != null)
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else if (data != null) ...[
            Text(
              '${data.detail} = ${(data.result * 100).toStringAsFixed(3)}%',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 225,
              child: LineChart(
                LineChartData(
                  minX: spots!.first.x,
                  maxX: spots.last.x == spots.first.x
                      ? spots.last.x + 1
                      : spots.last.x,
                  minY: 0,
                  maxY: math.max(
                    0.01,
                    spots.map((e) => e.y).reduce(math.max) * 1.12,
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: primary.withValues(alpha: .12)),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        interval: math.max(
                          1,
                          (spots.last.x - spots.first.x) / 4,
                        ),
                        getTitlesWidget: (value, _) => Text(
                          value.toStringAsFixed(discrete ? 0 : 1),
                          style: TextStyle(fontSize: 10, color: textColor),
                        ),
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      color: primary,
                      barWidth: 3,
                      isCurved: !discrete,
                      dotData: FlDotData(show: discrete),
                      belowBarData: BarAreaData(
                        show: !cumulative,
                        color: primary.withValues(alpha: .13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              discrete
                  ? 'La gráfica muestra hasta 81 valores alrededor de k; la acumulada incluye toda la cola anterior.'
                  : 'Área entre a y b calculada con la función acumulada; la gráfica muestra densidad o acumulada.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
