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
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('network ${brightness.name} 390x844', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = LabRepository.inMemory();
      addTearDown(repo.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: lanxisTheme(brightness),
          home: LabShell(
            repository: repo,
            network: NetworkLab(repo),
            mode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            onModeChanged: (_) {},
          ),
        ),
      );
      await tester.tap(find.text('Red local').last);
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(LabShell),
        matchesGoldenFile('goldens/network_${brightness.name}_390.png'),
      );
    });
  }
  testWidgets('boot dark at Gaussian formation', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: lanxisTheme(Brightness.dark),
        home: Builder(
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
                        'Preparando laboratorio local',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 34),
                      const GaussianBoot(ready: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1300));
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/boot_dark_390.png'),
    );
  });
}
