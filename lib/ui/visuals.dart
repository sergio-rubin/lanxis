import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

class LanxisColors {
  static const navy = Color(0xFF0B1B33);
  static const cyan = Color(0xFF4AC7D6);
  static const blue = Color(0xFF5576E8);
  static const mint = Color(0xFF83D8C5);
  static const ice = Color(0xFFF2F7FB);
  static const charcoal = Color(0xFF1C1E24);
  static const slate = Color(0xFF282B33);
}

ThemeData lanxisTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: LanxisColors.blue,
    brightness: brightness,
    primary: dark ? LanxisColors.cyan : const Color(0xFF3159D3),
    surface: dark ? LanxisColors.slate : Colors.white,
  );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: dark ? LanxisColors.charcoal : LanxisColors.ice,
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
    chipTheme: base.chipTheme.copyWith(
      selectedColor: dark ? const Color(0xFF344046) : const Color(0xFFE1EDF2),
      backgroundColor: dark ? const Color(0xFF292C33) : Colors.white,
      side: BorderSide(
        color: dark ? const Color(0xFF4A545B) : const Color(0xFFC7D2DC),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF343840) : const Color(0xFFEAF1F8),
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
  const GaussianBoot({super.key, required this.ready, this.onFinished});
  final bool ready;
  final VoidCallback? onFinished;
  @override
  State<GaussianBoot> createState() => _GaussianBootState();
}

class _GaussianBootState extends State<GaussianBoot>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  @override
  void initState() {
    super.initState();
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onFinished?.call();
    });
    if (widget.ready) controller.forward();
  }

  @override
  void didUpdateWidget(covariant GaussianBoot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ready && !oldWidget.ready && controller.value < 1) {
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
              Theme.of(context).brightness == Brightness.dark
                  ? LanxisColors.mint
                  : Theme.of(context).colorScheme.secondary,
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
        )!.withValues(alpha: .75 + .25 * convergence);
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
    for (var i = 0; i < labels.length; i++) {
      final x = ((i * 173 + 41) % 1000) / 1000 * size.width;
      final y = ((i * 227 + 63) % 1000) / 1000 * size.height;
      final painter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            fontFamily: 'Space Grotesk',
            fontSize: 22 + (i % 4) * 9,
            color: Colors.transparent,
            shadows: [
              Shadow(
                color: (dark ? const Color(0xFFB8C4C9) : LanxisColors.blue)
                    .withValues(alpha: dark ? .12 : .13),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(x, y));
    }
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
    this.blur = false,
  });
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final bool blur;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: dark ? const Color(0xE8282B33) : const Color(0xEFFFFFFF),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: dark ? const Color(0x3D9EABB2) : Colors.white,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .16 : .05),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: blur
          ? BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: panel,
            )
          : panel,
    );
  }
}

class GeometricNavBar extends StatelessWidget {
  const GeometricNavBar({
    super.key,
    required this.controller,
    required this.selectedIndex,
    required this.labels,
    required this.icons,
    required this.onSelected,
  });
  final PageController controller;
  final int selectedIndex;
  final List<String> labels;
  final List<IconData> icons;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: dark ? const Color(0xFF25272E) : const Color(0xFFF2F5FA),
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: .35),
            ),
          ),
        ),
        height: 72 + bottom,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final position =
                  controller.hasClients &&
                      controller.position.hasContentDimensions
                  ? (controller.page ?? selectedIndex.toDouble())
                  : selectedIndex.toDouble();
              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _MorphBubblePainter(
                        reduced ? selectedIndex.toDouble() : position,
                        labels.length,
                        scheme.primary,
                        dark,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < labels.length; i++)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: i == selectedIndex,
                            label: labels[i],
                            child: InkWell(
                              onTap: () => onSelected(i),
                              child: SizedBox(
                                height: 72,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      icons[i],
                                      size: 22,
                                      color: i == selectedIndex
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      labels[i],
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: i == selectedIndex
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: i == selectedIndex
                                            ? scheme.primary
                                            : scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MorphBubblePainter extends CustomPainter {
  _MorphBubblePainter(this.position, this.count, this.color, this.dark);
  final double position;
  final int count;
  final Color color;
  final bool dark;

  double _radiusAt(int shape, double angle) {
    final sides = [4, 3, 6, 0][shape.clamp(0, 3)];
    if (sides == 0) return 26;
    final sector = 2 * math.pi / sides;
    final local = (angle + math.pi / 2 + sector / 2) % sector - sector / 2;
    return 26 * math.cos(math.pi / sides) / math.cos(local);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (count == 0) return;
    final from = position.floor().clamp(0, count - 1);
    final to = (from + 1).clamp(0, count - 1);
    final mix = (position - from).clamp(0.0, 1.0);
    final center = Offset(size.width * (position + .5) / count, 28);
    final path = Path();
    for (var i = 0; i <= 64; i++) {
      final angle = -math.pi / 2 + i * math.pi * 2 / 64;
      final radius = ui.lerpDouble(
        _radiusAt(from, angle),
        _radiusAt(to, angle),
        mix,
      )!;
      final point =
          center +
          Offset(math.cos(angle) * radius, math.sin(angle) * radius * .79);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path..close(),
      Paint()..color = color.withValues(alpha: dark ? .19 : .12),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: dark ? .72 : .46)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _MorphBubblePainter old) =>
      old.position != position ||
      old.count != count ||
      old.color != color ||
      old.dark != dark;
}
