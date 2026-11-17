import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../science/session_comparison.dart';

/// A self-contained descriptive comparison for selected real sessions.
class ComparisonPdfBuilder {
  static const _ink = PdfColor(.13, .22, .27);
  static const _muted = PdfColor(.38, .47, .51);
  static const _accent = PdfColor(.20, .49, .55);
  static const _pale = PdfColor(.93, .96, .97);
  static const _line = PdfColor(.82, .87, .89);

  static Future<Uint8List> build(
    SessionComparison comparison, {
    required String appVersion,
    required int protocolVersion,
  }) async {
    final bodyFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Manrope.ttf'),
    );
    final headingFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/SpaceGrotesk.ttf'),
    );
    final exported = DateTime.now().toUtc().toIso8601String();
    final maxMean = comparison.entries
        .map((entry) => entry.summary.stats.mean ?? 0)
        .fold<double>(1, math.max);
    final document = pw.Document();
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
              pw.Text(
                'LANXIS  /  COMPARACIÓN DE SESIONES',
                style: pw.TextStyle(
                  font: headingFont,
                  fontSize: 8.5,
                  color: _ink,
                ),
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
                'Exportado $exported UTC',
                style: const pw.TextStyle(fontSize: 7, color: _muted),
              ),
              pw.Text(
                '${context.pageNumber} / ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 7, color: _muted),
              ),
            ],
          ),
        ),
        build: (context) => [
          pw.SizedBox(height: 16),
          pw.Text(
            'Sesiones bajo la misma lupa',
            style: pw.TextStyle(font: headingFont, fontSize: 25, color: _ink),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            '${comparison.entries.length} sesiones · ${comparison.pooled.total} intentos · ${comparison.pooled.valid} RTT válidos',
            style: const pw.TextStyle(fontSize: 9.5, color: _muted),
          ),
          pw.SizedBox(height: 18),
          pw.Container(
            padding: const pw.EdgeInsets.all(13),
            decoration: const pw.BoxDecoration(
              color: _pale,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(9)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'LECTURA CONJUNTA',
                  style: pw.TextStyle(
                    font: headingFont,
                    fontSize: 8,
                    color: _accent,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  'RTT medio ${_number(comparison.pooled.stats.mean)} ms · P95 ${_number(comparison.pooled.stats.p95)} ms · SLA ${_percent(comparison.pooled.sla)}. Estas cifras se recalculan desde cada observación original; los fallos cuentan en el SLA y no se les inventa RTT.',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: _ink,
                    lineSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          _section('01', 'Resumen por sesión', headingFont),
          pw.SizedBox(height: 9),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Sesión',
              'n / válidas',
              'Fallos',
              'Media ms',
              'P95 ms',
              'SLA',
            ],
            data: [
              for (final entry in comparison.entries)
                [
                  entry.session.name,
                  '${entry.summary.total} / ${entry.summary.valid}',
                  '${entry.summary.failed}',
                  _number(entry.summary.stats.mean),
                  _number(entry.summary.stats.p95),
                  _percent(entry.summary.sla),
                ],
            ],
            border: null,
            headerStyle: pw.TextStyle(
              font: headingFont,
              fontSize: 8,
              color: _ink,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8, color: _ink),
            headerDecoration: const pw.BoxDecoration(color: _pale),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 7,
              vertical: 6,
            ),
            oddRowDecoration: const pw.BoxDecoration(
              color: PdfColor(.97, .98, .98),
            ),
          ),
          pw.SizedBox(height: 17),
          _section('02', 'RTT medio por sesión', headingFont),
          pw.SizedBox(height: 5),
          pw.Text(
            'Escala relativa al mayor promedio de las sesiones seleccionadas.',
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
          pw.SizedBox(height: 9),
          for (final entry in comparison.entries)
            pw.Inseparable(
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Row(
                  children: [
                    pw.SizedBox(
                      width: 125,
                      child: pw.Text(
                        entry.session.name,
                        maxLines: 1,
                        overflow: pw.TextOverflow.clip,
                        style: const pw.TextStyle(fontSize: 8.5, color: _ink),
                      ),
                    ),
                    pw.SizedBox(
                      width: 220,
                      child: pw.Container(
                        height: 10,
                        decoration: const pw.BoxDecoration(
                          color: _pale,
                          borderRadius: pw.BorderRadius.all(
                            pw.Radius.circular(5),
                          ),
                        ),
                        child: pw.Align(
                          alignment: pw.Alignment.centerLeft,
                          child: pw.SizedBox(
                            width:
                                220 *
                                ((entry.summary.stats.mean ?? 0) / maxMean)
                                    .clamp(0, 1),
                            child: pw.Container(
                              decoration: const pw.BoxDecoration(
                                color: _accent,
                                borderRadius: pw.BorderRadius.all(
                                  pw.Radius.circular(5),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.SizedBox(
                      width: 53,
                      child: pw.Text(
                        '${_number(entry.summary.stats.mean)} ms',
                        style: const pw.TextStyle(fontSize: 8, color: _ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          pw.SizedBox(height: 14),
          _section('03', 'Interpretación y límites', headingFont),
          pw.SizedBox(height: 8),
          pw.Text(
            'Primera sesión de referencia: ${comparison.baseline.session.name} (${comparison.baseline.session.id}). La diferencia de medias se calcula con cada media descriptiva; no es una prueba de significancia.',
            style: const pw.TextStyle(
              fontSize: 8.5,
              color: _ink,
              lineSpacing: 2,
            ),
          ),
          pw.SizedBox(height: 8),
          for (final entry in comparison.entries.skip(1))
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Text(
                '${entry.session.name}: diferencia frente a referencia ${_signedDifference(entry.summary.stats.mean, comparison.baseline.summary.stats.mean)} ms; n=${entry.summary.total}, protocolos ${entry.protocols.join(', ')}, escenarios ${entry.scenarios.join(', ')}.',
                style: const pw.TextStyle(fontSize: 8.5, color: _ink),
              ),
            ),
          pw.SizedBox(height: 6),
          for (final warning in comparison.warnings)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Text(
                '· $warning',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: _muted,
                  lineSpacing: 2,
                ),
              ),
            ),
          pw.SizedBox(height: 11),
          pw.Text(
            'Método: RTT de aplicación registrado por protocolo; calentamientos excluidos. Cuantiles tipo 7, desviación estándar muestral con n−1 y SLA estricto RTT < 50 ms sobre todos los intentos. Un RTT ausente permanece sin dato. El paquete de investigación conserva muestras e identificadores para reproducir los cálculos.',
            style: const pw.TextStyle(
              fontSize: 8,
              color: _muted,
              lineSpacing: 2,
            ),
          ),
        ],
      ),
    );
    return document.save();
  }

  static pw.Widget _section(String number, String title, pw.Font headingFont) =>
      pw.Row(
        children: [
          pw.Container(
            width: 22,
            height: 22,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(
              color: _accent,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(5)),
            ),
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
            style: pw.TextStyle(font: headingFont, fontSize: 14, color: _ink),
          ),
        ],
      );

  static String _number(double? value) =>
      value == null ? '—' : value.toStringAsFixed(2);
  static String _percent(double? value) =>
      value == null ? '—' : '${(value * 100).toStringAsFixed(1)} %';
  static String _signedDifference(double? value, double? baseline) =>
      value == null || baseline == null
      ? '—'
      : '${value - baseline >= 0 ? '+' : ''}${(value - baseline).toStringAsFixed(2)}';
}
