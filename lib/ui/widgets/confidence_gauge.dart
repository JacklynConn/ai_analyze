import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';

class ConfidenceGauge extends StatelessWidget {
  const ConfidenceGauge({
    super.key,
    required this.value,
    required this.color,
    this.size = 92,
    this.label,
    this.threshold,
  });

  /// 0..1
  final double value;
  final Color color;
  final double size;
  final String? label;
  final double? threshold;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CustomPaint(
            size: Size.square(size),
            painter: _GaugePainter(
              value: value.clamp(0, 1),
              color: color,
              threshold: threshold,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '${(value * 100).round()}%',
                style: TextStyle(
                  fontSize: size * .24,
                  fontWeight: FontWeight.w800,
                  color: color,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label ?? 'confidence',
                style: TextStyle(fontSize: size * .1, color: AppColors.muted, letterSpacing: .3),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.value, required this.color, this.threshold});

  final double value;
  final Color color;
  final double? threshold;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    const startAngle = math.pi * 0.75;
    const sweep = math.pi * 1.5;

    final bg = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweep, false, bg);

    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweep * value, false, fg);

    if (threshold != null) {
      final angle = startAngle + sweep * threshold!.clamp(0, 1);
      final p1 = center + Offset(math.cos(angle), math.sin(angle)) * (radius - 7);
      final p2 = center + Offset(math.cos(angle), math.sin(angle)) * (radius + 7);
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = AppColors.text.withValues(alpha: .55)
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value || old.color != color || old.threshold != threshold;
}
