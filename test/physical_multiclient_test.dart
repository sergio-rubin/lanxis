import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/data/lab_repository.dart';
import 'package:lanxis/network/network_lab.dart';

/// Hardware test: Android hosts while two independent Linux participants wait.
void main() {
  const enabled = bool.fromEnvironment('LANXIS_PHYSICAL_MULTI_CLIENT');
  const baseText = String.fromEnvironment('LANXIS_BASE');
  const code = String.fromEnvironment('LANXIS_CODE');
  const outputFile = String.fromEnvironment(
    'LANXIS_PHYSICAL_OUTPUT',
    defaultValue: 'dist/physical-android-server-2clients.json',
  );

  test(
    'Android coordinates a trial with two Linux participants',
    () async {
      expect(RegExp(r'^\d{6}$').hasMatch(code), true);
      final base = Uri.parse(baseText);
      final repositories = [LabRepository.inMemory(), LabRepository.inMemory()];
      final participants = repositories.map(NetworkLab.new).toList();
      Timer? monitor;
      try {
        for (final participant in participants) {
          await participant.startParticipant(base, code);
          stdout.writeln('Participante listo: ${participant.clientId}');
        }
        expect(
          participants.map((participant) => participant.clientId).toSet(),
          hasLength(2),
        );
        monitor = Timer.periodic(const Duration(seconds: 3), (_) {
          stdout.writeln(
            'Muestras: ${repositories.map((repo) => repo.sessions().fold<int>(0, (sum, session) => sum + repo.measurementCount(session.id))).join(' / ')}; errores: ${participants.map((participant) => participant.lastParticipantError ?? 'ninguno').join(' / ')}',
          );
        });
        final deadline = DateTime.now().add(const Duration(minutes: 12));
        while (DateTime.now().isBefore(deadline)) {
          final counts = repositories
              .map(
                (repo) => repo.sessions().fold<int>(
                  0,
                  (sum, session) => sum + repo.measurementCount(session.id),
                ),
              )
              .toList();
          if (counts.every((count) => count >= 5) &&
              repositories.every((repo) => repo.pendingResultCount == 0)) {
            break;
          }
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        final records = <Map<String, Object?>>[];
        for (var index = 0; index < repositories.length; index++) {
          final repo = repositories[index];
          final samples = [
            for (final session in repo.sessions())
              ...repo.measurements(session.id),
          ];
          records.add({
            'client_id': participants[index].clientId,
            'samples': samples.map((sample) => sample.toJson()).toList(),
            'pending_results': repo.pendingResultCount,
            'last_error': participants[index].lastParticipantError,
          });
        }
        final output = File(outputFile);
        output.parent.createSync(recursive: true);
        output.writeAsStringSync(
          jsonEncode({
            'server': base.toString(),
            'observed_at_utc': DateTime.now().toUtc().toIso8601String(),
            'clients': records,
          }),
        );
        stdout.writeln('Resultados: ${output.path}');
        for (final record in records) {
          expect((record['samples'] as List).length, greaterThanOrEqualTo(5));
          expect(record['pending_results'], 0);
        }
      } finally {
        monitor?.cancel();
        for (final participant in participants) {
          await participant.stopParticipant();
        }
        for (final repo in repositories) {
          repo.dispose();
        }
      }
    },
    skip: !enabled || baseText.isEmpty || code.isEmpty,
    timeout: const Timeout(Duration(minutes: 14)),
  );
}
