import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import '../core/scenario_planner.dart';
import '../data/lab_repository.dart';
import '../export/export_service.dart';
import '../network/network_lab.dart';
import '../platform/hotspot_adapter.dart';
import '../science/descriptive.dart';
import '../science/inference.dart';
import '../science/modeling.dart';
import 'distribution_explorer.dart';
import 'science_charts.dart';
import 'visuals.dart';

class LabShell extends StatefulWidget {
  const LabShell({
    super.key,
    required this.repository,
    required this.network,
    required this.mode,
    required this.onModeChanged,
  });
  final LabRepository repository;
  final NetworkLab network;
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onModeChanged;
  @override
  State<LabShell> createState() => _LabShellState();
}

class _LabShellState extends State<LabShell> {
  int index = 0;
  int revision = 0;
  final PageController pages = PageController();
  static const titles = ['Inicio', 'Red local', 'Análisis', 'Acerca de'];
  static const icons = [
    Icons.space_dashboard_rounded,
    Icons.hub_rounded,
    Icons.analytics_rounded,
    Icons.info_outline_rounded,
  ];

  void refresh() => setState(() => revision++);

  void selectPage(int next) {
    if (next == index) return;
    setState(() => index = next);
    if (MediaQuery.disableAnimationsOf(context)) {
      pages.jumpToPage(next);
    } else {
      pages.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  void openSession(LabSession item) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    Navigator.of(context)
        .push(
          PageRouteBuilder<void>(
            pageBuilder: (_, animation, _) => SessionPage(
              session: item,
              repository: widget.repository,
              onChanged: refresh,
            ),
            transitionsBuilder: (_, animation, _, child) => SlideTransition(
              position: Tween(begin: const Offset(.08, 0), end: Offset.zero)
                  .animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: FadeTransition(opacity: animation, child: child),
            ),
            transitionDuration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 350),
          ),
        )
        .then((_) => refresh());
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 850;
    final theme = Theme.of(context);
    final screens = [
      Dashboard(
        repository: widget.repository,
        onChanged: refresh,
        onOpenSession: openSession,
      ),
      NetworkScreen(
        repository: widget.repository,
        network: widget.network,
        onChanged: refresh,
      ),
      AnalysisScreen(repository: widget.repository, revision: revision),
      AboutScreen(mode: widget.mode, onModeChanged: widget.onModeChanged),
    ];
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: MathBackground()),
          SafeArea(
            child: Row(
              children: [
                if (wide)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 0, 18),
                    child: SizedBox(
                      width: 234,
                      child: AcrylicPanel(
                        blur: true,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const GaussianMark(size: 36),
                                const SizedBox(width: 10),
                                Text(
                                  'LANXIS',
                                  style: theme.textTheme.titleLarge,
                                ),
                              ],
                            ),
                            const SizedBox(height: 44),
                            for (var i = 0; i < titles.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _NavItem(
                                  label: titles[i],
                                  icon: icons[i],
                                  selected: i == index,
                                  onTap: () => selectPage(i),
                                ),
                              ),
                            const Spacer(),
                            Text(
                              'LABORATORIO LOCAL',
                              style: theme.textTheme.labelSmall,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'v0.1 · sin nube',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          wide ? 32 : 20,
                          22,
                          wide ? 36 : 20,
                          10,
                        ),
                        child: Row(
                          children: [
                            if (!wide) ...[
                              const GaussianMark(size: 31),
                              const SizedBox(width: 9),
                            ],
                            Text(
                              wide ? titles[index] : 'LANXIS',
                              style: theme.textTheme.titleLarge,
                            ),
                            const Spacer(),
                            if (!wide)
                              Text(
                                titles[index],
                                style: theme.textTheme.labelMedium,
                              ),
                            const SizedBox(width: 12),
                            IconButton(
                              tooltip: 'Cambiar tema',
                              onPressed: () => widget.onModeChanged(
                                theme.brightness == Brightness.dark
                                    ? ThemeMode.light
                                    : ThemeMode.dark,
                              ),
                              icon: Icon(
                                theme.brightness == Brightness.dark
                                    ? Icons.light_mode_outlined
                                    : Icons.dark_mode_outlined,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: PageView(
                          controller: pages,
                          onPageChanged: (next) => setState(() => index = next),
                          children: screens,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : GeometricNavBar(
              controller: pages,
              selectedIndex: index,
              labels: titles,
              icons: icons,
              onSelected: selectPage,
            ),
    );
  }
}

class _HypothesisDetails extends StatelessWidget {
  const _HypothesisDetails({required this.result});
  final HypothesisResult result;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: Text('${result.method} · ${result.decision}'),
    subtitle: Text(
      'p = ${result.pValue.toStringAsPrecision(4)} · n = ${result.sampleSize}',
    ),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('H₀: ${result.nullHypothesis}'),
            Text('H₁: ${result.alternativeHypothesis}'),
            Text('Supuestos: ${result.assumptions}'),
            Text(
              'α = ${result.alpha}; estadístico = ${result.statistic.toStringAsPrecision(4)}; gl = ${result.degreesOfFreedom?.toStringAsPrecision(4) ?? 'no aplica'}',
            ),
            Text(
              'Valor crítico = ${result.criticalValue.toStringAsPrecision(4)}; región de rechazo: ${result.rejectionRegion}',
            ),
            Text(result.typeI),
            Text(result.typeII),
            if (result.warning != null) Text('Limitación: ${result.warning}'),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ],
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? Theme.of(context).colorScheme.primary.withValues(alpha: .12)
        : Colors.transparent,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 21),
            const SizedBox(width: 13),
            Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class Dashboard extends StatelessWidget {
  const Dashboard({
    super.key,
    required this.repository,
    required this.onChanged,
    required this.onOpenSession,
  });
  final LabRepository repository;
  final VoidCallback onChanged;
  final ValueChanged<LabSession> onOpenSession;

  Future<void> _newSession(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva sesión'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nombre de la investigación',
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Crear sesión'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    final item = repository.createSession(name);
    onChanged();
    if (context.mounted) onOpenSession(item);
  }

  @override
  Widget build(BuildContext context) {
    final sessions = repository.sessions();
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final count = sessions.fold<int>(
      0,
      (n, s) => n + repository.measurementCount(s.id),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 38),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 26,
                runSpacing: 26,
                children: [
                  SizedBox(
                    width: mobile ? MediaQuery.sizeOf(context).width - 48 : 510,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mobile
                              ? 'Tu red, bajo\nel microscopio.'
                              : 'Un laboratorio para\nentender tu red.',
                          style: mobile
                              ? Theme.of(context).textTheme.displayLarge
                                    ?.copyWith(fontSize: 39)
                              : Theme.of(context).textTheme.displayLarge,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Diseña experimentos, mide comunicación real entre dispositivos y conserva cada observación para un análisis verificable.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () => _newSession(context),
                          icon: const Icon(Icons.add),
                          label: const Text('Nueva sesión'),
                        ),
                      ],
                    ),
                  ),
                  if (!mobile)
                    SizedBox(
                      width: 240,
                      height: 190,
                      child: AcrylicPanel(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const GaussianMark(size: 72),
                            const SizedBox(height: 14),
                            Text(
                              'SESIÓN → MEDICIÓN',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 34),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _Metric(
                    label: 'Sesiones',
                    value: '${sessions.length}',
                    icon: Icons.folder_open_rounded,
                  ),
                  _Metric(
                    label: 'Observaciones',
                    value: '$count',
                    icon: Icons.scatter_plot_rounded,
                  ),
                  const _Metric(
                    label: 'Escenarios de referencia',
                    value: '6',
                    icon: Icons.grid_view_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 38),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text(
                    'Investigaciones',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text('${sessions.length} en este dispositivo'),
                ],
              ),
              const SizedBox(height: 16),
              if (sessions.isEmpty)
                AcrylicPanel(
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.science_outlined, size: 36),
                        const SizedBox(height: 12),
                        Text(
                          'Tu laboratorio está listo',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 7),
                        const Text(
                          'Crea una sesión para organizar fases, pruebas y ensayos. Las mediciones aparecerán aquí cuando ejecutes una prueba real.',
                        ),
                      ],
                    ),
                  ),
                )
              else
                for (final session in sessions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Hero(
                      tag: 'session-${session.id}',
                      child: Material(
                        color: Colors.transparent,
                        child: AcrylicPanel(
                          padding: EdgeInsets.zero,
                          child: InkWell(
                            onTap: () => onOpenSession(session),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.hexagon_outlined,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          session.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge,
                                        ),
                                        Text(
                                          '${repository.phases(session.id).length} fases · ${repository.measurementCount(session.id)} mediciones',
                                        ),
                                      ],
                                    ),
                                  ),
                                  Chip(
                                    label: Text(
                                      session.status == 'active'
                                          ? 'Activa'
                                          : session.status == 'paused'
                                          ? 'Pausada'
                                          : 'Finalizada',
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Icon(Icons.arrow_forward_ios, size: 16),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: MediaQuery.sizeOf(context).width < 600 ? 160 : 202,
    child: AcrylicPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(value, style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 3),
          Text(label),
        ],
      ),
    ),
  );
}

