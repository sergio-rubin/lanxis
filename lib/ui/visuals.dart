import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

class LanxisColors {
  static const navy = Color(0xFF0B1B33);
  static const cyan = Color(0xFF4AC7D6);
  static const blue = Color(0xFF5576E8);
  static const mint = Color(0xFF83D8C5);
  static const ice = Color(0xFFF2F7FB);
}

ThemeData lanxisTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: LanxisColors.blue,
    brightness: brightness,
    primary: dark ? LanxisColors.cyan : const Color(0xFF3159D3),
    surface: dark ? const Color(0xFF101D32) : Colors.white,
  );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: dark ? const Color(0xFF081526) : LanxisColors.ice,
    fontFamily: 'Manrope',
  );
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      displayLarge: TextStyle(
        fontFamily: 'Space Grotesk',
        fontSize: 48,
        fontWeight: FontWeight.w600,
        height: 1.04,
        letterSpacing: -2,
        color: scheme.onSurface,
      ),
      headlineLarge: TextStyle(
        fontFamily: 'Space Grotesk',
        fontSize: 34,
        fontWeight: FontWeight.w600,
        letterSpacing: -1.3,
        color: scheme.onSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Space Grotesk',
        fontSize: 25,
        fontWeight: FontWeight.w600,
        letterSpacing: -.6,
        color: scheme.onSurface,
      ),
      titleLarge: TextStyle(
        fontFamily: 'Space Grotesk',
        fontSize: 19,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF172A43) : const Color(0xFFEAF1F8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

class GaussianMark extends StatelessWidget {
  const GaussianMark({super.key, this.size = 38, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _GaussianMarkPainter(
      color ?? Theme.of(context).colorScheme.primary,
    ),
  );
}

class _GaussianMarkPainter extends CustomPainter {
  _GaussianMarkPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 100;
    canvas.scale(scale);
    final fill = Paint()..color = color.withValues(alpha: .12);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final flask = Path()
      ..moveTo(32, 12)
      ..lineTo(68, 12)
      ..moveTo(42, 12)
      ..lineTo(42, 38)
      ..lineTo(17, 80)
      ..quadraticBezierTo(12, 89, 23, 90)
      ..lineTo(77, 90)
      ..quadraticBezierTo(88, 89, 83, 80)
      ..lineTo(58, 38)
      ..lineTo(58, 12);
    canvas.drawPath(flask, stroke);
    final liquid = Path()
      ..moveTo(25, 75)
      ..lineTo(75, 75)
      ..lineTo(82, 87)
      ..lineTo(18, 87)
      ..close();
    canvas.drawPath(liquid, fill);
    final curve = Path()..moveTo(25, 72);
    for (var i = 0; i <= 50; i++) {
      final x = 25.0 + i;
      final y = 72 - 23 * math.exp(-math.pow((x - 50) / 13, 2) / 2);
      curve.lineTo(x, y);
    }
    canvas.drawPath(curve, stroke..strokeWidth = 4);
    for (final x in [30.0, 40.0, 50.0, 60.0, 70.0]) {
      final height = 6 + 16 * math.exp(-math.pow((x - 50) / 13, 2) / 2);
      canvas.drawLine(
        Offset(x, 73),
        Offset(x, 73 - height),
        Paint()
          ..color = color.withValues(alpha: .55)
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GaussianMarkPainter old) => old.color != color;
}

class GaussianBoot extends StatefulWidget {
  const GaussianBoot({super.key, required this.ready});
  final bool ready;
  @override
  State<GaussianBoot> createState() => _GaussianBootState();
}

class _GaussianBootState extends State<GaussianBoot>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..forward();
  @override
  void didUpdateWidget(covariant GaussianBoot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ready && !controller.isAnimating && controller.value < 1) {
      controller.forward();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: widget.ready ? 'Laboratorio listo' : 'Preparando laboratorio',
      child: SizedBox(
        width: 290,
        height: 170,
        child: AnimatedBuilder(
          animation: controller,
          builder: (_, _) => CustomPaint(
            painter: _GaussianBootPainter(
              reduced ? 1 : controller.value,
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.secondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _GaussianBootPainter extends CustomPainter {
  _GaussianBootPainter(this.progress, this.primary, this.secondary);
  final double progress;
  final Color primary;
  final Color secondary;
  @override
  void paint(Canvas canvas, Size size) {
    final bars = 43;
    final base = size.height - 18;
    final width = size.width / bars;
    final convergence = Curves.easeInOutCubic.transform(progress);
    final line = Path();
    for (var i = 0; i < bars; i++) {
      final x = (i + .5) * width;
      final z = (i - (bars - 1) / 2) / 8.2;
      final gaussian = math.exp(-z * z / 2);
      final noisy = .16 + .35 * (math.sin(i * 2.7 + progress * 14) + 1) / 2;
      final h = (noisy * (1 - convergence) + gaussian * convergence) * 116 + 3;
      final paint = Paint()
        ..color = Color.lerp(
          secondary,
          primary,
          gaussian,
        )!.withValues(alpha: .48 + .48 * convergence);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - width * .24, base - h, width * .48, h),
          const Radius.circular(4),
        ),
        paint,
      );
      final y = base - gaussian * 119;
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }
    final metric = line.computeMetrics().first;
    final trace = metric.extractPath(0, metric.length * convergence);
    canvas.drawPath(
      trace,
      Paint()
        ..color = primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      Paint()
        ..color = primary.withValues(alpha: .2)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _GaussianBootPainter old) =>
      old.progress != progress ||
      old.primary != primary ||
      old.secondary != secondary;
}

class GeometryLoader extends StatefulWidget {
  const GeometryLoader({super.key, this.size = 20});
  final double size;
  @override
  State<GeometryLoader> createState() => _GeometryLoaderState();
}

class _GeometryLoaderState extends State<GeometryLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'Cargando',
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: controller,
          builder: (_, _) => CustomPaint(
            painter: _GeometryPainter(reduced ? 0 : controller.value),
          ),
        ),
      ),
    );
  }
}

class _GeometryPainter extends CustomPainter {
  _GeometryPainter(this.t);
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final segment = (t * 3).floor().clamp(0, 2);
    final sides = [4, 3, 5][segment];
    final colors = [LanxisColors.cyan, LanxisColors.blue, LanxisColors.mint];
    final path = Path();
    for (var i = 0; i < sides; i++) {
      final angle = -math.pi / 2 + 2 * math.pi * i / sides + t * math.pi * 2;
      final point = Offset(
        size.width / 2 + math.cos(angle) * size.width * .42,
        size.height / 2 + math.sin(angle) * size.height * .42,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path..close(), Paint()..color = colors[segment]);
  }

  @override
  bool shouldRepaint(covariant _GeometryPainter old) => old.t != t;
}

class MathBackground extends StatelessWidget {
  const MathBackground({super.key});
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      painter: _MathPainter(Theme.of(context).brightness == Brightness.dark),
      size: Size.infinite,
    ),
  );
}

class _MathPainter extends CustomPainter {
  _MathPainter(this.dark);
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    final labels = [
      'σ²',
      'μ',
      'P(A|B)',
      '∫ f(x) dx',
      '∑ xᵢ',
      'χ²',
      'n−1',
      'λ',
      'Z=(x−μ)/σ',
      '≈',
      '∞',
      'f(x)',
    ];
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
    );
    for (var i = 0; i < labels.length; i++) {
      final x = ((i * 173 + 41) % 1000) / 1000 * size.width;
      final y = ((i * 227 + 63) % 1000) / 1000 * size.height;
      final painter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            fontFamily: 'Space Grotesk',
            fontSize: 22 + (i % 4) * 9,
            color: (dark ? LanxisColors.cyan : LanxisColors.blue).withValues(
              alpha: dark ? .11 : .09,
            ),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(x, y));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MathPainter old) => old.dark != dark;
}

class AcrylicPanel extends StatelessWidget {
  const AcrylicPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.radius = 24,
  });
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: dark ? const Color(0xD9203049) : const Color(0xEFFFFFFF),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: dark ? const Color(0x4483D8C5) : Colors.white,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? .16 : .05),
                blurRadius: 26,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
