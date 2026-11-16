import 'package:flutter_test/flutter_test.dart';
import 'package:lanxis/science/visualization_data.dart';

void main() {
  test('frequency polygons use identical class boundaries', () {
    final series = VisualizationData.polygons({
      'one': [1, 2, 3],
      'multi': [2, 3, 4],
    }, classes: 3);
    expect(series.length, 2);
    expect(
      series[0].bins.map((b) => b.lower),
      series[1].bins.map((b) => b.lower),
    );
    expect(series[0].bins.map((b) => b.frequency).reduce((a, b) => a + b), 3);
  });

  test('empirical CDF thresholds are strict', () {
    expect(VisualizationData.fractionBelow([20, 30, 40, 50], 30), .25);
    expect(VisualizationData.fractionBelow([20, 30, 40, 50], 50), .75);
  });
}