class SessionPage extends StatefulWidget {
  const SessionPage({
    super.key,
    required this.session,
    required this.repository,
    required this.onChanged,
  });
  final LabSession session;
  final LabRepository repository;
  final VoidCallback onChanged;
  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  bool exporting = false;
  Future<void> _addPhase() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva fase'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre de fase'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    widget.repository.createPhase(widget.session.id, name);
    widget.onChanged();
    setState(() {});
  }

  Future<void> _export(String format, {bool enriched = false}) async {
    setState(() => exporting = true);
    try {
      final path = await ExportService(widget.repository)
          .save(widget.session.id, format: format, enriched: enriched);
      if (mounted && path != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Exportado a $path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.repository.sessions().firstWhere(
      (s) => s.id == widget.session.id,
    );
    final phases = widget.repository.phases(widget.session.id);
    final tests = widget.repository.testsForSession(widget.session.id);
    final trials = widget.repository.trialsForSession(widget.session.id);
    final measurements = widget.repository.measurements(widget.session.id);
    final summary = DescriptiveEngine.calculate(
      measurements
          .where((m) => m.success && m.latencyMs != null)
          .map((m) => m.latencyMs!),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Sesión experimental')),
      body: Stack(
        children: [
          const Positioned.fill(child: MathBackground()),
          ListView(
            padding: const EdgeInsets.all(22),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 950),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Hero(
                      tag: 'session-${widget.session.id}',
                      child: Material(
                        color: Colors.transparent,
                        child: AcrylicPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                current.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${measurements.length} observaciones · ${phases.length} fases',
                              ),
                              const SizedBox(height: 18),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  FilledButton.icon(
                                    onPressed: current.status == 'active'
                                        ? _addPhase
                                        : null,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Nueva fase'),
                                  ),
                                  PopupMenuButton<String>(
                                    tooltip: 'Estado de la sesión',
                                    initialValue: current.status,
                                    onSelected: (value) {
                                      widget.repository.updateSessionStatus(
                                        current.id,
                                        value,
                                      );
                                      widget.onChanged();
                                      setState(() {});
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'active',
                                        child: Text('Sesión activa'),
                                      ),
                                      PopupMenuItem(
                                        value: 'paused',
                                        child: Text('Pausar sesión'),
                                      ),
                                      PopupMenuItem(
                                        value: 'finished',
                                        child: Text('Finalizar sesión'),
                                      ),
                                    ],
                                    child: Chip(
                                      label: Text(
                                        current.status == 'active'
                                            ? 'Activa'
                                            : current.status == 'paused'
                                            ? 'Pausada'
                                            : 'Finalizada',
                                      ),
                                    ),
                                  ),
                                  for (final format in [
                                    'csv',
                                    'json',
                                    'jsonl',
                                    'xlsx',
                                    'html',
                                    'pdf',
                                    'zip',
                                  ])
                                    OutlinedButton(
                                      onPressed: exporting
                                          ? null
                                          : () => _export(format),
                                      child: exporting
                                          ? const GeometryLoader()
                                          : Text(
                                              'Exportar ${format.toUpperCase()}',
                                            ),
                                    ),
                                  OutlinedButton(
                                    onPressed: exporting
                                        ? null
                                        : () => _export('csv', enriched: true),
                                    child: const Text('CSV enriquecido'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _Metric(
                          label: 'RTT medio · ms',
                          value: summary.mean?.toStringAsFixed(2) ?? '—',
                          icon: Icons.speed,
                        ),
                        _Metric(
                          label: 'P95 · ms',
                          value: summary.p95?.toStringAsFixed(2) ?? '—',
                          icon: Icons.timeline,
                        ),
                        _Metric(
                          label: 'SLA < 50 ms',
                          value:
                              DescriptiveEngine.successRate(measurements)
                                  ?.letPercent() ??
                              '—',
                          icon: Icons.verified_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Fases',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    if (phases.isEmpty)
                      const AcrylicPanel(
                        child: Text(
                          'Agrega una fase y luego ve a Red local para ejecutar una prueba en ella.',
                        ),
                      ),
                    for (final phase in phases)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AcrylicPanel(
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text(
                              phase.name,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            subtitle: Text(
                              '${measurements.where((m) => m.phaseId == phase.id).length} muestras · ${tests.where((t) => t['phase_id'] == phase.id).length} pruebas',
                            ),
                            leading: const Icon(Icons.layers_outlined),
                            trailing: PopupMenuButton<String>(
                              tooltip: 'Estado de la fase',
                              initialValue: phase.status,
                              onSelected: (value) {
                                widget.repository.updatePhaseStatus(
                                  current.id,
                                  phase.id,
                                  value,
                                );
                                widget.onChanged();
                                setState(() {});
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'active',
                                  child: Text('Fase activa'),
                                ),
                                PopupMenuItem(
                                  value: 'paused',
                                  child: Text('Pausar fase'),
                                ),
                                PopupMenuItem(
                                  value: 'finished',
                                  child: Text('Finalizar fase'),
                                ),
                              ],
                              child: Chip(
                                label: Text(
                                  phase.status == 'active'
                                      ? 'Activa'
                                      : phase.status == 'paused'
                                      ? 'Pausada'
                                      : 'Finalizada',
                                ),
                              ),
                            ),
                            children: [
                              if (tests.every((t) => t['phase_id'] != phase.id))
                                const ListTile(
                                  title: Text('Sin pruebas en esta fase'),
                                ),
                              for (final test in tests.where(
                                (t) => t['phase_id'] == phase.id,
                              ))
                                ListTile(
                                  title: Text('${test['name']}'),
                                  subtitle: Text(
                                    '${trials.where((r) => r['test_id'] == test['id']).length} ensayos · ${measurements.where((m) => m.testId == test['id']).length} muestras',
                                  ),
                                  leading: const Icon(Icons.science_outlined),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

extension _Percent on double {
  String letPercent() => '${(this * 100).toStringAsFixed(1)}%';
}

class NetworkScreen extends StatefulWidget {
  const NetworkScreen({
    super.key,
    required this.repository,
    required this.network,
    required this.onChanged,
  });
  final LabRepository repository;
  final NetworkLab network;
  final VoidCallback onChanged;
  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen>
    with AutomaticKeepAliveClientMixin<NetworkScreen> {
  @override
  bool get wantKeepAlive => true;
  Timer? statusTimer;
  final HotspotAdapter hotspotAdapter = const PlatformHotspotAdapter();
  HotspotState? hotspot;
  final address = TextEditingController();
  final code = TextEditingController();
  final count = TextEditingController(text: '100');
  final clients = TextEditingController(text: '1');
  final distance = TextEditingController();
  final payload = TextEditingController(text: '0');
  final interval = TextEditingController(text: '100');
  final timeout = TextEditingController(text: '5000');
  final warmup = TextEditingController(text: '3');
  String? sessionId;
  String? phaseId;
  String scenario = 'E1';
  String direction = 'download';
  String protocol = 'http';
  String environment = 'indoor';
  String loadProfile = 'latency';
  bool customAutoClients = false;
  String preset = 'latency';
  bool serverMode = false;
  bool connected = false;
  String? connectedName;
  String? busyAction;
  bool busy = false;
  bool cancel = false;
  bool coordinating = false;
  int progress = 0;
  String? feedback;
  List<String> localAddresses = [];
  List<DiscoveredServer> discovered = [];

  @override
  void initState() {
    super.initState();
    address.addListener(_clearConnection);
    code.addListener(_clearConnection);
    statusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted &&
          (widget.network.isServing || widget.network.isParticipating)) {
        setState(() {});
      }
    });
    _loadAddresses();
  }

  void _clearConnection() {
    if (connected && mounted) {
      setState(() {
        connected = false;
        connectedName = null;
      });
    }
  }

  Future<void> _loadHotspot() async {
    try {
      final value = await hotspotAdapter.status();
      if (mounted) setState(() => hotspot = value);
    } catch (e) {
      if (mounted) setState(() => feedback = 'Adaptador Wi-Fi: $e');
    }
  }

  Future<void> _toggleHotspot() async {
    setState(() {
      busy = true;
      busyAction = 'hotspot';
    });
    try {
      final value = hotspot?.active == true
          ? await hotspotAdapter.stop()
          : await hotspotAdapter.start();
      if (mounted) setState(() => hotspot = value);
      await _loadAddresses();
    } catch (e) {
      if (mounted) setState(() => feedback = 'Hotspot: $e');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          busyAction = null;
        });
      }
    }
  }

  Future<void> _loadAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      final result = [
        for (final iface in interfaces)
          for (final ip in iface.addresses)
            if (!ip.isLoopback) '${iface.name}: ${ip.address}',
      ];
      if (mounted) setState(() => localAddresses = result);
    } catch (_) {
      /* Address display is optional. */
    }
  }

  @override
  void dispose() {
    cancel = true;
    statusTimer?.cancel();
    address.dispose();
    code.dispose();
    count.dispose();
    clients.dispose();
    distance.dispose();
    payload.dispose();
    interval.dispose();
    timeout.dispose();
    warmup.dispose();
    super.dispose();
  }

  Future<void> _toggleServer() async {
    setState(() {
      busy = true;
      busyAction = 'server';
    });
    try {
      if (widget.network.isServing) {
        await widget.network.stopServer();
      } else {
        await widget.network.startServer();
      }
      if (!mounted) return;
      setState(
        () => feedback = widget.network.isServing
            ? 'Servidor activo. Comparte la IP local, puerto y código con clientes autorizados.'
            : 'Servidor detenido.',
      );
    } catch (e) {
      if (mounted) {
        setState(() => feedback = 'No se pudo cambiar el servidor: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          busyAction = null;
        });
      }
    }
  }

  Future<void> _toggleParticipant() async {
    setState(() {
      busy = true;
      busyAction = 'participant';
      feedback = null;
    });
    try {
      if (widget.network.isParticipating) {
        await widget.network.stopParticipant();
      } else {
        await widget.network.startParticipant(
          Uri.parse(address.text.trim()),
          code.text.trim(),
        );
      }
      if (mounted) {
        setState(
          () => feedback = widget.network.isParticipating
              ? 'Participante listo. Este dispositivo espera instrucciones del servidor y conservará una copia local de cada ensayo.'
              : 'Participación detenida.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => feedback = 'No se pudo participar: $e');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          busyAction = null;
        });
      }
    }
  }

  Future<void> _connect() async {
    final uri = Uri.tryParse(address.text.trim());
    if (uri == null ||
        uri.scheme != 'http' ||
        uri.host.isEmpty ||
        !RegExp(r'^\d{6}$').hasMatch(code.text.trim())) {
      setState(
        () => feedback = 'Escribe una URL http://IP:puerto y el código de seis dígitos del servidor.',
      );
      return;
    }
    setState(() {
      busy = true;
      busyAction = 'connect';
      feedback = null;
    });
    try {
      final info = await widget.network.probe(uri);
      await widget.network.register(uri, code.text.trim());
      if (!mounted) return;
      setState(() {
        connected = true;
        connectedName = '${info['name'] ?? uri.host}';
        feedback = 'Conectado a $connectedName. Ya puedes preparar un ensayo.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          connected = false;
          feedback =
              'No se pudo conectar. Comprueba la misma Wi-Fi, la URL y el código. Detalle: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          busyAction = null;
        });
      }
    }
  }

  Future<void> _createSession() async {
    final name = await _askName('Nueva sesión', 'Nombre del experimento');
    if (name == null) return;
    final session = widget.repository.createSession(name);
    final phase = widget.repository.createPhase(session.id, 'Fase inicial');
    if (!mounted) return;
    setState(() {
      sessionId = session.id;
      phaseId = phase.id;
      feedback = 'Sesión «$name» lista con su fase inicial.';
    });
    widget.onChanged();
  }

  Future<void> _createPhase() async {
    if (sessionId == null) return;
    final name = await _askName('Nueva fase', 'Nombre de la fase');
    if (name == null) return;
    final phase = widget.repository.createPhase(sessionId!, name);
    if (!mounted) return;
    setState(() => phaseId = phase.id);
    widget.onChanged();
  }

  Future<String?> _askName(String title, String label) async {
    var enteredName = '';
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: label),
          onChanged: (value) => enteredName = value,
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, enteredName),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _discover() async {
    setState(() {
      busy = true;
      busyAction = 'discover';
      feedback = null;
    });
    try {
      final found = await widget.network.discover();
      if (!mounted) return;
      setState(() {
        discovered = found;
        if (found.length == 1) address.text = found.first.uri.toString();
        feedback = found.isEmpty
            ? 'No se encontraron servidores LANXIS. Si el servidor está activo, escribe su IP local manualmente; algunas redes bloquean la búsqueda.'
            : '${found.length} servidor(es) LANXIS encontrados. Selecciona uno para usar su dirección.';
      });
    } catch (e) {
      if (mounted) setState(() => feedback = 'Descubrimiento: $e');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          busyAction = null;
        });
      }
    }
  }

  bool get isReferenceScenario => RegExp(r'^E[1-6]$').hasMatch(scenario);

  TrialConfig _currentConfig() {
    final n = int.tryParse(count.text.trim());
    if (n == null || n < 1 || n > 100000) {
      throw const FormatException(
        'Muestras: escribe un número entre 1 y 100 000.',
      );
    }
    final distanceText = distance.text.trim();
    final measured = distanceText.isEmpty
        ? null
        : double.tryParse(distanceText.replaceAll(',', '.'));
    if (distanceText.isNotEmpty && (measured == null || measured < 0)) {
      throw const FormatException(
        'Distancia real: deja vacío o escribe metros válidos.',
      );
    }
    if (isReferenceScenario) {
      final plan = ScenarioPlanner.reference(
        scenarioId: scenario,
        environment: environment,
        load: loadProfile,
        readyClients: widget.network.readyWorkers,
        count: n,
      );
      return measured == null
          ? plan.config
          : plan.config.withDistance(measured, 'manual', null);
    }
    final k = int.tryParse(clients.text.trim());
    final bytes = int.tryParse(payload.text.trim());
    final everyMs = int.tryParse(interval.text.trim());
    final timeoutMs = int.tryParse(timeout.text.trim());
    final warmupCount = int.tryParse(warmup.text.trim());
    if (k == null ||
        k < 1 ||
        k > 32 ||
        bytes == null ||
        bytes < 0 ||
        everyMs == null ||
        everyMs < 0 ||
        timeoutMs == null ||
        timeoutMs < 100 ||
        warmupCount == null ||
        warmupCount < 0) {
      throw const FormatException(
        'Revisa clientes, carga, intervalo, espera y calentamiento.',
      );
    }
    final actualClients = customAutoClients && widget.network.isServing
        ? widget.network.readyWorkers.clamp(1, 32)
        : k;
    return TrialConfig(
      scenarioId: scenario,
      clients: actualClients,
      count: n,
      distanceM: measured,
      distanceSource: measured == null ? 'unknown' : 'manual',
      environment: environment,
      payloadBytes: bytes,
      intervalMs: everyMs,
      timeoutMs: timeoutMs,
      warmup: warmupCount,
      protocol: protocol,
      direction: direction,
    );
  }

  Future<void> _saveTemplate() async {
    TrialConfig config;
    try {
      config = _currentConfig();
    } catch (error) {
      setState(() => feedback = '$error');
      return;
    }
    final name = await _askName('Guardar escenario', 'Nombre del escenario');
    if (name == null) return;
    final saved = widget.repository.saveScenarioTemplate(
      name,
      config,
      autoClients: customAutoClients,
    );
    if (!mounted) return;
    setState(() {
      scenario = saved.id;
      feedback = 'Escenario «$name» guardado. Puedes volver a usarlo después.';
    });
    widget.onChanged();
  }

  Future<void> _run() async {
    TrialConfig config;
    try {
      config = _currentConfig();
    } catch (error) {
      setState(() => feedback = '$error');
      return;
    }
    final coordinated =
        config.clients > 1 || {'E4', 'E5', 'E6'}.contains(config.scenarioId);
    if (coordinated && !widget.network.isServing) {
      setState(
        () => feedback = 'Inicia el servidor en el paso 1 para coordinar varios participantes.',
      );
      return;
    }
    if (!coordinated && !connected) {
      setState(
        () => feedback = 'Conecta primero con el servidor en el paso 1.',
      );
      return;
    }
    if (coordinated && widget.network.readyWorkers < config.clients) {
      setState(
        () => feedback =
            'Faltan participantes listos: '
            '${widget.network.readyWorkers}/${config.clients}.',
      );
      return;
    }
    final selectedSession = widget.repository
        .sessions()
        .where((item) => item.id == sessionId)
        .firstOrNull;
    final selectedPhase = selectedSession == null
        ? null
        : widget.repository
              .phases(selectedSession.id)
              .where((item) => item.id == phaseId)
              .firstOrNull;
    if (selectedSession == null || selectedPhase == null) {
      setState(
        () =>
            feedback = 'Crea o selecciona una sesión y una fase en el paso 2.',
      );
      return;
    }
    setState(() {
      busy = true;
      cancel = false;
      coordinating = coordinated;
      progress = 0;
      feedback = null;
    });
    try {
      if (coordinated) {
        final actual = await widget.network.runCoordinatedTrial(
          session: selectedSession,
          phase: selectedPhase,
          config: config,
        );
        if (!mounted) return;
        setState(
          () => feedback =
              'Ensayo coordinado: $actual/'
              '${config.count * config.clients} mediciones recibidas de '
              '${config.clients} dispositivos.',
        );
      } else {
        final results = await widget.network.runTrial(
          base: Uri.parse(address.text.trim()),
          code: code.text.trim(),
          session: selectedSession,
          phase: selectedPhase,
          config: config,
          cancelled: () => cancel,
          onProgress: (done, _) {
            if (mounted) setState(() => progress = done);
          },
        );
        final successes = results.where((item) => item.success).length;
        if (!mounted) return;
        final distanceStatus =
            results.isNotEmpty && results.first.distanceM != null
            ? 'Distancia ${results.first.distanceM!.toStringAsFixed(1)} m '
                  '(${results.first.distanceSource}).'
            : 'Distancia no disponible; se guardó sin inventar un valor.';
        setState(
          () => feedback =
              'Ensayo ${cancel ? 'cancelado' : 'terminado'}: '
              '$successes/${results.length} respuestas. $distanceStatus',
        );
      }
      widget.onChanged();
    } catch (error) {
      if (mounted) setState(() => feedback = 'Ensayo interrumpido: $error');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          coordinating = false;
        });
      }
    }
  }

  void _setScenario(String value) {
    final saved = widget.repository
        .scenarioTemplates()
        .where((item) => item.id == value)
        .firstOrNull;
    setState(() {
      scenario = value;
      if (isReferenceScenario) {
        count.text = '100';
        distance.clear();
      } else if (saved != null) {
        final config = saved.config;
        count.text = '${config.count}';
        clients.text = '${config.clients}';
        distance.text = config.distanceM?.toString() ?? '';
        payload.text = '${config.payloadBytes}';
        interval.text = '${config.intervalMs}';
        timeout.text = '${config.timeoutMs}';
        warmup.text = '${config.warmup}';
        protocol = config.protocol;
        direction = config.direction;
        environment = config.environment;
        customAutoClients = saved.autoClients;
        preset = 'custom';
      } else {
        customAutoClients = false;
      }
    });
  }

  void _applyPreset(String kind) {
    setState(() {
      preset = kind;
      protocol = kind == 'tcp'
          ? 'tcp'
          : kind == 'udp'
          ? 'udp'
          : 'http';
      direction = kind == 'upload' ? 'upload' : 'download';
      payload.text = kind == 'latency'
          ? '0'
          : kind == 'udp'
          ? '32'
          : '65536';
    });
  }

  String _presetDescription() => switch (preset) {
    'latency' => 'Mide el tiempo de ida y vuelta de una petición HTTP pequeña.',
    'download' => 'Mide la respuesta al descargar datos del servidor.',
    'upload' => 'Mide el envío de datos hacia el servidor.',
    'tcp' => 'Mide conexión y transferencia TCP directa.',
    'udp' => 'Mide eco UDP con una carga pequeña.',
    _ => 'Configuración personalizada de protocolo y transferencia.',
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final sessions = widget.repository.sessions();
    if (!sessions.any((s) => s.id == sessionId)) {
      sessionId = sessions.firstOrNull?.id;
    }
    final phases = sessionId == null
        ? <LabPhase>[]
        : widget.repository.phases(sessionId!);
    if (!phases.any((p) => p.id == phaseId)) {
      phaseId = phases.firstOrNull?.id;
    }
    Widget heading(String number, String title, String description) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$number  $title', style: theme.textTheme.titleLarge),
        const SizedBox(height: 5),
        Text(description, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 18),
      ],
    );
    Widget message() => feedback == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              feedback!,
              style: TextStyle(
                color:
                    feedback!.startsWith('No se') ||
                        feedback!.startsWith('Ensayo interrumpido') ||
                        feedback!.startsWith('Conecta primero')
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Red y ensayos', style: theme.textTheme.headlineLarge),
              const SizedBox(height: 7),
              const Text(
                'Tres pasos para medir dispositivos en la misma red local.',
              ),
              const SizedBox(height: 19),
              Wrap(
                spacing: 10,
                children: [
                  ChoiceChip(
                    label: const Text('Medir desde este dispositivo'),
                    avatar: const Icon(Icons.speed_rounded, size: 18),
                    selected: !serverMode,
                    onSelected: (_) => setState(() => serverMode = false),
                  ),
                  ChoiceChip(
                    label: const Text('Ofrecer servidor'),
                    avatar: const Icon(Icons.dns_outlined, size: 18),
                    selected: serverMode,
                    onSelected: (_) {
                      setState(() => serverMode = true);
                      if (hotspot == null) _loadHotspot();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 17),
              AcrylicPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading(
                      '01',
                      serverMode ? 'Publicar servidor' : 'Conectar servidor',
                      serverMode
                          ? 'Comparte la dirección y el código con los demás dispositivos.'
                          : 'Busca un servidor LANXIS o escribe la dirección que muestra el otro dispositivo.',
                    ),
                    if (serverMode) ...[
                      if (widget.network.isServing) ...[
                        Text(
                          'Servidor activo · puerto ${widget.network.port}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 7),
                        SelectableText(
                          'Código: ${widget.network.pairCode}',
                          style: theme.textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 7),
                        for (final ip in localAddresses)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(
                              'http://${ip.split(': ').last}:${widget.network.port}',
                            ),
                            subtitle: Text(ip.split(': ').first),
                            trailing: IconButton(
                              tooltip: 'Copiar dirección',
                              icon: const Icon(Icons.copy_rounded),
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text:
                                        'http://${ip.split(': ').last}:${widget.network.port}',
                                  ),
                                );
                                if (mounted) {
                                  setState(
                                    () => feedback = 'Dirección copiada.',
                                  );
                                }
                              },
                            ),
                          ),
                        TextButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: widget.network.pairCode!),
                            );
                            if (mounted) {
                              setState(() => feedback = 'Código copiado.');
                            }
                          },
                          icon: const Icon(Icons.copy_rounded, size: 17),
                          label: const Text('Copiar código'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${widget.network.connectedClients} conectados · '
                          '${widget.network.readyWorkers} listos para ensayos coordinados',
                        ),
                        const SizedBox(height: 12),
                      ] else ...[
                        const Text(
                          'Al iniciarlo, aparecerá un código de seis dígitos y la IP que deben usar los demás.',
                        ),
                        const SizedBox(height: 12),
                      ],
                      FilledButton.icon(
                        onPressed: busy ? null : _toggleServer,
                        icon: busy && busyAction == 'server'
                            ? const GeometryLoader()
                            : Icon(
                                widget.network.isServing
                                    ? Icons.stop_circle_outlined
                                    : Icons.play_arrow_rounded,
                              ),
                        label: Text(
                          widget.network.isServing
                              ? 'Detener servidor'
                              : 'Iniciar servidor',
                        ),
                      ),
                      const SizedBox(height: 12),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Opciones de red Wi-Fi'),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hotspot == null
                                      ? 'Consultando capacidad Wi-Fi…'
                                      : hotspot!.active
                                      ? 'Hotspot local activo'
                                      : hotspot!.supported
                                      ? 'Puedes crear un hotspot local.'
                                      : hotspot!.reason ?? 'Configura una LAN desde el sistema.',
                                ),
                                if (hotspot?.active == true) ...[
                                  SelectableText(
                                    'SSID: ${hotspot!.ssid ?? 'No disponible'}',
                                  ),
                                  SelectableText(
                                    'Clave: ${hotspot!.passphrase ?? 'No disponible'}',
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    if (hotspot?.supported == true)
                                      OutlinedButton.icon(
                                        onPressed: busy ? null : _toggleHotspot,
                                        icon: const Icon(Icons.wifi_tethering),
                                        label: Text(
                                          hotspot!.active
                                              ? 'Detener hotspot'
                                              : 'Crear hotspot',
                                        ),
                                      ),
                                    if (Platform.isAndroid)
                                      TextButton.icon(
                                        onPressed: () => hotspotAdapter
                                            .openSystemWifiSettings(),
                                        icon: const Icon(
                                          Icons.settings_outlined,
                                        ),
                                        label: const Text('Ajustes Wi-Fi'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      OutlinedButton.icon(
                        onPressed: busy ? null : _discover,
                        icon: busy && busyAction == 'discover'
                            ? const GeometryLoader()
                            : const Icon(Icons.radar_rounded),
                        label: Text(
                          busy && busyAction == 'discover'
                              ? 'Buscando en la red local…'
                              : 'Buscar servidores LANXIS',
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'La búsqueda encuentra servidores activos; las sesiones se eligen en el paso 2.',
                      ),
                      for (final server in discovered)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.dns_outlined),
                          title: Text(server.uri.toString()),
                          trailing: const Text('Usar'),
                          onTap: () => setState(
                            () => address.text = server.uri.toString(),
                          ),
                        ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: address,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Dirección del servidor',
                          hintText: 'http://192.168.1.65:8040',
                          helperText:
                              'IP local y puerto que aparecen en el servidor',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: code,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: 'Código de seis dígitos',
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 13),
                      FilledButton.icon(
                        onPressed: busy ? null : _connect,
                        icon: busy && busyAction == 'connect'
                            ? const GeometryLoader()
                            : const Icon(Icons.link_rounded),
                        label: Text(
                          connected
                              ? 'Volver a comprobar conexión'
                              : 'Conectar y comprobar',
                        ),
                      ),
                      if (connected) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Conectado a $connectedName',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text(
                          'Participar en ensayo de otro dispositivo',
                        ),
                        subtitle: Text(
                          widget.network.isParticipating
                              ? 'Participante listo · esperando instrucciones'
                              : 'Úsalo si este teléfono será un cliente auxiliar en E4–E6.',
                        ),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FilledButton.tonalIcon(
                                  onPressed:
                                      busy ||
                                          (!connected &&
                                              !widget.network.isParticipating)
                                      ? null
                                      : _toggleParticipant,
                                  icon: busy && busyAction == 'participant'
                                      ? const GeometryLoader()
                                      : Icon(
                                          widget.network.isParticipating
                                              ? Icons.stop_circle_outlined
                                              : Icons.groups_outlined,
                                        ),
                                  label: Text(
                                    widget.network.isParticipating
                                        ? 'Dejar de participar'
                                        : 'Participar ahora',
                                  ),
                                ),
                                if (widget.network.lastParticipantError != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      'Conexión de participante: '
                                      '${widget.network.lastParticipantError}',
                                      style: TextStyle(
                                        color: theme.colorScheme.error,
                                      ),
                                    ),
                                  ),
                                if (widget.repository.pendingResultCount > 0)
                                  Text(
                                    '${widget.repository.pendingResultCount} resultados pendientes de sincronización.',
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    message(),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              AcrylicPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading(
                      '02',
                      'Guardar en una sesión',
                      'La sesión agrupa el experimento; la fase agrupa las mediciones de una etapa.',
                    ),
                    Wrap(
                      spacing: 9,
                      runSpacing: 9,
                      children: [
                        OutlinedButton.icon(
                          onPressed: busy ? null : _createSession,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Nueva sesión'),
                        ),
                        if (sessionId != null)
                          TextButton.icon(
                            onPressed: busy ? null : _createPhase,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Añadir fase'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: 260,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('session-$sessionId'),
                            initialValue: sessionId,
                            decoration: const InputDecoration(
                              labelText: 'Sesión',
                            ),
                            items: [
                              for (final s in sessions)
                                DropdownMenuItem(
                                  value: s.id,
                                  child: Text(s.name),
                                ),
                            ],
                            onChanged: busy
                                ? null
                                : (value) => setState(() {
                                    sessionId = value;
                                    phaseId = null;
                                  }),
                          ),
                        ),
                        SizedBox(
                          width: 230,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('phase-$sessionId-$phaseId'),
                            initialValue: phaseId,
                            decoration: const InputDecoration(
                              labelText: 'Fase',
                            ),
                            items: [
                              for (final p in phases)
                                DropdownMenuItem(
                                  value: p.id,
                                  child: Text(p.name),
                                ),
                            ],
                            onChanged: busy
                                ? null
                                : (value) => setState(() => phaseId = value),
                          ),
                        ),
                      ],
                    ),
                    if (sessions.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                          'Crea una sesión para guardar el primer ensayo.',
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              AcrylicPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading(
                      '03',
                      'Configurar y medir',
                      'Elige un escenario, revisa el plan y comienza la medición.',
                    ),
                    SizedBox(
                      width: 290,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('scenario-$scenario'),
                        isExpanded: true,
                        initialValue: scenario,
                        decoration: const InputDecoration(
                          labelText: 'Escenario de prueba',
                        ),
                        items: [
                          for (final id in [
                            ...List.generate(6, (index) => 'E${index + 1}'),
                            'Libre',
                          ])
                            DropdownMenuItem(
                              value: id,
                              child: Text(
                                id == 'Libre' ? 'Libre · configurar' : id,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          for (final item
                              in widget.repository.scenarioTemplates())
                            DropdownMenuItem(
                              value: item.id,
                              child: Text(
                                item.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (value) {
                                if (value != null) _setScenario(value);
                              },
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Tipo de ambiente'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Cerrado'),
                          selected: environment == 'indoor',
                          onSelected: busy
                              ? null
                              : (_) => setState(() => environment = 'indoor'),
                        ),
                        ChoiceChip(
                          label: const Text('Abierto'),
                          selected: environment == 'outdoor',
                          onSelected: busy
                              ? null
                              : (_) => setState(() => environment = 'outdoor'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (isReferenceScenario) ...[
                      const Text('Perfil de carga'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (label, value) in [
                            ('Latencia', 'latency'),
                            ('Equilibrada', 'balanced'),
                            ('Transferencia', 'throughput'),
                          ])
                            ChoiceChip(
                              label: Text(label),
                              selected: loadProfile == value,
                              onSelected: busy
                                  ? null
                                  : (_) => setState(() => loadProfile = value),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _NumberField(
                        controller: count,
                        label: 'Muestras por cliente',
                        width: 220,
                      ),
                      const SizedBox(height: 16),
                      ValueListenableBuilder(
                        valueListenable: count,
                        builder: (context, value, child) {
                          final plan = ScenarioPlanner.reference(
                            scenarioId: scenario,
                            environment: environment,
                            load: loadProfile,
                            readyClients: widget.network.readyWorkers,
                            count: int.tryParse(count.text) ?? 100,
                          );
                          final config = plan.config;
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(
                                alpha: .07,
                              ),
                              borderRadius: BorderRadius.circular(17),
                              border: Border.all(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: .26,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Vista previa · $scenario',
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: 6),
                                Text(plan.description),
                                const SizedBox(height: 10),
                                Text(
                                  '${config.clients} cliente(s) × '
                                  '${config.count} muestras = ${plan.totalSamples} observaciones',
                                ),
                                Text(
                                  'HTTP · ${config.payloadBytes} bytes por petición · '
                                  '${config.intervalMs} ms entre peticiones por cliente',
                                ),
                                Text(
                                  'Espera ${config.timeoutMs} ms · '
                                  '${config.warmup} muestras de calentamiento',
                                ),
                                if (config.clients > 1) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Participantes listos: '
                                    '${widget.network.readyWorkers}/${config.clients}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: plan.enoughParticipants
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.error,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                const Text(
                                  'La distancia objetivo define la condición E1–E6. '
                                  'LANXIS intenta medir la distancia real por Wi-Fi RTT '
                                  'cuando el servidor es un punto de acceso compatible.',
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ] else ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (label, kind) in [
                            ('Latencia', 'latency'),
                            ('Descarga', 'download'),
                            ('Subida', 'upload'),
                            ('TCP', 'tcp'),
                            ('UDP eco', 'udp'),
                          ])
                            ChoiceChip(
                              label: Text(label),
                              selected: preset == kind,
                              onSelected: busy
                                  ? null
                                  : (_) => _applyPreset(kind),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(_presetDescription()),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _NumberField(
                            controller: count,
                            label: 'Muestras por cliente',
                            width: 215,
                          ),
                          _NumberField(
                            controller: payload,
                            label: 'Carga · bytes',
                            width: 170,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Adaptar a participantes listos'),
                        subtitle: const Text(
                          'Al iniciar en el servidor, usa los clientes activos.',
                        ),
                        value: customAutoClients,
                        onChanged: busy
                            ? null
                            : (value) =>
                                  setState(() => customAutoClients = value),
                      ),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Parámetros personalizados'),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                SizedBox(
                                  width: 150,
                                  child: DropdownButtonFormField<String>(
                                    key: ValueKey('protocol-$protocol'),
                                    initialValue: protocol,
                                    decoration: const InputDecoration(
                                      labelText: 'Protocolo',
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'http',
                                        child: Text('HTTP'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'tcp',
                                        child: Text('TCP'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'udp',
                                        child: Text('UDP eco'),
                                      ),
                                    ],
                                    onChanged: busy
                                        ? null
                                        : (value) {
                                            if (value != null) {
                                              setState(() {
                                                protocol = value;
                                                if (value == 'udp') {
                                                  direction = 'download';
                                                }
                                                preset = 'custom';
                                              });
                                            }
                                          },
                                  ),
                                ),
                                SizedBox(
                                  width: 155,
                                  child: DropdownButtonFormField<String>(
                                    key: ValueKey(
                                      'direction-$protocol-$direction',
                                    ),
                                    initialValue: direction,
                                    decoration: const InputDecoration(
                                      labelText: 'Transferencia',
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'download',
                                        child: Text('Descarga'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'upload',
                                        child: Text('Subida'),
                                      ),
                                    ],
                                    onChanged: busy || protocol == 'udp'
                                        ? null
                                        : (value) {
                                            if (value != null) {
                                              setState(() {
                                                direction = value;
                                                preset = 'custom';
                                              });
                                            }
                                          },
                                  ),
                                ),
                                if (!customAutoClients)
                                  _NumberField(
                                    controller: clients,
                                    label: 'Clientes',
                                    width: 125,
                                  ),
                                _NumberField(
                                  controller: interval,
                                  label: 'Intervalo · ms',
                                  width: 155,
                                ),
                                _NumberField(
                                  controller: timeout,
                                  label: 'Espera máxima · ms',
                                  width: 190,
                                ),
                                _NumberField(
                                  controller: warmup,
                                  label: 'Calentamiento',
                                  width: 155,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: busy ? null : _saveTemplate,
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: Text(
                          scenario == 'Libre'
                              ? 'Guardar escenario'
                              : 'Guardar copia personalizada',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Distancia real'),
                      subtitle: const Text(
                        'Automática si es medible; no se exige para iniciar.',
                      ),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Wi-Fi RTT mide al punto de acceso compatible. '
                                'Si el servidor es otro equipo en la red, la distancia '
                                'queda sin dato para evitar una cifra falsa.',
                              ),
                              const SizedBox(height: 10),
                              _NumberField(
                                controller: distance,
                                label: 'Introducir distancia medida · m (opcional)',
                                width: 300,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (busy && progress > 0) ...[
                      LinearProgressIndicator(
                        value: (progress / (int.tryParse(count.text) ?? 1))
                            .clamp(0, 1),
                      ),
                      const SizedBox(height: 9),
                    ],
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: busy ? null : _run,
                          icon: busy
                              ? const GeometryLoader()
                              : const Icon(Icons.play_arrow_rounded),
                          label: Text(
                            busy
                                ? progress > 0
                                      ? 'Midiendo $progress…'
                                      : 'Preparando ensayo…'
                                : 'Iniciar ensayo',
                          ),
                        ),
                        if (busy && !coordinating)
                          TextButton(
                            onPressed: () => setState(() => cancel = true),
                            child: const Text('Cancelar'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Cada ejecución crea una prueba con sus muestras. '
                      'Los resultados aparecen en Análisis.',
                    ),
                    message(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.width,
  });
  final TextEditingController controller;
  final String label;
  final double width;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
    ),
  );
}

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({
    super.key,
    required this.repository,
    required this.revision,
  });
  final LabRepository repository;
  final int revision;
  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  String? selected;
  String selectedPhase = 'all';
  String selectedTest = 'all';
  String selectedTrial = 'all';
  bool exporting = false;

  Future<void> _exportSelection(String format) async {
    if (selected == null) return;
    setState(() => exporting = true);
    try {
      final path = await ExportService(widget.repository).save(
        selected!,
        format: format,
        scope: ExportScope(
          phaseId: selectedPhase == 'all' ? null : selectedPhase,
          testId: selectedTest == 'all' ? null : selectedTest,
          trialId: selectedTrial == 'all' ? null : selectedTrial,
        ),
      );
      if (mounted && path != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Selección exportada a $path')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo exportar: $error')));
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = widget.repository.sessions();
    if (!sessions.any((s) => s.id == selected)) {
      selected = sessions.firstOrNull?.id;
    }
    final phases = selected == null
        ? <LabPhase>[]
        : widget.repository.phases(selected!);
    if (selectedPhase != 'all' && !phases.any((p) => p.id == selectedPhase)) {
      selectedPhase = 'all';
    }
    final tests = selected == null
        ? <Map<String, Object?>>[]
        : widget.repository
              .testsForSession(selected!)
              .where(
                (t) => selectedPhase == 'all' || t['phase_id'] == selectedPhase,
              )
              .toList();
    if (selectedTest != 'all' && !tests.any((t) => t['id'] == selectedTest)) {
      selectedTest = 'all';
    }
    final testIds = tests.map((t) => t['id']).toSet();
    final trials = selected == null
        ? <Map<String, Object?>>[]
        : widget.repository
              .trialsForSession(selected!)
              .where(
                (t) =>
                    testIds.contains(t['test_id']) &&
                    (selectedTest == 'all' || t['test_id'] == selectedTest),
              )
              .toList();
    if (selectedTrial != 'all' &&
        !trials.any((t) => t['id'] == selectedTrial)) {
      selectedTrial = 'all';
    }
    final allItems = selected == null
        ? <Measurement>[]
        : widget.repository.measurements(selected!);
    final items = allItems
        .where(
          (m) =>
              (selectedPhase == 'all' || m.phaseId == selectedPhase) &&
              (selectedTest == 'all' || m.testId == selectedTest) &&
              (selectedTrial == 'all' || m.trialId == selectedTrial),
        )
        .toList();
    final valid = items
        .where((m) => m.success && m.latencyMs != null)
        .map((m) => m.latencyMs!)
        .toList();
    final stats = DescriptiveEngine.calculate(valid);
    final bins = DescriptiveEngine.frequency(valid);
    final grouped = DescriptiveEngine.byScenario(items);
    final posterior = DescriptiveEngine.criticalDistancePosterior(items);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 42),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cada muestra cuenta.',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Estadística descriptiva de observaciones reales. Fallos conservados, sin imputar latencias.',
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 300,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('analysis-session-$selected'),
                      initialValue: selected,
                      decoration: const InputDecoration(labelText: 'Sesión'),
                      items: [
                        for (final s in sessions)
                          DropdownMenuItem(value: s.id, child: Text(s.name)),
                      ],
                      onChanged: (v) => setState(() {
                        selected = v;
                        selectedPhase = 'all';
                        selectedTest = 'all';
                        selectedTrial = 'all';
                      }),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('analysis-phase-$selected-$selectedPhase'),
                      initialValue: selectedPhase,
                      decoration: const InputDecoration(labelText: 'Fase'),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('Todas'),
                        ),
                        for (final phase in phases)
                          DropdownMenuItem(
                            value: phase.id,
                            child: Text(phase.name),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        selectedPhase = v ?? 'all';
                        selectedTest = 'all';
                        selectedTrial = 'all';
                      }),
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(
                        'analysis-test-$selectedPhase-$selectedTest',
                      ),
                      initialValue: selectedTest,
                      decoration: const InputDecoration(labelText: 'Prueba'),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('Todas'),
                        ),
                        for (final test in tests)
                          DropdownMenuItem(
                            value: test['id'] as String,
                            child: Text(test['name'] as String),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        selectedTest = v ?? 'all';
                        selectedTrial = 'all';
                      }),
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(
                        'analysis-trial-$selectedTest-$selectedTrial',
                      ),
                      initialValue: selectedTrial,
                      decoration: const InputDecoration(labelText: 'Ensayo'),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('Todos'),
                        ),
                        for (var i = 0; i < trials.length; i++)
                          DropdownMenuItem(
                            value: trials[i]['id'] as String,
                            child: Text(
                              'Ensayo ${i + 1} · ${trials[i]['status']}',
                            ),
                          ),
                      ],
                      onChanged: (v) =>
                          setState(() => selectedTrial = v ?? 'all'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (selected != null && items.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final format in ['csv', 'json', 'xlsx', 'pdf', 'zip'])
                      OutlinedButton(
                        onPressed: exporting
                            ? null
                            : () => _exportSelection(format),
                        child: exporting
                            ? const GeometryLoader()
                            : Text('Exportar ${format.toUpperCase()}'),
                      ),
                  ],
                ),
              const SizedBox(height: 18),
              if (items.isEmpty)
                const AcrylicPanel(
                  child: Text(
                    'No hay mediciones para esta selección. Ajusta los filtros o inicia un ensayo desde Red local.',
                  ),
                )
              else ...[
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _Metric(
                      label: 'RTT medio · ms',
                      value: stats.mean?.toStringAsFixed(2) ?? '—',
                      icon: Icons.speed,
                    ),
                    _Metric(
                      label: 'Mediana · ms',
                      value: stats.median?.toStringAsFixed(2) ?? '—',
                      icon: Icons.horizontal_rule,
                    ),
                    _Metric(
                      label: 'P95 · ms',
                      value: stats.p95?.toStringAsFixed(2) ?? '—',
                      icon: Icons.insights_rounded,
                    ),
                    _Metric(
                      label: 'SLA < 50 ms',
                      value:
                          DescriptiveEngine.successRate(items)?.letPercent() ??
                          '—',
                      icon: Icons.check_circle_outline,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                AcrylicPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Distribución de latencia',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${valid.length} respuestas válidas · ${items.length - valid.length} fallos · 7 clases',
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        height: 260,
                        child: BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            maxY:
                                bins
                                    .map((b) => b.frequency.toDouble())
                                    .fold<double>(0, math.max) +
                                1,
                            gridData: const FlGridData(show: false),
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
                                  getTitlesWidget: (value, meta) => Text(
                                    '${value.toInt() + 1}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ),
                            ),
                            barGroups: [
                              for (var i = 0; i < bins.length; i++)
                                BarChartGroupData(
                                  x: i,
                                  barRods: [
                                    BarChartRodData(
                                      toY: bins[i].frequency.toDouble(),
                                      width: 22,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(6),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Clases numeradas de menor a mayor latencia. Tabla con límites exactos debajo.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ScienceCharts(items: items),
                const SizedBox(height: 16),
                AcrylicPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tabla de frecuencias',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Intervalo ms')),
                            DataColumn(label: Text('fi')),
                            DataColumn(label: Text('fr')),
                            DataColumn(label: Text('Fi')),
                          ],
                          rows: [
                            for (var i = 0; i < bins.length; i++)
                              DataRow(
                                cells: [
                                  DataCell(
                                    Text(
                                      '[${bins[i].lower.toStringAsFixed(1)}, ${bins[i].upper.toStringAsFixed(1)}${i == bins.length - 1 ? ']' : ')'}',
                                    ),
                                  ),
                                  DataCell(Text('${bins[i].frequency}')),
                                  DataCell(
                                    Text(bins[i].relative.toStringAsFixed(3)),
                                  ),
                                  DataCell(Text('${bins[i].cumulative}')),
                                ],
                              ),
                          ],
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
                        'Escenarios',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      if (grouped.isEmpty)
                        const Text('No hay respuestas válidas.'),
                      for (final entry in grouped.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              SizedBox(width: 46, child: Text(entry.key)),
                              Expanded(
                                child: LinearProgressIndicator(
                                  value:
                                      stats.maximum == null ||
                                          stats.maximum == 0
                                      ? 0
                                      : (entry.value.mean ?? 0) /
                                            stats.maximum!,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${entry.value.n} · ${entry.value.mean?.toStringAsFixed(1)} ms',
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 14),
                      Text(
                        'P(distancia | petición crítica)',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      if (posterior.isEmpty)
                        const Text(
                          'Aún no hay peticiones fallidas o > 100 ms.',
                        ),
                      for (final entry in posterior.entries)
                        Text(
                          '${entry.key.toStringAsFixed(0)} m: ${entry.value.letPercent()}',
                        ),
                      const SizedBox(height: 8),
                      const Text(
                        'Probabilidad empírica descriptiva. No implica causalidad.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _InferencePanel(items: items, valid: valid),
              ],
              const SizedBox(height: 16),
              const DistributionExplorer(),
            ],
          ),
        ),
      ],
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({
    super.key,
    required this.mode,
    required this.onModeChanged,
  });
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onModeChanged;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 42),
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 790),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const GaussianMark(size: 74),
            const SizedBox(height: 18),
            Text('LANXIS', style: Theme.of(context).textTheme.displayLarge),
            const SizedBox(height: 6),
            const Text('Local Area Network eXperimentation & Inference Suite'),
            const SizedBox(height: 24),
            const AcrylicPanel(
              child: Text(
                'Laboratorio científico de redes locales. Las mediciones se guardan en este dispositivo y los experimentos se ejecutan en redes autorizadas. La ausencia de señal RSSI u otra métrica se muestra como dato no disponible; nunca se inventa.',
              ),
            ),
            const SizedBox(height: 16),
            AcrylicPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Apariencia',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('Sistema'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Claro'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Oscuro'),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (values) => onModeChanged(values.first),
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
                    'Código y licencia',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Código fuente público bajo CC BY-NC 4.0. Se requiere atribución; el uso comercial del material licenciado no está permitido por esta licencia.',
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse('https://github.com/sergio-rubin/lanxis'),
                    ),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Ver repositorio en GitHub'),
                  ),
                  TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(
                        'https://creativecommons.org/licenses/by-nc/4.0/',
                      ),
                    ),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Leer la licencia'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'v0.1.0 · Protocolo 1',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ],
  );
}

