import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/science/inference.dart';
import 'package:lanxis/ui/distribution_explorer.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('theoretical explorer updates probability and checks input', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: DistributionExplorer()),
        ),
      ),
    );
    expect(find.text('Explorador de distribuciones'), findsOneWidget);
    expect(
      find.textContaining(
        '${(ProbabilityEngine.binomialPmf(20, 5, .2) * 100).toStringAsFixed(3)}%',
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).at(2), '0.3');
    await tester.pump();
    expect(
      find.textContaining(
        '${(ProbabilityEngine.binomialPmf(20, 5, .3) * 100).toStringAsFixed(3)}%',
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).at(2), '1.5');
    await tester.pump();
    expect(find.textContaining('Revisa el dominio'), findsOneWidget);
  });

  testWidgets('continuous model renders on a narrow screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: DistributionExplorer()),
        ),
      ),
    );
    await tester.tap(find.text('Binomial').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Normal').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('P(40.0 ≤ X ≤ 60.0)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
