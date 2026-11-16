import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lanxis/data/lab_repository.dart';
import 'package:lanxis/network/network_lab.dart';
import 'package:lanxis/ui/screens.dart';
import 'package:lanxis/ui/visuals.dart';

Future<void> loadFonts() async {
  for (final (family, path) in [
    ('Manrope', 'assets/fonts/Manrope.ttf'),
    ('Space Grotesk', 'assets/fonts/SpaceGrotesk.ttf'),
    ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
  ]) {
    final loader = FontLoader(family)..addFont(rootBundle.load(path));
    await loader.load();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);
  for (final size in [const Size(1200, 900), const Size(390, 844)]) {
    testWidgets('dashboard ${size.width.toInt()}x${size.height.toInt()}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
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
            network: NetworkLab(repo),
            mode: ThemeMode.light,
            onModeChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expectLater(
        find.byType(LabShell),
        matchesGoldenFile('goldens/dashboard_${size.width.toInt()}.png'),
      );
    });
  }
}
