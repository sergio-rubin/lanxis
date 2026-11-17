import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/lab_repository.dart';
import 'network/network_lab.dart';
import 'ui/screens.dart';
import 'ui/visuals.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LanxisApp());
}

/// The Android foreground service runs this isolate without a Flutter view.
@pragma('vm:entry-point')
Future<void> participantBackgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mx.lanxis/participant_worker');
  final state = await channel.invokeMapMethod<String, String>('state');
  final base = Uri.tryParse(state?['base'] ?? '');
  final code = state?['code'] ?? '';
  if (base == null ||
      base.scheme != 'http' ||
      base.host.isEmpty ||
      !RegExp(r'^\d{6}$').hasMatch(code)) {
    return;
  }
  final repo = await LabRepository.open();
  try {
    await NetworkLab(repo).runParticipantWorker(base, code);
  } finally {
    repo.dispose();
  }
}

class LanxisApp extends StatefulWidget {
  const LanxisApp({super.key});
  @override
  State<LanxisApp> createState() => _LanxisAppState();
}

class _LanxisAppState extends State<LanxisApp> {
  LabRepository? repository;
  NetworkLab? network;
  Object? error;
  bool introComplete = false;
  ThemeMode mode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initialize();
    });
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString('theme');
      final repo = await LabRepository.open();
      final restoredNetwork = NetworkLab(repo);
      await restoredNetwork.restoreParticipant();
      if (!mounted) {
        repo.dispose();
        return;
      }
      setState(() {
        repository = repo;
        network = restoredNetwork;
        mode = value == 'light'
            ? ThemeMode.light
            : value == 'dark'
            ? ThemeMode.dark
            : ThemeMode.system;
      });
      if (WidgetsBinding
              .instance
              .platformDispatcher
              .accessibilityFeatures
              .disableAnimations &&
          mounted) {
        setState(() => introComplete = true);
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> _setMode(ThemeMode next) async {
    setState(() => mode = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', next.name);
  }

  @override
  void dispose() {
    if (network != null) unawaited(network!.stopServer());
    repository?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LANXIS',
    debugShowCheckedModeBanner: false,
    theme: lanxisTheme(Brightness.light),
    darkTheme: lanxisTheme(Brightness.dark),
    themeMode: mode,
    home: error != null
        ? Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 42),
                    const SizedBox(height: 16),
                    const Text('No se pudo abrir el laboratorio'),
                    const SizedBox(height: 8),
                    Text('$error'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        setState(() => error = null);
                        _initialize();
                      },
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            ),
          )
        : repository == null || !introComplete
        ? Builder(
            builder: (context) => Scaffold(
              body: Stack(
                children: [
                  const Positioned.fill(child: MathBackground()),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const GaussianMark(size: 52),
                        const SizedBox(height: 24),
                        Text(
                          'LANXIS',
                          style: Theme.of(context).textTheme.displayLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          repository == null
                              ? 'Preparando laboratorio local'
                              : 'Laboratorio listo',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 34),
                        GaussianBoot(
                          ready: repository != null,
                          onFinished: () {
                            if (mounted) setState(() => introComplete = true);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
        : LabShell(
            repository: repository!,
            network: network!,
            mode: mode,
            onModeChanged: _setMode,
          ),
  );
}