class _InferencePanel extends StatelessWidget {
  const _InferencePanel({required this.items, required this.valid});
  final List<Measurement> items;
  final List<double> valid;

  @override
  Widget build(BuildContext context) {
    final success = items.where((m) => m.meetsSla).length;
    final wilson = InferenceEngine.proportionWilson(success, items.length);
    final interval = valid.length >= 2
        ? InferenceEngine.meanInterval(valid)
        : null;
    final probability = ProbabilityEngine.criticalByDistance(items);
    final e3 = items.where((m) => m.scenarioId == 'E3').toList();
    final pE3 = ProbabilityEngine.severeLagRate(e3);
    final lagP = EventModels.lagProbability(items);
    final udp = items.where((m) => m.protocol == 'udp').toList();
    final udpTimeouts = udp
        .where((m) => m.error?.toLowerCase().contains('timeout') ?? false)
        .length;
    final poissonRate = EventModels.spikeRatePerMinute(items);
    final exponentialRate = EventModels.exponentialRate(items);
    final e1 = items
        .where((m) => m.scenarioId == 'E1' && m.latencyMs != null)
        .map((m) => m.latencyMs!)
        .toList();
    final e4 = items
        .where((m) => m.scenarioId == 'E4' && m.latencyMs != null)
        .map((m) => m.latencyMs!)
        .toList();
    final e6Items = items.where((m) => m.scenarioId == 'E6').toList();
    final normalFit = EventModels.normalFit(e1);
    final tests = <HypothesisResult>[];
    HypothesisResult? comparison;
    if (e1.length >= 2 && e4.length >= 2) {
      try {
        comparison = InferenceEngine.welchGreater(e4, e1);
      } on ArgumentError {
        /* Constant groups cannot support this test. */
      }
    }
    if (comparison != null) tests.add(comparison);
    if (valid.length >= 2) {
      try {
        tests.add(InferenceEngine.meanGreater(valid, 50));
      } on ArgumentError {
        // Constant samples do not support the t statistic.
      }
    }
    final e1Variance = DescriptiveEngine.calculate(e1).variance;
    if (e4.length >= 2 && e1Variance != null && e1Variance > 0) {
      try {
        tests.add(InferenceEngine.varianceGreater(e4, e1Variance));
      } on ArgumentError {
        // The reference variance requires valid variation.
      }
    }
    if (e6Items.isNotEmpty) {
      tests.add(
        InferenceEngine.slowProportionGreater(
          e6Items.where((m) => m.severeLag).length,
          e6Items.length,
        ),
      );
    }
    return AcrylicPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Inferencia y probabilidad',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 7),
          const Text(
            'Resultados calculados desde esta sesión; revisa supuestos antes de interpretar.',
          ),
          const SizedBox(height: 16),
          Text(
            'IC Wilson 95% de cumplimiento SLA: ${(wilson.lower * 100).toStringAsFixed(1)}–${(wilson.upper * 100).toStringAsFixed(1)}%',
          ),
          if (interval != null)
            Text(
              'IC t 95% de RTT medio: ${interval.lower.toStringAsFixed(2)}–${interval.upper.toStringAsFixed(2)} ms',
            ),
          if (interval?.warning != null)
            Text(
              interval!.warning!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 9),
          Text(
            'P(lag > 50 ms | multicliente): ${DescriptiveEngine.conditionalLagMulticlient(items)?.letPercent() ?? 'sin datos'}',
          ),
          Text('P(lag > 50 ms): ${lagP?.letPercent() ?? 'sin datos'}'),
          if (udp.isNotEmpty)
            Text(
              'Sin eco UDP: $udpTimeouts/${udp.length} datagramas (${(udpTimeouts / udp.length).letPercent()}). Incluye posibles bloqueos de firewall o del dispositivo.',
            ),
          Text(
            'P(multicliente): ${(items.where((m) => m.clients > 1).length / items.length).letPercent()}',
          ),
          Text(
            'P(lag ∩ multicliente): ${ProbabilityEngine.lagAndMulti(items)?.letPercent() ?? 'sin datos'}',
          ),
          Text(
            'P(multicliente | lag > 50 ms): ${ProbabilityEngine.conditionalMultiGivenLag(items)?.letPercent() ?? 'sin datos'}',
          ),
          Text('P(petición crítica): ${probability.total.letPercent()}'),
          const SizedBox(height: 8),
          const Text(
            'Árbol de distancia y petición crítica (ponderación empírica):',
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Distancia')),
                DataColumn(label: Text('P(Bᵢ)')),
                DataColumn(label: Text('P(A|Bᵢ)')),
                DataColumn(label: Text('P(A∩Bᵢ)')),
                DataColumn(label: Text('P(Bᵢ|A)')),
              ],
              rows: [
                for (final distance in probability.prior.keys)
                  DataRow(
                    cells: [
                      DataCell(Text('${distance.toStringAsFixed(0)} m')),
                      DataCell(
                        Text(probability.prior[distance]!.toStringAsFixed(3)),
                      ),
                      DataCell(
                        Text(
                          probability.conditional[distance]!.toStringAsFixed(3),
                        ),
                      ),
                      DataCell(
                        Text(
                          (probability.prior[distance]! *
                                  probability.conditional[distance]!)
                              .toStringAsFixed(3),
                        ),
                      ),
                      DataCell(
                        Text(
                          probability.posterior[distance]?.toStringAsFixed(3) ??
                              '—',
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (probability.posterior.containsKey(12.0))
            Text(
              'P(12 m | petición crítica): ${probability.posterior[12.0]!.letPercent()}',
            ),
          if (pE3 != null)
            Text(
              'Binomial E3: P(5 lentas en 20, p=${pE3.toStringAsFixed(3)}): ${ProbabilityEngine.binomialPmf(20, 5, pE3).toStringAsFixed(4)}',
            ),
          if (lagP != null) ...[
            Text('Bernoulli lag severo: p = ${lagP.toStringAsFixed(3)}'),
            Text(
              'Geométrica hasta el primer pico: E[intentos] = ${ProbabilityEngine.geometricAttemptsMean(lagP).toStringAsFixed(2)}; E[anteriores] = ${ProbabilityEngine.geometricFailuresMean(lagP).toStringAsFixed(2)}',
            ),
          ],
          if (poissonRate != null)
            Text(
              'Spikes por minuto: λ = ${poissonRate.toStringAsFixed(3)}; Poisson P(5/min) = ${ProbabilityEngine.poissonPmf(5, poissonRate).toStringAsPrecision(3)} (si tasa e independencia son plausibles).',
            ),
          if (exponentialRate != null)
            Text(
              'Entre picos: λ = ${exponentialRate.toStringAsFixed(4)} s⁻¹; P(T ≤ 30 s) = ${ProbabilityEngine.exponentialCdf(30, exponentialRate).letPercent()} (modelo exploratorio).',
            ),
          if (normalFit != null) ...[
            const SizedBox(height: 8),
            Text(
              'Ajuste normal E1: μ = ${normalFit.mean.toStringAsFixed(2)} ms, s = ${normalFit.standardDeviation.toStringAsFixed(2)} ms; Jarque–Bera p = ${normalFit.pValue.toStringAsPrecision(3)}.',
            ),
            Text(normalFit.interpretation),
          ],
          const SizedBox(height: 12),
          Text(
            'Pruebas de hipótesis',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (tests.isEmpty)
            const Text(
              'Se requieren grupos con tamaño y variación suficientes.',
            ),
          for (final result in tests) _HypothesisDetails(result: result),
          const SizedBox(height: 10),
          const Text(
            'Exploratorio. La repetición por dispositivo o ensayo puede reducir el tamaño efectivo de muestra; esta pantalla no establece causalidad.',
          ),
        ],
      ),
    );
  }
}
