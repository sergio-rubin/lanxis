import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/models.dart';
import '../science/analysis_report.dart';
import '../science/descriptive.dart';

/// Vector report shared by Android and desktop exports. All statements are
/// derived from the selected observations; an empty selection stays explicit.
class PdfReportBuilder {
  static const _ink = PdfColor(.13, .22, .27);
  static const _muted = PdfColor(.38, .47, .51);
  static const _accent = PdfColor(.20, .49, .55);
  static const _pale = PdfColor(.93, .96, .97);
  static const _line = PdfColor(.82, .87, .89);

  static Future<Uint8List> build({
    required LabSession session,
    required String scopeLabel,
    required List<Measurement> items,
    required List<List<String>> conditions,
    required List<Map<String, Object?>> serverMetrics,
    required String appVersion,
    required int protocolVersion,
    required bool clientScoped,
  }) async {
    final report = AnalysisReport(items);
    final ordered = [...items]
      ..sort((a, b) => a.timestampUtc.compareTo(b.timestampUtc));
    final valid = ordered
        .where((item) => item.success && item.latencyMs != null)
        .map((item) => item.latencyMs!)
        .toList();
    final bins = DescriptiveEngine.frequency(valid);
    final jitter = DescriptiveEngine.calculate(
      items.where((m) => m.jitterMs != null).map((m) => m.jitterMs!),
    );
    final throughput = DescriptiveEngine.calculate(
      items.where((m) => m.speedMbps != null).map((m) => m.speedMbps!),
    );
    final bodyFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Manrope.ttf'),
    );
    final headingFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/SpaceGrotesk.ttf'),
    );
    final exported = DateTime.now().toUtc().toIso8601String();
    final document = pw.Document();
    final summary = report.general;
    final clientLocalCopy = items.any(
      (item) => item.distanceSource == 'server_pending',
    );
    final interpretations = _insights(report, clientLocalCopy: clientLocalCopy);

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(39, 38, 39, 37),
        maxPages: 200,
        theme: pw.ThemeData.withFont(base: bodyFont, bold: headingFont),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _line, width: .6)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                children: [
                  _gaussianMark(),
                  pw.SizedBox(width: 8),
                  pw.Text(
                    'LANXIS  /  INFORME DE ENSAYO',
                    style: pw.TextStyle(
                      font: headingFont,
                      fontSize: 8.5,
                      color: _ink,
                    ),
                  ),
                ],
              ),
              pw.Text(
                'v$appVersion  ·  protocolo $protocolVersion',
                style: const pw.TextStyle(fontSize: 7.5, color: _muted),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _line, width: .6)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Sesión ${_short(session.id)}  ·  Exportado $exported UTC',
                style: const pw.TextStyle(fontSize: 7, color: _muted),
              ),
              pw.Text(
                '${context.pageNumber} / ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 7, color: _muted),
              ),
            ],
          ),
        ),
        build: (_) => [
          pw.SizedBox(height: 15),
          pw.Text(
            'Informe de análisis de red local',
            style: pw.TextStyle(font: headingFont, fontSize: 25, color: _ink),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            session.name,
            style: pw.TextStyle(
              font: headingFont,
              fontSize: 15,
              color: _accent,
            ),
          ),
          pw.SizedBox(height: 7),
          pw.Text(
            'Alcance: $scopeLabel  ·  ID ${session.id}',
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
          if (clientLocalCopy) ...[
            pw.SizedBox(height: 7),
            pw.Text(
              'Copia local del participante. La distancia y las métricas finales calculadas por el servidor se consultan en su informe.',
              style: const pw.TextStyle(fontSize: 8, color: _accent),
            ),
          ],
          pw.SizedBox(height: 20),
          _section('01', 'Resultados de un vistazo', headingFont),
          pw.SizedBox(height: 9),
          pw.Row(
            children: [
              _kpi('OBSERVACIONES', '${summary.total}', headingFont),
              pw.SizedBox(width: 7),
              _kpi('RTT MEDIO', _ms(summary.stats.mean), headingFont),
              pw.SizedBox(width: 7),
              _kpi('P95', _ms(summary.stats.p95), headingFont),
              pw.SizedBox(width: 7),
              _kpi('SLA < 50 MS', _pct(summary.sla), headingFont),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            '${summary.valid} respuestas con RTT válido · ${summary.failed} fallos · ${summary.withoutValidRtt} sin RTT válido. El SLA usa todas las observaciones como denominador.',
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
          pw.SizedBox(height: 18),
          _section('02', 'Qué indican los datos', headingFont),
          pw.SizedBox(height: 8),
          for (final (index, insight) in interpretations.indexed)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 7),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 15,
                    height: 15,
                    alignment: pw.Alignment.center,
                    decoration: const pw.BoxDecoration(color: _pale),
                    child: pw.Text(
                      '${index + 1}',
                      style: pw.TextStyle(
                        font: headingFont,
                        fontSize: 8,
                        color: _accent,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Text(
                      insight,
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: _ink,
                        lineSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          pw.SizedBox(height: 5),
          pw.Container(
            padding: const pw.EdgeInsets.all(11),
            decoration: const pw.BoxDecoration(
              color: _pale,
              border: pw.Border(left: pw.BorderSide(color: _accent, width: 2)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'INTERPRETACIÓN ESTADÍSTICA',
                  style: pw.TextStyle(
                    font: headingFont,
                    fontSize: 8,
                    color: _accent,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  summary.interpretation,
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: _ink,
                    lineSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 19),
          _section('03', 'Latencia a lo largo del ensayo', headingFont),
          pw.SizedBox(height: 7),
          if (valid.isEmpty)
            _empty('No hay RTT válido para trazar la serie temporal.')
          else ...[
            pw.Text(
              valid.length > 180
                  ? 'Serie ordenada por UTC y reducida a 180 puntos para lectura visual. Los cálculos usan todas las respuestas válidas. La línea tenue marca 50 ms.'
                  : 'Cada punto es una respuesta válida, ordenada por UTC. La línea tenue marca el umbral SLA de 50 ms.',
              style: const pw.TextStyle(fontSize: 8, color: _muted),
            ),
            pw.SizedBox(height: 8),
            _latencyChart(valid),
            pw.SizedBox(height: 5),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Primera muestra',
                  style: const pw.TextStyle(fontSize: 7, color: _muted),
                ),
                pw.Text(
                  'Máximo ${_ms(summary.stats.maximum)} · mediana ${_ms(summary.stats.median)}',
                  style: const pw.TextStyle(fontSize: 7, color: _muted),
                ),
                pw.Text(
                  'Última muestra',
                  style: const pw.TextStyle(fontSize: 7, color: _muted),
                ),
              ],
            ),
          ],
          pw.SizedBox(height: 18),
          pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _section('04', 'Distribución y dispersión', headingFont),
                pw.SizedBox(height: 7),
                if (bins.isEmpty)
                  _empty('Sin respuestas válidas para construir el histograma.')
                else ...[
                  pw.Text(
                    'Frecuencia de RTT por intervalo. Las barras muestran recuentos, no probabilidad modelada.',
                    style: const pw.TextStyle(fontSize: 8, color: _muted),
                  ),
                  pw.SizedBox(height: 7),
                  _histogram(bins),
                ],
              ],
            ),
          ),
          if (bins.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            _table(
              ['Intervalo RTT (ms)', 'Frecuencia', 'Porcentaje'],
              [
                for (final (index, bin) in bins.indexed)
                  [
                    '[${bin.lower.toStringAsFixed(1)}, ${bin.upper.toStringAsFixed(1)}${index == bins.length - 1 ? ']' : ')'}',
                    '${bin.frequency}',
                    '${(bin.relative * 100).toStringAsFixed(1)} %',
                  ],
              ],
            ),
          ],
          pw.SizedBox(height: 9),
          _table(
            ['Indicador', 'Valor', 'Lectura'],
            [
              [
                'Mínimo / máximo',
                '${_ms(summary.stats.minimum)} / ${_ms(summary.stats.maximum)}',
                'Extremos observados',
              ],
              [
                'Q1 / mediana / Q3',
                '${_ms(summary.stats.q1)} / ${_ms(summary.stats.median)} / ${_ms(summary.stats.q3)}',
                'Mitad central de los RTT válidos',
              ],
              [
                'P90 / P95 / P99',
                '${_ms(summary.stats.p90)} / ${_ms(summary.stats.p95)} / ${_ms(summary.stats.p99)}',
                'Cola de la distribución',
              ],
              [
                'Desv. estándar',
                _ms(summary.stats.standardDeviation),
                'Muestral, n - 1',
              ],
              [
                'Jitter medio',
                _ms(jitter.mean),
                'Solo muestras con jitter registrado',
              ],
              [
                'Throughput medio',
                throughput.mean == null
                    ? '—'
                    : '${throughput.mean!.toStringAsFixed(2)} Mb/s',
                'Solo transferencias con throughput',
              ],
            ],
          ),
          pw.SizedBox(height: 18),
          _section('05', 'Clientes y distancia', headingFont),
          pw.SizedBox(height: 7),
          if (report.individual.isEmpty)
            _empty('No hay clientes en esta selección.')
          else ...[
            _table(
              ['Cliente', 'n', 'RTT medio', 'P95', 'SLA', 'Distancia'],
              [
                for (final entry in report.individual.entries)
                  [
                    _short(entry.key),
                    '${entry.value.total}',
                    _ms(entry.value.stats.mean),
                    _ms(entry.value.stats.p95),
                    _pct(entry.value.sla),
                    entry.value.medianDistanceM == null
                        ? 'Sin dato'
                        : '${entry.value.medianDistanceM!.toStringAsFixed(2)} m${entry.value.maxUncertaintyM == null ? '' : ' ±${entry.value.maxUncertaintyM!.toStringAsFixed(2)}'}',
                  ],
              ],
            ),
            if (report.individual.length > 1) ...[
              pw.SizedBox(height: 10),
              pw.Text(
                'Comparación de RTT medio (solo respuestas válidas)',
                style: const pw.TextStyle(fontSize: 8, color: _muted),
              ),
              pw.SizedBox(height: 7),
              _clientBars(report.individual),
            ],
            if (report.individual.values.any(
              (summary) => summary.medianDistanceM != null,
            ))
              pw.Inseparable(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(height: 11),
                    pw.Text(
                      'Distancia registrada y margen orientativo por cliente',
                      style: const pw.TextStyle(fontSize: 8.5, color: _muted),
                    ),
                    pw.SizedBox(height: 7),
                    _distanceRanges(report.individual),
                  ],
                ),
              ),
            pw.SizedBox(height: 10),
            for (final entry in report.individual.entries)
              pw.Inseparable(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Cliente ${entry.key}',
                      style: pw.TextStyle(
                        font: headingFont,
                        fontSize: 10,
                        color: _ink,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      entry.value.interpretation,
                      style: const pw.TextStyle(
                        fontSize: 8.5,
                        color: _muted,
                        lineSpacing: 2,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                  ],
                ),
              ),
          ],
          pw.SizedBox(height: 12),
          pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _section('06', 'Condiciones y servidor', headingFont),
                pw.SizedBox(height: 7),
                if (conditions.isEmpty)
                  _empty('No hay pruebas configuradas en esta selección.')
                else if (conditions.length <= 6)
                  _table([
                    'Escenario',
                    'Clientes',
                    'n previsto',
                    'Carga B',
                    'Protocolo',
                    'Ambiente',
                    'Objetivo m',
                  ], conditions)
                else
                  pw.Text(
                    '${conditions.length} configuraciones seleccionadas.',
                    style: const pw.TextStyle(fontSize: 8, color: _muted),
                  ),
              ],
            ),
          ),
          if (conditions.length > 6)
            _table([
              'Escenario',
              'Clientes',
              'n previsto',
              'Carga B',
              'Protocolo',
              'Ambiente',
              'Objetivo m',
            ], conditions),
          pw.SizedBox(height: 10),
          if (serverMetrics.isEmpty)
            _empty(
              clientLocalCopy
                  ? 'Esta copia del cliente no incluye métricas del servidor. Expórtalas desde el servidor LANXIS.'
                  : 'No hay métricas de ensayo coordinado para esta selección.',
            )
          else ...[
            pw.Text(
              'Métricas del servidor por ensayo; la carga útil no incluye cabeceras de transporte.',
              style: const pw.TextStyle(fontSize: 8, color: _muted),
            ),
            if (clientScoped)
              pw.Text(
                'Estas métricas cubren el ensayo completo con todos los clientes, incluso en una vista individual.',
                style: const pw.TextStyle(fontSize: 8, color: _accent),
              ),
            pw.SizedBox(height: 6),
            _table(
              ['Ensayo', 'Duración ms', 'Muestras', 'Enviado B', 'Recibido B'],
              [
                for (final metric in serverMetrics)
                  [
                    _short('${metric['trial_id']}'),
                    '${metric['server_elapsed_ms'] ?? '—'}',
                    '${metric['server_received_samples'] ?? '—'}',
                    '${metric['server_payload_sent_bytes'] ?? '—'}',
                    '${metric['server_payload_received_bytes'] ?? '—'}',
                  ],
              ],
            ),
          ],
          pw.SizedBox(height: 18),
          pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _section('07', 'Método y límites', headingFont),
                pw.SizedBox(height: 6),
                pw.Text(
                  'RTT de aplicación del protocolo registrado, medido con reloj monotónico local. Calentamientos excluidos. Fallos incluidos en el denominador del SLA estricto (RTT < 50 ms). Cuartiles y percentiles por interpolación tipo 7; desviación estándar muestral con n - 1.',
                  style: const pw.TextStyle(
                    fontSize: 8.5,
                    color: _ink,
                    lineSpacing: 2,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'La carga, el sistema operativo y el entorno radioeléctrico afectan los resultados. BLE por RSSI produce una estimación orientativa con incertidumbre, no una distancia calibrada. Las muestras repetidas pueden estar correlacionadas; los resúmenes son descriptivos y no demuestran causalidad.',
                  style: const pw.TextStyle(
                    fontSize: 8.5,
                    color: _muted,
                    lineSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return document.save();
  }

  static String _short(String id) =>
      id.length > 12 ? '${id.substring(0, 10)}…' : id;
  static String _ms(num? value) =>
      value == null ? '—' : '${value.toStringAsFixed(2)} ms';
  static String _pct(num? value) =>
      value == null ? '—' : '${(value * 100).toStringAsFixed(1)} %';

  static List<String> _insights(
    AnalysisReport report, {
    required bool clientLocalCopy,
  }) {
    final summary = report.general;
    if (summary.total == 0) {
      return [
        'La selección no contiene observaciones. Ajusta los filtros o ejecuta un ensayo para obtener una interpretación.',
      ];
    }
    final result = <String>[
      '${summary.valid} de ${summary.total} observaciones aportaron un RTT válido; ${summary.failed} fallaron. El porcentaje SLA considera también los fallos.',
    ];
    final median = summary.stats.median;
    final p95 = summary.stats.p95;
    if (median != null && p95 != null) {
      final gap = p95 - median;
      result.add(
        'El P95 supera la mediana en ${gap.toStringAsFixed(2)} ms. ${gap > median ? 'La cola de latencia es amplia respecto al comportamiento central; revisa interferencia, carga y eventos del ensayo.' : 'La cola se mantiene relativamente próxima al comportamiento central en esta selección.'}',
      );
      if (summary.valid < 20) {
        result.add(
          'Solo hay ${summary.valid} RTT válidos: los percentiles altos son sensibles a una o dos muestras y deben leerse como descripción de este ensayo.',
        );
      }
    } else {
      result.add(
        'No hay RTT suficiente para estimar media, percentiles o dispersión.',
      );
    }
    if (summary.medianDistanceM != null) {
      result.add(
        'La distancia mediana registrada es ${summary.medianDistanceM!.toStringAsFixed(2)} m${summary.maxUncertaintyM == null ? '' : ' con margen orientativo máximo ±${summary.maxUncertaintyM!.toStringAsFixed(2)} m'}. El origen y el margen acompañan al dato; BLE no es una medición exacta.',
      );
    } else {
      result.add(
        clientLocalCopy
            ? 'Esta copia local no incluye la distancia que mide el servidor. Consulta el informe del servidor para verla con su incertidumbre.'
            : 'La distancia no estuvo disponible; las estadísticas de RTT se calculan sin inventar metros.',
      );
    }
    final ranked =
        report.individual.entries
            .where((entry) => entry.value.stats.mean != null)
            .toList()
          ..sort((a, b) => a.value.stats.mean!.compareTo(b.value.stats.mean!));
    if (ranked.length > 1) {
      final fastest = ranked.first;
      final slowest = ranked.last;
      final gap = slowest.value.stats.mean! - fastest.value.stats.mean!;
      result.add(
        'Entre los clientes con RTT válido, ${_short(fastest.key)} presenta la menor media y ${_short(slowest.key)} la mayor; la diferencia observada es ${gap.toStringAsFixed(2)} ms. Compara también tamaños de muestra y protocolos antes de atribuir causas.',
      );
    }
    return result;
  }

  static pw.Widget _section(String number, String title, pw.Font headingFont) =>
      pw.Row(
        children: [
          pw.Container(
            width: 19,
            height: 19,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(color: _accent),
            child: pw.Text(
              number,
              style: pw.TextStyle(
                font: headingFont,
                fontSize: 8,
                color: PdfColors.white,
              ),
            ),
          ),
          pw.SizedBox(width: 9),
          pw.Text(
            title,
            style: pw.TextStyle(font: headingFont, fontSize: 13, color: _ink),
          ),
        ],
      );

  static pw.Widget _kpi(String label, String value, pw.Font headingFont) =>
      pw.Expanded(
        child: pw.Container(
          height: 62,
          padding: const pw.EdgeInsets.fromLTRB(9, 10, 7, 8),
          decoration: const pw.BoxDecoration(color: _pale),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                label,
                style: const pw.TextStyle(fontSize: 6.7, color: _muted),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                value,
                style: pw.TextStyle(
                  font: headingFont,
                  fontSize: 14,
                  color: _ink,
                ),
              ),
            ],
          ),
        ),
      );

  static pw.Widget _empty(String message) => pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: const pw.BoxDecoration(color: _pale),
    child: pw.Text(
      message,
      style: const pw.TextStyle(fontSize: 8, color: _muted),
    ),
  );

  static pw.Widget _table(List<String> headers, List<List<String>> data) =>
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: data,
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        headerPadding: const pw.EdgeInsets.symmetric(
          horizontal: 6,
          vertical: 6,
        ),
        headerStyle: const pw.TextStyle(fontSize: 8, color: _ink),
        cellStyle: const pw.TextStyle(fontSize: 8, color: _ink),
        headerDecoration: const pw.BoxDecoration(color: _pale),
        border: const pw.TableBorder(
          bottom: pw.BorderSide(color: _line, width: .5),
          horizontalInside: pw.BorderSide(color: _line, width: .35),
        ),
      );

  static pw.Widget _gaussianMark() => pw.CustomPaint(
    size: const PdfPoint(33, 20),
    painter: (canvas, size) {
      const heights = [3.0, 6.0, 11.0, 17.0, 20.0, 17.0, 11.0, 6.0, 3.0];
      for (var i = 0; i < heights.length; i++) {
        canvas
          ..setFillColor(i == 4 ? _accent : _line)
          ..drawRect(i * 3.7, 0, 2.4, heights[i])
          ..fillPath();
      }
    },
  );

  static pw.Widget _latencyChart(List<double> values) {
    final maximum = math.max(50.0, values.reduce(math.max) * 1.08);
    return pw.Row(
      children: [
        pw.SizedBox(
          width: 34,
          height: 132,
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                maximum.toStringAsFixed(0),
                style: const pw.TextStyle(fontSize: 7, color: _muted),
              ),
              pw.Text(
                (maximum / 2).toStringAsFixed(0),
                style: const pw.TextStyle(fontSize: 7, color: _muted),
              ),
              pw.Text(
                '0 ms',
                style: const pw.TextStyle(fontSize: 7, color: _muted),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 4),
        pw.CustomPaint(
          size: const PdfPoint(462, 132),
          painter: (canvas, size) {
            const left = 5.0;
            const bottom = 9.0;
            final width = size.x - 10;
            final height = size.y - 19;
            for (var i = 0; i <= 2; i++) {
              final y = bottom + height * i / 2;
              canvas
                ..setStrokeColor(_line)
                ..setLineWidth(.45)
                ..drawLine(left, y, left + width, y)
                ..strokePath();
            }
            final slaY = bottom + height * 50 / maximum;
            canvas
              ..setStrokeColor(_muted)
              ..setLineWidth(.7)
              ..drawLine(left, slaY, left + width, slaY)
              ..strokePath();
            final plotted = values.length > 180
                ? [
                    for (var i = 0; i < 180; i++)
                      values[(i * (values.length - 1) / 179).round()],
                  ]
                : values;
            canvas
              ..setStrokeColor(_accent)
              ..setLineWidth(1.55);
            for (var i = 0; i < plotted.length; i++) {
              final x =
                  left +
                  width * (plotted.length == 1 ? .5 : i / (plotted.length - 1));
              final y = bottom + height * plotted[i] / maximum;
              if (i == 0) {
                canvas.moveTo(x, y);
              } else {
                canvas.lineTo(x, y);
              }
            }
            canvas.strokePath();
            if (plotted.length <= 35) {
              for (var i = 0; i < plotted.length; i++) {
                final x =
                    left +
                    width *
                        (plotted.length == 1 ? .5 : i / (plotted.length - 1));
                final y = bottom + height * plotted[i] / maximum;
                canvas
                  ..setFillColor(_accent)
                  ..drawEllipse(x, y, 1.8, 1.8)
                  ..fillPath();
              }
            }
          },
        ),
      ],
    );
  }

  static pw.Widget _histogram(List<FrequencyClass> bins) => pw.CustomPaint(
    size: const PdfPoint(500, 118),
    painter: (canvas, size) {
      const bottom = 8.0;
      final width = size.x - 10;
      final height = size.y - 16;
      final maximum = bins.map((b) => b.frequency).reduce(math.max);
      canvas
        ..setStrokeColor(_line)
        ..setLineWidth(.6)
        ..drawLine(5, bottom, 5 + width, bottom)
        ..strokePath();
      final step = width / bins.length;
      for (var i = 0; i < bins.length; i++) {
        final barWidth = step * .62;
        final barHeight = maximum == 0
            ? 0.0
            : bins[i].frequency / maximum * height;
        canvas
          ..setFillColor(i.isEven ? _accent : _muted)
          ..drawRect(
            5 + i * step + (step - barWidth) / 2,
            bottom,
            barWidth,
            barHeight,
          )
          ..fillPath();
      }
    },
  );

  static pw.Widget _clientBars(Map<String, AnalysisSummary> clients) {
    final values = clients.entries
        .where((e) => e.value.stats.mean != null)
        .toList();
    if (values.isEmpty) {
      return _empty('No hay RTT válido por cliente para comparar.');
    }
    final maximum = math.max(
      .000001,
      values.map((e) => e.value.stats.mean!).reduce(math.max),
    );
    return pw.Column(
      children: [
        for (final entry in values)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(
              children: [
                pw.SizedBox(
                  width: 87,
                  child: pw.Text(
                    _short(entry.key),
                    style: const pw.TextStyle(fontSize: 7, color: _ink),
                  ),
                ),
                pw.Container(
                  width: math.max(2, 290 * entry.value.stats.mean! / maximum),
                  height: 8,
                  color: _accent,
                ),
                pw.SizedBox(width: 8),
                pw.Text(
                  _ms(entry.value.stats.mean),
                  style: const pw.TextStyle(fontSize: 7, color: _muted),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static pw.Widget _distanceRanges(Map<String, AnalysisSummary> clients) {
    final values = clients.entries
        .where((entry) => entry.value.medianDistanceM != null)
        .toList();
    final maximum = math.max(
      1.0,
      values
          .map(
            (entry) =>
                entry.value.medianDistanceM! +
                (entry.value.maxUncertaintyM ?? 0),
          )
          .reduce(math.max),
    );
    return pw.Column(
      children: [
        for (final entry in values)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 7),
            child: pw.Row(
              children: [
                pw.SizedBox(
                  width: 87,
                  child: pw.Text(
                    _short(entry.key),
                    style: const pw.TextStyle(fontSize: 8, color: _ink),
                  ),
                ),
                pw.CustomPaint(
                  size: const PdfPoint(280, 14),
                  painter: (canvas, size) {
                    final center = entry.value.medianDistanceM!;
                    final margin = entry.value.maxUncertaintyM ?? 0;
                    final lower =
                        math.max(0, center - margin) / maximum * size.x;
                    final upper =
                        math.min(maximum, center + margin) / maximum * size.x;
                    final point = center / maximum * size.x;
                    canvas
                      ..setStrokeColor(_line)
                      ..setLineWidth(.7)
                      ..drawLine(0, 7, size.x, 7)
                      ..strokePath()
                      ..setStrokeColor(_accent)
                      ..setLineWidth(2)
                      ..drawLine(lower, 7, upper, 7)
                      ..strokePath()
                      ..setFillColor(_accent)
                      ..drawEllipse(point, 7, 3, 3)
                      ..fillPath();
                  },
                ),
                pw.SizedBox(width: 8),
                pw.Text(
                  '${entry.value.medianDistanceM!.toStringAsFixed(2)}${entry.value.maxUncertaintyM == null ? '' : ' ±${entry.value.maxUncertaintyM!.toStringAsFixed(2)}'} m',
                  style: const pw.TextStyle(fontSize: 8, color: _muted),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
