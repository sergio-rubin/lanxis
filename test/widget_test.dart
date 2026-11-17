import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/ui/visuals.dart';

void main() {
  testWidgets('brand and loaders render with accessible labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const GaussianMark(),
              const GaussianBoot(ready: false),
              const GeometryLoader(),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(GaussianMark), findsOneWidget);
    expect(find.bySemanticsLabel('Preparando laboratorio'), findsOneWidget);
    expect(find.bySemanticsLabel('Cargando'), findsOneWidget);
  });
}
