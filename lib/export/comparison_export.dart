import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../data/lab_repository.dart';
import '../science/session_comparison.dart';
import 'comparison_pdf.dart';
import 'export_service.dart';

class ComparisonExportService {
  const ComparisonExportService(this.repository);

  final LabRepository repository;

  SessionComparison compare(List<String> sessionIds) {
    final sessions = {
      for (final session in repository.sessions()) session.id: session,
    };
    if (sessionIds.any((id) => !sessions.containsKey(id))) {
      throw ArgumentError('Una sesión seleccionada ya no existe.');
    }
    return SessionComparison([
      for (final id in sessionIds)
        (session: sessions[id]!, items: repository.measurements(id)),
    ]);
  }

  String json(List<String> sessionIds) {
    final comparison = compare(sessionIds);
    final exporter = ExportService(repository);
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'LANXIS multi-session comparison',
      'format_version': 1,
      'app_version': ExportService.appVersion,
      'protocol_version': ExportService.protocolVersion,
      'exported_utc': DateTime.now().toUtc().toIso8601String(),
      'comparison': comparison.toJson(),
      'source_sessions': [
        for (final entry in comparison.entries)
          jsonDecode(exporter.json(entry.session.id)),
      ],
    });
  }

  String csv(List<String> sessionIds) {
    final comparison = compare(sessionIds);
    final exportedUtc = DateTime.now().toUtc().toIso8601String();
    final buffer = StringBuffer(
      'app_version,protocol_version,exported_utc,baseline_session_id,alcance,session_id,session_name,n_total,n_valid,n_failed,mean_latency_ms,median_latency_ms,p95_latency_ms,sla_probability,mean_difference_from_baseline_ms,protocols,scenarios\r\n',
    );
    void row(
      String scope,
      String id,
      String name,
      int total,
      int valid,
      int failed,
      double? mean,
      double? median,
      double? p95,
      double? sla,
      double? difference,
      Iterable<String> protocols,
      Iterable<String> scenarios,
    ) {
      buffer.writeln(
        [
          ExportService.appVersion,
          ExportService.protocolVersion,
          exportedUtc,
          comparison.baseline.session.id,
          scope,
          id,
          name,
          total,
          valid,
          failed,
          mean,
          median,
          p95,
          sla,
          difference,
          protocols.join('; '),
          scenarios.join('; '),
        ].map(_csvCell).join(','),
      );
    }

    for (final entry in comparison.entries) {
      final mean = entry.summary.stats.mean;
      final baselineMean = comparison.baseline.summary.stats.mean;
      row(
        'session',
        entry.session.id,
        entry.session.name,
        entry.summary.total,
        entry.summary.valid,
        entry.summary.failed,
        mean,
        entry.summary.stats.median,
        entry.summary.stats.p95,
        entry.summary.sla,
        mean == null || baselineMean == null ? null : mean - baselineMean,
        entry.protocols,
        entry.scenarios,
      );
    }
    row(
      'pooled_raw',
      '',
      'Todas las sesiones seleccionadas',
      comparison.pooled.total,
      comparison.pooled.valid,
      comparison.pooled.failed,
      comparison.pooled.stats.mean,
      comparison.pooled.stats.median,
      comparison.pooled.stats.p95,
      comparison.pooled.sla,
      null,
      comparison.entries.expand((entry) => entry.protocols).toSet(),
      comparison.entries.expand((entry) => entry.scenarios).toSet(),
    );
    return buffer.toString();
  }

  String html(List<String> sessionIds) {
    final comparison = compare(sessionIds);
    String cell(Object? value) => _escapeHtml(value?.toString() ?? '—');
    String number(double? value) =>
        value == null ? '—' : value.toStringAsFixed(2);
    String percent(double? value) =>
        value == null ? '—' : '${(value * 100).toStringAsFixed(1)} %';
    final maxMean = comparison.entries
        .map((entry) => entry.summary.stats.mean ?? 0)
        .fold<double>(1, (a, b) => a > b ? a : b);
    return '''<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>LANXIS · Comparación de sesiones</title>
<style>body{font-family:system-ui,sans-serif;max-width:920px;margin:auto;padding:2rem;background:#f3f8fa;color:#21383f}h1,h2{letter-spacing:-.035em}section{background:white;border-radius:16px;padding:1.4rem;margin:1rem 0;border:1px solid #d9e5e9}table{border-collapse:collapse;width:100%}td,th{padding:.6rem;border-bottom:1px solid #d9e5e9;text-align:left}.bar{height:.6rem;border-radius:1rem;background:#dfeaec}.bar span{display:block;height:100%;border-radius:1rem;background:#337d8c}.muted{color:#667b80}</style></head><body>
<h1>LANXIS · Comparación de sesiones</h1><p class="muted">Versión ${ExportService.appVersion} · Protocolo ${ExportService.protocolVersion} · Exportado ${DateTime.now().toUtc().toIso8601String()} UTC</p>
<section><h2>Lectura conjunta</h2><p>${comparison.entries.length} sesiones, ${comparison.pooled.total} intentos y ${comparison.pooled.valid} RTT válidos. Media ${number(comparison.pooled.stats.mean)} ms; P95 ${number(comparison.pooled.stats.p95)} ms; SLA ${percent(comparison.pooled.sla)}. Los resultados se recalculan desde las observaciones originales.</p></section>
<section><h2>Por sesión</h2><table><thead><tr><th>Sesión</th><th>n / válidas</th><th>Fallos</th><th>Media ms</th><th>P95 ms</th><th>SLA</th></tr></thead><tbody>${comparison.entries.map((entry) => '<tr><td>${cell(entry.session.name)}<br><small>${cell(entry.session.id)}</small></td><td>${entry.summary.total} / ${entry.summary.valid}</td><td>${entry.summary.failed}</td><td>${number(entry.summary.stats.mean)}</td><td>${number(entry.summary.stats.p95)}</td><td>${percent(entry.summary.sla)}</td></tr>').join()}</tbody></table></section>
<section><h2>RTT medio</h2>${comparison.entries.map((entry) => '<p>${cell(entry.session.name)} · ${number(entry.summary.stats.mean)} ms</p><div class="bar"><span style="width:${(((entry.summary.stats.mean ?? 0) / maxMean) * 100).clamp(0, 100).toStringAsFixed(1)}%"></span></div>').join()}</section>
<section><h2>Interpretación y límites</h2><p>Sesión de referencia: ${cell(comparison.baseline.session.name)}. Las diferencias entre promedios son descriptivas; no son pruebas de significancia.</p><ul>${comparison.warnings.map((warning) => '<li>${cell(warning)}</li>').join()}</ul><p>RTT por protocolo con reloj monotónico local; calentamientos excluidos; cuartiles tipo 7, varianza muestral n−1 y SLA estricto RTT &lt; 50 ms. Una respuesta fallida no recibe latencia inventada.</p></section>
</body></html>''';
  }

  Future<Uint8List> pdf(List<String> sessionIds) => ComparisonPdfBuilder.build(
    compare(sessionIds),
    appVersion: ExportService.appVersion,
    protocolVersion: ExportService.protocolVersion,
  );

  Future<Uint8List> zip(List<String> sessionIds) async {
    final comparison = compare(sessionIds);
    final exporter = ExportService(repository);
    final files = <String, List<int>>{
      'comparacion.json': utf8.encode(json(sessionIds)),
      'comparacion.csv': utf8.encode(csv(sessionIds)),
      'comparacion.html': utf8.encode(html(sessionIds)),
      'comparacion.pdf': await pdf(sessionIds),
      for (var index = 0; index < comparison.entries.length; index++) ...{
        'sesiones/${index + 1}/session.json': utf8.encode(
          exporter.json(comparison.entries[index].session.id),
        ),
        'sesiones/${index + 1}/datos_hotspot.csv': utf8.encode(
          exporter.csv(comparison.entries[index].session.id),
        ),
      },
    };
    final archive = Archive();
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
    }
    archive.addFile(
      ArchiveFile.string(
        'manifest.json',
        const JsonEncoder.withIndent('  ').convert({
          'format': 'LANXIS multi-session research bundle',
          'format_version': 1,
          'app_version': ExportService.appVersion,
          'protocol_version': ExportService.protocolVersion,
          'created_utc': DateTime.now().toUtc().toIso8601String(),
          'session_ids': [
            for (final entry in comparison.entries) entry.session.id,
          ],
          'files': {
            for (final entry in files.entries)
              entry.key: {
                'sha256': sha256.convert(entry.value).toString(),
                'bytes': entry.value.length,
              },
          },
        }),
      ),
    );
    return ZipEncoder().encodeBytes(archive);
  }

  Future<String?> save(
    List<String> sessionIds, {
    required String format,
  }) async {
    if (!{'csv', 'json', 'html', 'pdf', 'zip'}.contains(format)) {
      throw ArgumentError.value(format);
    }
    final content = switch (format) {
      'csv' => utf8.encode(csv(sessionIds)),
      'json' => utf8.encode(json(sessionIds)),
      'html' => utf8.encode(html(sessionIds)),
      'pdf' => await pdf(sessionIds),
      'zip' => await zip(sessionIds),
      _ => throw ArgumentError.value(format),
    };
    final mime = switch (format) {
      'csv' => 'text/csv',
      'json' => 'application/json',
      'html' => 'text/html',
      'pdf' => 'application/pdf',
      'zip' => 'application/zip',
      _ => 'application/octet-stream',
    };
    final suggestedName = 'lanxis_comparacion.$format';
    if (Platform.isAndroid) {
      final directory = await getTemporaryDirectory();
      final temporary = File(
        '${directory.path}/lanxis-comparison-${DateTime.now().microsecondsSinceEpoch}.$format',
      );
      try {
        await temporary.writeAsBytes(content, flush: true);
        return await const MethodChannel('mx.lanxis/export')
            .invokeMethod<String>('saveDocument', {
              'name': suggestedName,
              'mime': mime,
              'path': temporary.path,
            });
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    }
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [
        XTypeGroup(label: format.toUpperCase(), extensions: [format]),
      ],
    );
    if (location == null) return null;
    await XFile.fromData(content, mimeType: mime).saveTo(location.path);
    return location.path;
  }

  static String _csvCell(Object? value) {
    if (value == null) return '';
    final text = value.toString();
    if (!text.contains(RegExp('[,"\r\n]'))) return text;
    return '"${text.replaceAll('"', '""')}"';
  }

  static String _escapeHtml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
