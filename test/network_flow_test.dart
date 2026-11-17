import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/data/lab_repository.dart';
import 'package:lanxis/network/network_lab.dart';
import 'package:lanxis/ui/screens.dart';
import 'package:lanxis/ui/visuals.dart';
import 'package:material_ui/material_ui.dart';

class _FakeNetwork extends NetworkLab {
  _FakeNetwork(super.repository);
  @override
  int get readyWorkers => 3;
  @override
  Future<Map<String, Object?>> probe(Uri base) async => {
    'name': 'LANXIS',
    'version': 1,
  };
  @override
  Future<Map<String, Object?>> register(Uri base, String code) async {
    if (code != '715289') throw const FormatException('Código incorrecto');
    return {'client_id': clientId};
  }
}

void main() {
  testWidgets('connection and fields survive tab swipe', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = LabRepository.inMemory();
    addTearDown(repo.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: lanxisTheme(Brightness.light),
        home: LabShell(
          repository: repo,
          network: _FakeNetwork(repo),
          mode: ThemeMode.light,
          onModeChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('Red local').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Dirección del servidor'),
      'http://192.168.1.65:8040',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Código de seis dígitos'),
      '715289',
    );
    final codeFocus = tester
        .widget<EditableText>(
          find.descendant(
            of: find.widgetWithText(TextField, 'Código de seis dígitos'),
            matching: find.byType(EditableText),
          ),
        )
        .focusNode;
    await tester.ensureVisible(find.text('Conectar y comprobar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conectar y comprobar'));
    await tester.pumpAndSettle();
    expect(find.text('Conectado a LANXIS'), findsOneWidget);
    await tester.tap(find.text('Análisis').last);
    await tester.pumpAndSettle();
    expect(codeFocus.hasFocus, false);
    await tester.drag(find.byType(PageView), const Offset(330, 0));
    await tester.pumpAndSettle();
    expect(find.text('Conectado a LANXIS'), findsOneWidget);
    expect(find.text('http://192.168.1.65:8040'), findsWidgets);
    expect(find.text('715289'), findsWidgets);
  });

  testWidgets('reference preview adapts and custom scenario can be saved', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = LabRepository.inMemory();
    addTearDown(repo.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: lanxisTheme(Brightness.light),
        home: LabShell(
          repository: repo,
          network: _FakeNetwork(repo),
          mode: ThemeMode.light,
          onModeChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('Red local').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Iniciar servidor y medir'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('Configurar y medir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scenario-E1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('E4').last);
    await tester.pumpAndSettle();
    expect(find.text('Vista previa · E4'), findsOneWidget);
    expect(find.text('Participantes listos: 3/3'), findsOneWidget);
    await tester.ensureVisible(find.text('Abierto'));
    await tester.tap(find.text('Abierto'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Transferencia'));
    await tester.tap(find.text('Transferencia'));
    await tester.pumpAndSettle();
    expect(find.textContaining('65536 bytes por petición'), findsOneWidget);
    expect(find.textContaining('Espera 7000 ms'), findsOneWidget);
    await tester.drag(find.byType(NetworkScreen), const Offset(0, 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scenario-E4')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Libre · configurar').last);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(NetworkScreen), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar escenario'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre del escenario'),
      'Patio personalizado',
    );
    await tester.tap(find.text('Crear').last);
    await tester.pumpAndSettle();
    expect(repo.scenarioTemplates().single.name, 'Patio personalizado');
    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();
  });
}
