import 'models.dart';

class ScenarioPreview {
  const ScenarioPreview({
    required this.config,
    required this.readyClients,
    required this.requiredClients,
    required this.description,
  });
  final TrialConfig config;
  final int readyClients;
  final int requiredClients;
  final String description;
  bool get enoughParticipants => readyClients >= requiredClients;
  int get totalSamples => config.count * config.clients;
}

class ScenarioPlanner {
  const ScenarioPlanner._();

  static ScenarioPreview reference({
    required String scenarioId,
    required String environment,
    required String load,
    required int readyClients,
    int count = 100,
  }) {
    final index = int.tryParse(scenarioId.replaceFirst('E', ''));
    if (index == null || index < 1 || index > 6) {
      throw ArgumentError.value(scenarioId, 'scenarioId');
    }
    if (!{'indoor', 'outdoor'}.contains(environment) ||
        !{'latency', 'balanced', 'throughput'}.contains(load)) {
      throw ArgumentError('Ambiente o carga inválidos');
    }
    final multi = index > 3;
    final clients = multi && readyClients >= 3
        ? readyClients.clamp(3, 5)
        : multi
        ? 4
        : 1;
    final payload = switch (load) {
      'latency' => 0,
      'balanced' => 16 * 1024,
      _ => 64 * 1024,
    };
    final baseInterval = switch (load) {
      'latency' => 100,
      'balanced' => 150,
      _ => 250,
    };
    final target = [1.0, 6.0, 12.0][(index - 1) % 3];
    final config = TrialConfig(
      scenarioId: scenarioId,
      clients: clients,
      count: count,
      targetDistanceM: target,
      environment: environment,
      payloadBytes: payload,
      intervalMs: baseInterval * clients,
      timeoutMs: environment == 'outdoor' ? 7000 : 5000,
      warmup: environment == 'outdoor' ? 5 : 3,
    );
    return ScenarioPreview(
      config: config,
      readyClients: readyClients,
      requiredClients: multi ? 3 : 1,
      description:
          '${multi ? 'Multicliente' : 'Un cliente'} · '
          '${target.toStringAsFixed(0)} m objetivo · '
          '${environment == 'outdoor' ? 'ambiente abierto' : 'ambiente cerrado'}',
    );
  }
}
