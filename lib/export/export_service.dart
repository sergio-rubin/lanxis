import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/lab_repository.dart';
import '../core/models.dart';
import '../science/descriptive.dart';

class ExportScope {
  const ExportScope({this.phaseId, this.testId, this.trialId});
  final String? phaseId;
  final String? testId;
  final String? trialId;

  bool matches(Measurement item) =>
      (phaseId == null || item.phaseId == phaseId) &&
      (testId == null || item.testId == testId) &&
      (trialId == null || item.trialId == trialId);

  Map<String, Object?> toJson() => {
    if (phaseId != null) 'phase_id': phaseId,
    if (testId != null) 'test_id': testId,
    if (trialId != null) 'trial_id': trialId,
  };
}

class ExportService {
  const ExportService(this.repository);
  final LabRepository repository;

  List<Measurement> _items(
    String sessionId,
    ExportScope scope, {
    bool includeWarmup = false,
  }) => repository
      .measurements(sessionId, includeWarmup: includeWarmup)
      .where(scope.matches)
      .toList();

  static const legacyColumns = [
    'id_escenario',
    'clientes',
    'distancia_m',
    'rssi_dbm',
    'latencia_ms',
    'jitter_ms',
    'velocidad_mbps',
    'exito_sla',
    'calidad_red',
    'tipo_anomalia',
  ];

  String csv(
    String sessionId, {
    bool enriched = false,
    ExportScope scope = const ExportScope(),
  }) {
    final items = _items(sessionId, scope);
    final columns = enriched
        ? [
            ...legacyColumns,
            'session_id',
            'phase_id',
            'test_id',
            'trial_id',
            'request_id',
            'timestamp_utc',
            'protocolo',
            'bytes_recibidos',
            'bytes_enviados',
            'http_status',
            'error',
            'client_id',
            'success',
          ]
        : legacyColumns;
    final buffer = StringBuffer('${columns.join(',')}\r\n');
    for (final item in items) {
      final row = item.toJson();
      buffer.writeln(columns.map((name) => _csvCell(row[name])).join(','));
    }
    return buffer.toString();
  }

