import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../core/models.dart';
import '../science/descriptive.dart';
import '../science/visualization_data.dart';
import 'visuals.dart';

class ScienceCharts extends StatelessWidget {
  const ScienceCharts({super.key, required this.items});
  final List<Measurement> items;

  @override
  Widget build(BuildContext context) {
    final one = items
        .where((m) => m.clients == 1 && m.success && m.latencyMs != null)
        .map((m) => m.latencyMs!)
        .toList();
    final multi = items
        .where((m) => m.clients > 1 && m.success && m.latencyMs != null)
        .map((m) => m.latencyMs!)
        .toList();
    final polygons = VisualizationData.polygons({
      '1 cliente': one,
      'Varios': multi,
    });
    final all = [...one, ...multi];
    final bins = DescriptiveEngine.frequency(all);
    final boxes = VisualizationData.boxes(items);
    final pareto = VisualizationData.pareto(items);
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        AcrylicPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Polígono de frecuencias',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              const Text('Las series comparten los mismos límites de clase.'),
              const SizedBox(height: 12),
              if (one.isEmpty || multi.isEmpty)
                const Text(
                  'Realiza pruebas con uno y varios clientes para comparar.',
                )
              else ...[
                Row(
                  children: [
                    _Legend(color: primary, label: '1 cliente'),
                    const SizedBox(width: 18),
                    const _Legend(color: LanxisColors.mint, label: 'Varios'),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 240,
                  child: LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: 6,
                      minY: 0,
                      maxY:
                          polygons
                              .expand((p) => p.bins)
                              .map((b) => b.frequency.toDouble())
                              .fold<double>(0, math.max) +
                          1,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) =>
                            FlLine(color: primary.withValues(alpha: .1)),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: const FlTitlesData(
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      lineBarsData: [
                        for (var i = 0; i < polygons.length; i++)
                          LineChartBarData(
                            spots: [
                              for (var j = 0; j < polygons[i].bins.length; j++)
                                FlSpot(
                                  j.toDouble(),
                                  polygons[i].bins[j].frequency.toDouble(),
                                ),
                            ],
                            color: i == 0 ? primary : LanxisColors.mint,
                            barWidth: 3,
                            isCurved: false,
                            dotData: const FlDotData(show: true),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        AcrylicPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ojiva acumulada',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                'Menos de 30 ms: ${_pct(VisualizationData.fractionBelow(all, 30))} · Menos de 50 ms: ${_pct(VisualizationData.fractionBelow(all, 50))}',
              ),
              const SizedBox(height: 18),
              if (bins.isEmpty)
                const Text('Sin respuestas válidas.')
              else
                SizedBox(
                  height: 240,
                  child: LineChart(
                    LineChartData(
                      minX: bins.first.lower,
                      maxX: bins.last.upper,
                      minY: 0,
                      maxY: 100,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) =>
                            FlLine(color: primary.withValues(alpha: .1)),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: const FlTitlesData(
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            FlSpot(bins.first.lower, 0),
                            for (final bin in bins)
                              FlSpot(bin.upper, bin.cumulativeRelative * 100),
                          ],
                          color: primary,
                          barWidth: 3,
                          dotData: const FlDotData(show: false),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              const Text(
                'La curva usa clases agrupadas; los porcentajes de 30 y 50 ms usan muestras originales.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AcrylicPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Caja y bigotes',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              const Text(
                'E1–E6 · cuartiles tipo 7, bigotes de Tukey y valores atípicos.',
              ),
              const SizedBox(height: 16),
              if (boxes.isEmpty)
                const Text('Sin escenarios con latencias válidas.')
              else
                LayoutBuilder(
                  builder: (_, c) => CustomPaint(
                    size: Size(c.maxWidth, 52.0 * boxes.length + 40),
                    painter: _BoxPainter(
                      boxes,
                      primary,
                      Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AcrylicPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pareto de anomalías',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              const Text(
                'Frecuencia de cada anomalía y porcentaje acumulado; referencia de 80%.',
              ),
              const SizedBox(height: 16),
              if (pareto.isEmpty)
                const Text('No se han detectado anomalías en las muestras.'),
              if (pareto.isNotEmpty)
                LayoutBuilder(
                  builder: (_, c) => CustomPaint(
                    size: Size(c.maxWidth, 250),
                    painter: _ParetoPainter(
                      pareto,
                      primary,
                      LanxisColors.mint,
                      Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _pct(double? value) =>
      value == null ? '—' : '${(value * 100).toStringAsFixed(1)}%';
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 5),
      Text(label),
    ],
  );
}

void _label(
  Canvas canvas,
  String text,
  Offset offset,
  Color color, {
  double size = 11,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: size, fontFamily: 'Manrope'),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, offset);
}

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.boxes, this.primary, this.ink);
  final Map<String, BoxSummary> boxes;
  final Color primary;
  final Color ink;
  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = boxes.values
        .expand((b) => [b.maximumWhisker, ...b.outliers])
        .fold<double>(0, math.max);
    final left = 50.0;
    final right = size.width - 12;
    double x(double value) =>
        left + value / (maxValue <= 0 ? 1 : maxValue) * (right - left);
    var row = 0;
    for (final box in boxes.values) {
      final y = 26.0 + row * 52;
      _label(canvas, box.label, Offset(0, y - 8), ink);
      canvas.drawLine(
        Offset(x(box.minimumWhisker), y),
        Offset(x(box.maximumWhisker), y),
        Paint()
          ..color = primary
          ..strokeWidth = 2,
      );
      for (final end in [box.minimumWhisker, box.maximumWhisker]) {
        canvas.drawLine(
          Offset(x(end), y - 9),
          Offset(x(end), y + 9),
          Paint()
            ..color = primary
            ..strokeWidth = 2,
        );
      }
      canvas.drawRect(
        Rect.fromLTRB(x(box.q1), y - 12, x(box.q3), y + 12),
        Paint()..color = primary.withValues(alpha: .24),
      );
      canvas.drawRect(
        Rect.fromLTRB(x(box.q1), y - 12, x(box.q3), y + 12),
        Paint()
          ..color = primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawLine(
        Offset(x(box.median), y - 12),
        Offset(x(box.median), y + 12),
        Paint()
          ..color = ink
          ..strokeWidth = 2,
      );
      for (final point in box.outliers) {
        canvas.drawCircle(Offset(x(point), y), 3, Paint()..color = ink);
      }
      row++;
    }
    _label(canvas, '0 ms', Offset(left, size.height - 18), ink);
    _label(
      canvas,
      '${maxValue.toStringAsFixed(0)} ms',
      Offset(right - 42, size.height - 18),
      ink,
    );
  }

  @override
  bool shouldRepaint(covariant _BoxPainter old) =>
      old.boxes != boxes || old.primary != primary;
}

class _ParetoPainter extends CustomPainter {
  _ParetoPainter(this.data, this.primary, this.secondary, this.ink);
  final List<ParetoCategory> data;
  final Color primary;
  final Color secondary;
  final Color ink;
  @override
  void paint(Canvas canvas, Size size) {
    final left = 16.0;
    final chartWidth = size.width - 32;
    final chartHeight = size.height - 70;
    final maxCount = data.map((d) => d.count).reduce(math.max);
    final barWidth = chartWidth / data.length;
    final line = Path();
    final guideY = 18 + chartHeight * .2;
    canvas.drawLine(
      Offset(left, guideY),
      Offset(left + chartWidth, guideY),
      Paint()
        ..color = ink.withValues(alpha: .35)
        ..strokeWidth = 1,
    );
    _label(canvas, '80%', Offset(left + chartWidth - 28, guideY - 15), ink);
    for (var i = 0; i < data.length; i++) {
      final x = left + i * barWidth;
      final height = data[i].count / maxCount * chartHeight;
      final barLeft = x + barWidth * .16;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            barLeft,
            18 + chartHeight - height,
            barWidth * .55,
            height,
          ),
          const Radius.circular(4),
        ),
        Paint()..color = primary.withValues(alpha: .72),
      );
      _label(
        canvas,
        '${data[i].count}',
        Offset(barLeft, 18 + chartHeight - height - 18),
        ink,
      );
      final label = data[i].label == 'Lag Moderado'
          ? 'Lag'
          : data[i].label == 'Spike Severo'
          ? 'Spike'
          : data[i].label;
      _label(canvas, label, Offset(x, size.height - 35), ink, size: 10);
      final point = Offset(
        x + barWidth * .47,
        18 + chartHeight * (1 - data[i].cumulative),
      );
      if (i == 0) {
        line.moveTo(point.dx, point.dy);
      } else {
        line.lineTo(point.dx, point.dy);
      }
      canvas.drawCircle(point, 3.5, Paint()..color = secondary);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = secondary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _ParetoPainter old) =>
      old.data != data || old.primary != primary || old.secondary != secondary;
}
