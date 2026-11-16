import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
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
  static const titles = ['Inicio', 'Red local', 'Análisis', 'Acerca de'];
  static const icons = [
    Icons.space_dashboard_rounded,
    Icons.hub_rounded,
    Icons.analytics_rounded,
    Icons.info_outline_rounded,
  ];

  void refresh() => setState(() => revision++);

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
    final reduced = MediaQuery.disableAnimationsOf(context);
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
                                  onTap: () => setState(() => index = i),
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
                        child: AnimatedSwitcher(
                          duration: reduced
                              ? Duration.zero
                              : const Duration(milliseconds: 330),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween(
                                    begin: const Offset(.025, .02),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: KeyedSubtree(
                            key: ValueKey(index),
                            child: screens[index],
                          ),
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
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => setState(() => index = i),
              destinations: [
                for (var i = 0; i < titles.length; i++)
                  NavigationDestination(icon: Icon(icons[i]), label: titles[i]),
              ],
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
              Row(
                children: [
                  Text(
                    'Investigaciones',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const Spacer(),
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

class _NetworkScreenState extends State<NetworkScreen> {
  Timer? statusTimer;
  final HotspotAdapter hotspotAdapter = const PlatformHotspotAdapter();
  HotspotState? hotspot;
  final address = TextEditingController(text: 'http://192.168.1.1:8040');
  final code = TextEditingController();
  final count = TextEditingController(text: '100');
  final clients = TextEditingController(text: '1');
  final distance = TextEditingController(text: '1');
  final payload = TextEditingController(text: '0');
  final interval = TextEditingController(text: '100');
  final timeout = TextEditingController(text: '5000');
  final warmup = TextEditingController(text: '3');
  String? sessionId;
  String? phaseId;
  String scenario = 'E1';
  String direction = 'download';
  String protocol = 'http';
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
    statusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted &&
          (widget.network.isServing || widget.network.isParticipating)) {
        setState(() {});
      }
    });
    _loadAddresses();
    _loadHotspot();
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
    setState(() => busy = true);
    try {
      final value = hotspot?.active == true
          ? await hotspotAdapter.stop()
          : await hotspotAdapter.start();
      if (mounted) setState(() => hotspot = value);
      await _loadAddresses();
    } catch (e) {
      if (mounted) setState(() => feedback = 'Hotspot: $e');
    } finally {
      if (mounted) setState(() => busy = false);
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
    setState(() => busy = true);
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
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _toggleParticipant() async {
    setState(() => busy = true);
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
      if (mounted) setState(() => feedback = 'Participación: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _probe() async {
    setState(() {
      busy = true;
      feedback = null;
    });
    try {
      final response = await widget.network.probe(
        Uri.parse(address.text.trim()),
      );
      if (!mounted) return;
      setState(
        () => feedback =
            'Servidor ${response['name']} · protocolo ${response['version']} · capacidades ${response['capabilities']}',
      );
    } catch (e) {
      if (mounted) setState(() => feedback = 'Diagnóstico: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _discover() async {
    setState(() {
      busy = true;
      feedback = null;
    });
    try {
      final found = await widget.network.discover();
      if (!mounted) return;
      setState(() {
        discovered = found;
        if (found.length == 1) address.text = found.first.uri.toString();
        feedback = found.isEmpty
            ? 'No se encontró ningún servidor por UDP. Usa la IP manual si la red bloquea broadcasts.'
            : '${found.length} servidor(es) LANXIS encontrados.';
      });
    } catch (e) {
      if (mounted) setState(() => feedback = 'Descubrimiento: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _run() async {
    final sessions = widget.repository.sessions();
    final selectedSession = sessions
        .where((s) => s.id == sessionId)
        .firstOrNull;
    final selectedPhase = selectedSession == null
        ? null
        : widget.repository
              .phases(selectedSession.id)
              .where((p) => p.id == phaseId)
              .firstOrNull;
    if (selectedSession == null || selectedPhase == null) {
      setState(
        () => feedback = 'Selecciona una sesión y una fase en el laboratorio.',
      );
      return;
    }
    final n = int.tryParse(count.text);
    final k = int.tryParse(clients.text);
    final d = double.tryParse(distance.text.replaceAll(',', '.'));
    final bytes = int.tryParse(payload.text);
    final everyMs = int.tryParse(interval.text);
    final timeoutMs = int.tryParse(timeout.text);
    final warmupCount = int.tryParse(warmup.text);
    if (n == null ||
        k == null ||
        d == null ||
        bytes == null ||
        everyMs == null ||
        timeoutMs == null ||
        warmupCount == null ||
        n < 1 ||
        k < 1 ||
        d < 0 ||
        everyMs < 0 ||
        timeoutMs < 100 ||
        warmupCount < 0) {
      setState(
        () => feedback = 'Revisa cantidad, clientes, distancia y carga.',
      );
      return;
    }
    setState(() {
      busy = true;
      cancel = false;
      coordinating = k > 1 || {'E4', 'E5', 'E6'}.contains(scenario);
      progress = 0;
      feedback = null;
    });
    try {
      if (k > 1 || {'E4', 'E5', 'E6'}.contains(scenario)) {
        final actual = await widget.network.runCoordinatedTrial(
          session: selectedSession,
          phase: selectedPhase,
          config: TrialConfig(
            scenarioId: scenario,
            clients: k,
            distanceM: d,
            count: n,
            payloadBytes: bytes,
            protocol: protocol,
            direction: direction,
            intervalMs: everyMs,
            timeoutMs: timeoutMs,
            warmup: warmupCount,
          ),
        );
        if (!mounted) return;
        setState(
          () => feedback =
              'Ensayo coordinado: $actual/${n * k} mediciones recibidas de $k dispositivos.',
        );
        widget.onChanged();
        return;
      }
      final results = await widget.network.runTrial(
        base: Uri.parse(address.text.trim()),
        code: code.text.trim(),
        session: selectedSession,
        phase: selectedPhase,
        config: TrialConfig(
          scenarioId: scenario,
          clients: k,
          distanceM: d,
          count: n,
          payloadBytes: bytes,
          protocol: protocol,
          direction: direction,
          intervalMs: everyMs,
          timeoutMs: timeoutMs,
          warmup: warmupCount,
        ),
        cancelled: () => cancel,
        onProgress: (done, _) {
          if (mounted) setState(() => progress = done);
        },
      );
      final successes = results.where((r) => r.success).length;
      if (!mounted) return;
      setState(
        () => feedback =
            'Ensayo ${cancel ? 'cancelado' : 'terminado'}: $successes/${results.length} solicitudes respondieron. Resultados guardados.',
      );
      widget.onChanged();
    } catch (e) {
      if (mounted) setState(() => feedback = 'Ensayo interrumpido: $e');
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
    setState(() => scenario = value);
    final index = int.tryParse(value.replaceFirst('E', ''));
    if (index != null && index >= 1 && index <= 6) {
      clients.text = index <= 3 ? '1' : '4';
      distance.text = [1, 6, 12][(index - 1) % 3].toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = widget.repository.sessions();
    sessionId ??= sessions.firstOrNull?.id;
    final phases = sessionId == null
        ? <LabPhase>[]
        : widget.repository.phases(sessionId!);
    if (!phases.any((p) => p.id == phaseId)) phaseId = phases.firstOrNull?.id;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 42),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Conecta el laboratorio',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Usa una LAN existente o un hotspot configurado en el sistema. No se necesita Internet.',
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth > 700;
                  final server = AcrylicPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.dns_outlined, size: 28),
                        const SizedBox(height: 12),
                        Text(
                          'Este dispositivo como servidor',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.network.isServing
                              ? 'Escuchando en el puerto ${widget.network.port}'
                              : 'Servidor detenido',
                        ),
                        const SizedBox(height: 10),
                        if (widget.network.isServing)
                          SelectableText(
                            'Código de emparejamiento: ${widget.network.pairCode}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        if (widget.network.isServing)
                          Text(
                            '${widget.network.connectedClients} clientes registrados · ${widget.network.readyWorkers} participantes listos',
                          ),
                        if (widget.network.isServing)
                          TextButton.icon(
                            onPressed: () => setState(() {}),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Actualizar participantes'),
                          ),
                        const SizedBox(height: 8),
                        for (final ip in localAddresses) SelectableText(ip),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: busy ? null : _toggleServer,
                          icon: busy
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
                      ],
                    ),
                  );
                  final client = AcrylicPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.router_outlined, size: 28),
                        const SizedBox(height: 12),
                        Text(
                          'Conectar a un servidor',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: address,
                          decoration: const InputDecoration(
                            labelText: 'URL local',
                            hintText: 'http://192.168.1.1:8040',
                          ),
                          keyboardType: TextInputType.url,
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: code,
                          decoration: const InputDecoration(
                            labelText: 'Código de 6 dígitos',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: busy ? null : _discover,
                              icon: busy
                                  ? const GeometryLoader()
                                  : const Icon(Icons.radar_rounded),
                              label: const Text('Buscar en la LAN'),
                            ),
                            OutlinedButton.icon(
                              onPressed: busy ? null : _probe,
                              icon: const Icon(Icons.wifi_find),
                              label: const Text('Diagnosticar conexión'),
                            ),
                            OutlinedButton.icon(
                              onPressed: busy ? null : _toggleParticipant,
                              icon: Icon(
                                widget.network.isParticipating
                                    ? Icons.stop_circle_outlined
                                    : Icons.groups_outlined,
                              ),
                              label: Text(
                                widget.network.isParticipating
                                    ? 'Dejar de participar'
                                    : 'Participar en ensayos',
                              ),
                            ),
                          ],
                        ),
                        for (final server in discovered)
                          TextButton(
                            onPressed: () => setState(
                              () => address.text = server.uri.toString(),
                            ),
                            child: Text(server.uri.toString()),
                          ),
                        if (widget.network.lastParticipantError != null)
                          Text(
                            'Último problema del participante: ${widget.network.lastParticipantError}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        if (widget.repository.pendingResultCount > 0)
                          Text(
                            '${widget.repository.pendingResultCount} lotes de resultados conservados localmente; la sincronización se reintenta al participar en el mismo servidor.',
                          ),
                      ],
                    ),
                  );
                  return wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: server),
                            const SizedBox(width: 16),
                            Expanded(child: client),
                          ],
                        )
                      : Column(
                          children: [
                            server,
                            const SizedBox(height: 14),
                            client,
                          ],
                        );
                },
              ),
              const SizedBox(height: 16),
              AcrylicPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Red experimental',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hotspot == null
                          ? 'Consultando capacidad Wi-Fi…'
                          : hotspot!.active
                          ? 'Hotspot local activo'
                          : hotspot!.supported
                          ? 'El dispositivo puede intentar crear un hotspot local.'
                          : hotspot!.reason ??
                                'Configura un hotspot o una LAN en el sistema.',
                    ),
                    if (hotspot?.active == true) ...[
                      const SizedBox(height: 8),
                      SelectableText(
                        'SSID: ${hotspot!.ssid ?? 'No disponible'}',
                      ),
                      SelectableText(
                        'Clave: ${hotspot!.passphrase ?? 'No disponible'}',
                      ),
                      const Text(
                        'Comparte estos datos solo con participantes autorizados.',
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (hotspot?.supported == true)
                          OutlinedButton.icon(
                            onPressed: busy ? null : _toggleHotspot,
                            icon: busy
                                ? const GeometryLoader()
                                : const Icon(Icons.wifi_tethering),
                            label: Text(
                              hotspot!.active
                                  ? 'Detener hotspot'
                                  : 'Crear hotspot local',
                            ),
                          ),
                        if (Platform.isAndroid)
                          TextButton.icon(
                            onPressed: () =>
                                hotspotAdapter.openSystemWifiSettings(),
                            icon: const Icon(Icons.settings_outlined),
                            label: const Text('Abrir ajustes Wi-Fi'),
                          ),
                      ],
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
                      'Ejecutar ensayo HTTP',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'RTT de aplicación y descarga por bloques. Los datos se almacenan por ensayo y los fallos cuentan en el SLA.',
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'E4–E6 requieren coordinación simultánea de varios dispositivos; una ejecución individual no se registra como multicliente.',
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: 230,
                          child: DropdownButtonFormField<String>(
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
                                : (v) => setState(() {
                                    sessionId = v;
                                    phaseId = null;
                                  }),
                          ),
                        ),
                        SizedBox(
                          width: 210,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey(sessionId),
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
                                : (v) => setState(() => phaseId = v),
                          ),
                        ),
                        SizedBox(
                          width: 160,
                          child: DropdownButtonFormField<String>(
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
                                      });
                                    }
                                  },
                          ),
                        ),
                        SizedBox(
                          width: 160,
                          child: DropdownButtonFormField<String>(
                            initialValue: scenario,
                            decoration: const InputDecoration(
                              labelText: 'Escenario',
                            ),
                            items: [
                              for (final s in [
                                ...List.generate(6, (i) => 'E${i + 1}'),
                                'Libre',
                              ])
                                DropdownMenuItem(value: s, child: Text(s)),
                            ],
                            onChanged: busy
                                ? null
                                : (v) {
                                    if (v != null) _setScenario(v);
                                  },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _NumberField(
                          controller: count,
                          label: 'Peticiones',
                          width: 140,
                        ),
                        _NumberField(
                          controller: clients,
                          label: 'Clientes',
                          width: 130,
                        ),
                        _NumberField(
                          controller: distance,
                          label: 'Distancia · m',
                          width: 150,
                        ),
                        _NumberField(
                          controller: payload,
                          label: 'Carga · bytes',
                          width: 160,
                        ),
                        SizedBox(
                          width: 160,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('direction-$protocol-$direction'),
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
                                      setState(() => direction = value);
                                    }
                                  },
                          ),
                        ),
                        _NumberField(
                          controller: interval,
                          label: 'Intervalo · ms',
                          width: 160,
                        ),
                        _NumberField(
                          controller: timeout,
                          label: 'Timeout · ms',
                          width: 160,
                        ),
                        _NumberField(
                          controller: warmup,
                          label: 'Calentamiento',
                          width: 160,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (busy && progress > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: LinearProgressIndicator(
                          value: progress / (int.tryParse(count.text) ?? 1),
                        ),
                      ),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: busy ? null : _run,
                          icon: busy
                              ? const GeometryLoader()
                              : const Icon(Icons.play_arrow_rounded),
                          label: Text(
                            busy ? 'Midiendo $progress…' : 'Iniciar ensayo',
                          ),
                        ),
                        if (busy && !coordinating) ...[
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: () => setState(() => cancel = true),
                            child: const Text('Cancelar'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (feedback != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: AcrylicPanel(child: Text(feedback!)),
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