  String json(String sessionId, {ExportScope scope = const ExportScope()}) {
    final session = repository.sessions().firstWhere((s) => s.id == sessionId);
    final measurements = _items(sessionId, scope, includeWarmup: true);
    final allTrials = repository.trialsForSession(sessionId);
    final scopedTrialTestIds = scope.trialId == null
        ? null
        : allTrials
              .where((trial) => trial['id'] == scope.trialId)
              .map((trial) => trial['test_id'])
              .toSet();
    final tests = repository
        .testsForSession(sessionId)
        .where(
          (t) =>
              (scope.phaseId == null || t['phase_id'] == scope.phaseId) &&
              (scope.testId == null || t['id'] == scope.testId) &&
              (scopedTrialTestIds == null ||
                  scopedTrialTestIds.contains(t['id'])),
        )
        .toList();
    final phaseIds = tests.map((t) => t['phase_id']).toSet();
    final phases = repository
        .phases(sessionId)
        .where(
          (p) =>
              (scope.phaseId == null || p.id == scope.phaseId) &&
              ((scope.testId == null && scope.trialId == null) ||
                  phaseIds.contains(p.id)),
        )
        .toList();
    final testIds = tests.map((t) => t['id']).toSet();
    final trials = allTrials
        .where(
          (t) =>
              testIds.contains(t['test_id']) &&
              (scope.trialId == null || t['id'] == scope.trialId),
        )
        .toList();
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'LANXIS research export',
      'format_version': 1,
      'protocol_version': 1,
      'exported_utc': DateTime.now().toUtc().toIso8601String(),
      'scope': scope.toJson(),
      'session': {
        'id': session.id,
        'name': session.name,
        'created_utc': session.createdAt.toIso8601String(),
        'status': session.status,
        'notes': session.notes,
      },
      'phases': phases
          .map(
            (p) => {
              'id': p.id,
              'session_id': p.sessionId,
              'name': p.name,
              'status': p.status,
              'created_utc': p.createdAt.toIso8601String(),
            },
          )
          .toList(),
      'tests': tests,
      'trials': trials,
      'measurements': measurements.map((m) => m.toJson()).toList(),
      'events': repository
          .eventsForSession(sessionId)
          .where(
            (e) =>
                (scope.phaseId == null || e['phase_id'] == scope.phaseId) &&
                (scope.testId == null || e['test_id'] == scope.testId) &&
                (scope.trialId == null || e['trial_id'] == scope.trialId),
          )
          .toList(),
      'summary': _summary(sessionId, scope),
      'definitions': {
        'latency_ms': 'Application HTTP RTT using local monotonic clock',
        'jitter_ms': '|RTT_i - RTT_(i-1)| for consecutive valid observations',
        'exito_sla': '1 only if successful and latency < 50 ms',
        'warmup': 'Excluded from CSV and default analysis',
      },
    });
  }

  Map<String, Object?> _summary(String sessionId, ExportScope scope) {
    final items = _items(sessionId, scope);
    final latency = items
        .where((m) => m.success && m.latencyMs != null)
        .map((m) => m.latencyMs!);
    final stats = DescriptiveEngine.calculate(latency);
    return {
      'n_total': items.length,
      'n_valid': stats.n,
      'n_failed': items.where((m) => !m.success).length,
      'mean_latency_ms': stats.mean,
      'median_latency_ms': stats.median,
      'sample_sd_ms': stats.standardDeviation,
      'p95_latency_ms': stats.p95,
      'sla_probability': DescriptiveEngine.successRate(items),
      'method': 'Quartiles type 7; sample variance n-1; SLA strict < 50 ms',
    };
  }

  String jsonl(String sessionId, {ExportScope scope = const ExportScope()}) {
    final lines = <String>[
      jsonEncode({
        'type': 'manifest',
        'format_version': 1,
        'session_id': sessionId,
        'scope': scope.toJson(),
        'exported_utc': DateTime.now().toUtc().toIso8601String(),
      }),
      for (final item in _items(sessionId, scope, includeWarmup: true))
        jsonEncode({'type': 'measurement', ...item.toJson()}),
      for (final event
          in repository
              .eventsForSession(sessionId)
              .where(
                (e) =>
                    (scope.phaseId == null || e['phase_id'] == scope.phaseId) &&
                    (scope.testId == null || e['test_id'] == scope.testId) &&
                    (scope.trialId == null || e['trial_id'] == scope.trialId),
              ))
        jsonEncode({'type': 'event', ...event}),
    ];
    return '${lines.join('\n')}\n';
  }

  String html(String sessionId, {ExportScope scope = const ExportScope()}) {
    final session = repository.sessions().firstWhere((s) => s.id == sessionId);
    final summary = _summary(sessionId, scope);
    final items = _items(sessionId, scope);
    final bins = DescriptiveEngine.frequency(
      items
          .where((m) => m.success && m.latencyMs != null)
          .map((m) => m.latencyMs!),
    );
    final maxCount = bins.isEmpty
        ? 1
        : bins.map((b) => b.frequency).reduce((a, b) => a > b ? a : b);
    String cell(Object? value) => _escapeHtml(value?.toString() ?? '—');
    return '''<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>LANXIS · ${cell(session.name)}</title><style>
body{font-family:system-ui,sans-serif;max-width:900px;margin:auto;padding:2rem;background:#f3f8fb;color:#123042}
h1,h2{letter-spacing:-.04em}section{background:white;border-radius:18px;padding:1.5rem;margin:1rem 0;box-shadow:0 8px 28px #153e5310}
table{border-collapse:collapse;width:100%}td,th{padding:.6rem;border-bottom:1px solid #d9e5eb;text-align:left}
svg{width:100%;height:auto}.muted{color:#587481}</style></head><body>
<h1>LANXIS · ${cell(session.name)}</h1>
<p class="muted">Sesión ${cell(session.id)} · Exportado ${DateTime.now().toUtc().toIso8601String()} UTC</p>
<p class="muted">Alcance: ${cell(scope.toJson().isEmpty ? 'Sesión completa' : scope.toJson())}</p>
<section><h2>Metodología</h2><p>RTT HTTP de aplicación con reloj monotónico local. Calentamientos excluidos del análisis. Fallos incluidos en el denominador del SLA. Cuartiles tipo 7, varianza muestral n−1 y criterio SLA estricto de latencia &lt; 50 ms.</p></section>
<section><h2>Resultados</h2><table><tbody>
${summary.entries.map((e) => '<tr><th>${cell(e.key)}</th><td>${cell(e.value)}</td></tr>').join()}
</tbody></table></section>
<section><h2>Distribución de latencia</h2><svg viewBox="0 0 700 240" role="img" aria-label="Histograma de latencias">
${[for (var i = 0; i < bins.length; i++) '<rect x="${45 + i * 90}" y="${200 - bins[i].frequency / maxCount * 170}" width="60" height="${bins[i].frequency / maxCount * 170}" fill="#3a8ca8" rx="5"/><text x="${55 + i * 90}" y="220" fill="#123042">${i + 1}</text>'].join()}
</svg><p>Clases ordenadas de menor a mayor latencia. n válido: ${bins.fold<int>(0, (sum, b) => sum + b.frequency)}.</p></section>
<section><h2>Limitaciones</h2><p>Las mediciones dependen del sistema operativo, hardware y carga del dispositivo. La distancia es una condición declarada. En ensayos coordinados, los clientes son participantes registrados; interpreta causalidad solo si el diseño experimental controló los factores de confusión.</p></section>
</body></html>''';
  }

  static String _escapeHtml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  Future<Uint8List> zip(
    String sessionId, {
    ExportScope scope = const ExportScope(),
  }) async {
    final csvBytes = utf8.encode(csv(sessionId, scope: scope));
    final enrichedBytes = utf8.encode(
      csv(sessionId, enriched: true, scope: scope),
    );
    final jsonBytes = utf8.encode(json(sessionId, scope: scope));
    final jsonlBytes = utf8.encode(jsonl(sessionId, scope: scope));
    final htmlBytes = utf8.encode(html(sessionId, scope: scope));
    final xlsxBytes = xlsx(sessionId, scope: scope);
    final pdfBytes = await pdf(sessionId, scope: scope);
    final files = <String, List<int>>{
      'datos_hotspot.csv': csvBytes,
      'datos_enriquecidos.csv': enrichedBytes,
      'session.json': jsonBytes,
      'records.jsonl': jsonlBytes,
      'report.html': htmlBytes,
      'workbook.xlsx': xlsxBytes,
      'report.pdf': pdfBytes,
    };
    final manifest = jsonEncode({
      'format': 'LANXIS research bundle',
      'version': 1,
      'session_id': sessionId,
      'scope': scope.toJson(),
      'created_utc': DateTime.now().toUtc().toIso8601String(),
      'files': {
        for (final entry in files.entries)
          entry.key: {
            'sha256': sha256.convert(entry.value).toString(),
            'bytes': entry.value.length,
          },
      },
    });
    final archive = Archive();
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
    }
    archive.addFile(ArchiveFile.string('manifest.json', manifest));
    return ZipEncoder().encodeBytes(archive);
  }

  Uint8List xlsx(String sessionId, {ExportScope scope = const ExportScope()}) {
    final measurements = _items(sessionId, scope);
    final trialTestIds = scope.trialId == null
        ? null
        : repository
              .trialsForSession(sessionId)
              .where((trial) => trial['id'] == scope.trialId)
              .map((trial) => trial['test_id'])
              .toSet();
    final tests = repository
        .testsForSession(sessionId)
        .where(
          (t) =>
              (scope.phaseId == null || t['phase_id'] == scope.phaseId) &&
              (scope.testId == null || t['id'] == scope.testId) &&
              (trialTestIds == null || trialTestIds.contains(t['id'])),
        )
        .toList();
    final summary = _summary(sessionId, scope);
    final frequencies = DescriptiveEngine.frequency(
      measurements
          .where((m) => m.success && m.latencyMs != null)
          .map((m) => m.latencyMs!),
    );
    final sheets = <String, List<List<Object?>>>{
      'Datos': [
        [
          ...legacyColumns,
          'session_id',
          'phase_id',
          'test_id',
          'trial_id',
          'request_id',
          'timestamp_utc',
          'protocolo',
          'bytes_recibidos',
          'bytes_enviados',
          'http_status',
          'error',
          'client_id',
          'success',
        ],
        for (final m in measurements)
          [
            for (final column in [
              ...legacyColumns,
              'session_id',
              'phase_id',
              'test_id',
              'trial_id',
              'request_id',
              'timestamp_utc',
              'protocolo',
              'bytes_recibidos',
              'bytes_enviados',
              'http_status',
              'error',
              'client_id',
              'success',
            ])
              m.toJson()[column],
          ],
      ],
      'Configuraciones': [
        ['test_id', 'phase_id', 'name', 'config_json', 'created_utc'],
        for (final row in tests)
          [
            for (final key in [
              'id',
              'phase_id',
              'name',
              'config_json',
              'created_utc',
            ])
              row[key],
          ],
      ],
      'Resultados': [
        ['indicador', 'valor'],
        for (final entry in summary.entries) [entry.key, entry.value],
      ],
      'Estadisticas': [
        [
          'limite_inferior_ms',
          'limite_superior_ms',
          'frecuencia',
          'frecuencia_relativa',
          'acumulada',
        ],
        for (final bin in frequencies)
          [bin.lower, bin.upper, bin.frequency, bin.relative, bin.cumulative],
      ],
    };
    final archive = Archive();
    void add(String name, String content) =>
        archive.addFile(ArchiveFile.string(name, content));
    add(
      '[Content_Types].xml',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
${[for (var i = 1; i <= sheets.length; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}
</Types>''',
    );
    add(
      '_rels/.rels',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''',
    );
    add(
      'xl/workbook.xml',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets>${[for (var i = 0; i < sheets.length; i++) '<sheet name="${_escapeXml(sheets.keys.elementAt(i))}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}</sheets>
</workbook>''',
    );
    add(
      'xl/_rels/workbook.xml.rels',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
${[for (var i = 1; i <= sheets.length; i++) '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>'].join()}
<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''',
    );
    add(
      'xl/styles.xml',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font><sz val="11"/><name val="Aptos"/></font></fonts><fills count="1"><fill><patternFill patternType="none"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs></styleSheet>''',
    );
    for (var i = 0; i < sheets.length; i++) {
      final rows = sheets.values.elementAt(i);
      add(
        'xl/worksheets/sheet${i + 1}.xml',
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
${[
          for (var r = 0; r < rows.length; r++) '<row r="${r + 1}">${[for (var c = 0; c < rows[r].length; c++) _xlsxCell(c, r, rows[r][c])].join()}</row>',
        ].join()}
</sheetData></worksheet>''',
      );
    }
    return ZipEncoder().encodeBytes(archive);
  }

  static String _xlsxCell(int column, int row, Object? value) {
    if (value == null) return '';
    var n = column + 1;
    var letter = '';
    while (n > 0) {
      n--;
      letter = String.fromCharCode(65 + n % 26) + letter;
      n ~/= 26;
    }
    final ref = '$letter${row + 1}';
    if (value is num && value.isFinite) {
      return '<c r="$ref"><v>$value</v></c>';
    }
    return '<c r="$ref" t="inlineStr"><is><t>${_escapeXml(value.toString())}</t></is></c>';
  }

  static String _escapeXml(String text) =>
      _escapeHtml(text).replaceAll("'", '&apos;');

  Future<Uint8List> pdf(
    String sessionId, {
    ExportScope scope = const ExportScope(),
  }) async {
    final session = repository.sessions().firstWhere((s) => s.id == sessionId);
    final summary = _summary(sessionId, scope);
    final fontData = await rootBundle.load('assets/fonts/Manrope.ttf');
    final font = pw.Font.ttf(fontData);
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        build: (_) => [
          pw.Text(
            'LANXIS',
            style: pw.TextStyle(fontSize: 28, color: PdfColors.blueGrey900),
          ),
          pw.SizedBox(height: 8),
          pw.Text(session.name, style: const pw.TextStyle(fontSize: 19)),
          pw.Text(
            'Sesión ${session.id} · ${DateTime.now().toUtc().toIso8601String()} UTC',
          ),
          pw.Text(
            'Alcance: ${scope.toJson().isEmpty ? 'Sesión completa' : scope.toJson()}',
          ),
          pw.SizedBox(height: 20),
          pw.Header(level: 1, text: 'Metodología'),
          pw.Text(
            'RTT HTTP de aplicación medido con reloj monotónico. Muestras de calentamiento excluidas. Fallos conservados para SLA. Cuartiles tipo 7; varianza muestral n−1; SLA estricto menor que 50 ms.',
          ),
          pw.Header(level: 1, text: 'Resumen de resultados'),
          pw.TableHelper.fromTextArray(
            headers: ['Indicador', 'Valor'],
            data: [
              for (final entry in summary.entries)
                [entry.key, '${entry.value ?? '—'}'],
            ],
          ),
          pw.Header(level: 1, text: 'Limitaciones'),
          pw.Text(
            'La carga del dispositivo, el sistema operativo y el entorno radioeléctrico pueden afectar los resultados. La distancia requiere control experimental externo; en ensayos coordinados los clientes son participantes registrados.',
          ),
        ],
      ),
    );
    return document.save();
  }

  static String _csvCell(Object? value) {
    if (value == null) return '';
    final text = value.toString();
    if (!text.contains(RegExp('[,"\r\n]'))) return text;
    return '"${text.replaceAll('"', '""')}"';
  }

  Future<String?> save(
    String sessionId, {
    required String format,
    bool enriched = false,
    ExportScope scope = const ExportScope(),
  }) async {
    if (!{
      'csv',
      'json',
      'jsonl',
      'html',
      'zip',
      'pdf',
      'xlsx',
    }.contains(format)) {
      throw ArgumentError.value(format);
    }
    final extension = format;
    final location = await getSaveLocation(
      suggestedName: format == 'csv'
          ? (enriched ? 'datos_enriquecidos.csv' : 'datos_hotspot.csv')
          : 'lanxis_session.$extension',
      acceptedTypeGroups: [
        XTypeGroup(label: format.toUpperCase(), extensions: [extension]),
      ],
    );
    if (location == null) return null;
    final content = switch (format) {
      'csv' => utf8.encode(csv(sessionId, enriched: enriched, scope: scope)),
      'json' => utf8.encode(json(sessionId, scope: scope)),
      'jsonl' => utf8.encode(jsonl(sessionId, scope: scope)),
      'html' => utf8.encode(html(sessionId, scope: scope)),
      'zip' => await zip(sessionId, scope: scope),
      'xlsx' => xlsx(sessionId, scope: scope),
      'pdf' => await pdf(sessionId, scope: scope),
      _ => throw ArgumentError.value(format),
    };
    await XFile.fromData(
      content,
      mimeType: switch (format) {
        'csv' => 'text/csv',
        'json' => 'application/json',
        'jsonl' => 'application/x-ndjson',
        'html' => 'text/html',
        'zip' => 'application/zip',
        'xlsx' =>
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'pdf' => 'application/pdf',
        _ => 'application/octet-stream',
      },
    ).saveTo(location.path);
    repository.addEvent(
      'export_$format',
      sessionId: sessionId,
      metadataJson: jsonEncode({'enriched': enriched, 'scope': scope.toJson()}),
    );
    return location.path;
  }
}
