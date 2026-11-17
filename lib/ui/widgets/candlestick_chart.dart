import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart' as intl;

import '../../core/theme.dart';
import '../../models/candle.dart';
import '../../models/signal.dart';
import '../../models/technical_snapshot.dart';

/// Hand-rolled candlestick chart (no chart package): candles, EMA overlays,
/// volume, live price tag and SL/TP projection lines.
class CandleChart extends StatelessWidget {
  const CandleChart({
    super.key,
    required this.candles,
    this.tech,
    this.plan,
    this.height = 260,
    this.visibleCount = 70,
    this.showEma = true,
    this.showVolume = true,
    this.showPlanLevels = true,
  });

  final List<Candle> candles;
  final TechnicalSnapshot? tech;
  final TradePlan? plan;
  final double height;
  final int visibleCount;
  final bool showEma;
  final bool showVolume;
  final bool showPlanLevels;

  @override
  Widget build(BuildContext context) {
    if (candles.length < 5) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('Waiting for candles…', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _CandlePainter(
          candles: candles,
          tech: tech,
          plan: showPlanLevels ? plan : null,
          visibleCount: visibleCount,
          showEma: showEma,
          showVolume: showVolume,
          isDark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    );
  }
}

class _CandlePainter extends CustomPainter {
  _CandlePainter({
    required this.candles,
    required this.tech,
    required this.plan,
    required this.visibleCount,
    required this.showEma,
    required this.showVolume,
    required this.isDark,
  });

  final List<Candle> candles;
  final TechnicalSnapshot? tech;
  final TradePlan? plan;
  final int visibleCount;
  final bool showEma;
  final bool showVolume;
  final bool isDark;

  static final intl.NumberFormat _fmt = intl.NumberFormat('#,##0.0');

  @override
  void paint(Canvas canvas, Size size) {
    const rightPad = 56.0;
    const bottomPad = 16.0;
    final plotW = size.width - rightPad;
    final plotH = size.height - bottomPad;

    final visible = candles.length > visibleCount
        ? candles.sublist(candles.length - visibleCount)
        : List<Candle>.from(candles);
    if (visible.isEmpty) return;

    var minLow = visible.map((c) => c.low).reduce(math.min);
    var maxHigh = visible.map((c) => c.high).reduce(math.max);

    // include overlaid levels so they are never clipped
    if (plan != null) {
      for (final v in <double>[plan!.entry, plan!.stopLoss, plan!.takeProfit1, plan!.takeProfit2]) {
        if (v < minLow) minLow = v;
        if (v > maxHigh) maxHigh = v;
      }
    }
    final pad = (maxHigh - minLow) * 0.06 + 0.5;
    minLow -= pad;
    maxHigh += pad;
    final range = math.max(maxHigh - minLow, 0.01);

    double yFor(double price) => plotH - ((price - minLow) / range) * plotH;

    // ---------------------------------------------------------------- grid
    final gridPaint = Paint()
      ..color = AppColors.border.withValues(alpha: .75)
      ..strokeWidth = 0.8;
    for (var i = 0; i <= 4; i++) {
      final y = plotH * i / 4;
      canvas.drawLine(Offset(0, y), Offset(plotW, y), gridPaint);
      final price = maxHigh - range * i / 4;
      _text(canvas, _fmt.format(price), Offset(plotW + 6, y - 6), AppColors.muted, 9.5);
    }

    // -------------------------------------------------------------- volume
    final volH = showVolume ? plotH * 0.16 : 0.0;
    final maxVol = visible.map((c) => c.volume).fold<double>(1, math.max);

    final step = plotW / visible.length;
    final bodyW = math.max(1.6, math.min(step * 0.62, 9.0));

    for (var i = 0; i < visible.length; i++) {
      final c = visible[i];
      final x = step * i + step / 2;
      final color = c.isBull ? AppColors.buy : AppColors.sell;

      final wick = Paint()
        ..color = color
        ..strokeWidth = math.min(1.4, bodyW / 3.0);

      canvas.drawLine(Offset(x, yFor(c.high)), Offset(x, yFor(c.low)), wick);

      final openY = yFor(c.open);
      final closeY = yFor(c.close);
      final top = math.min(openY, closeY);
      final h = math.max((openY - closeY).abs(), 1.2);
      final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - bodyW / 2, top, bodyW, h),
        const Radius.circular(1),
      );
      canvas.drawRRect(body, Paint()..color = color);

      if (showVolume && c.volume > 0) {
        final vh = (c.volume / maxVol) * volH;
        canvas.drawRect(
          Rect.fromLTWH(x - bodyW / 2, plotH - vh, bodyW, vh),
          Paint()..color = color.withValues(alpha: .22),
        );
      }
    }

    // ----------------------------------------------------------------- EMA
    if (showEma && candles.length > 30) {
      _drawEma(canvas, candles, 21, plotW, plotH, visible.length, yFor, const Color(0xFF4F9CFF), step);
      _drawEma(canvas, candles, 50, plotW, plotH, visible.length, yFor, const Color(0xFFB87BFF), step);
    }

    // ------------------------------------------------------- SL / TP levels
    if (plan != null) {
      _level(canvas, plotW, yFor(plan!.takeProfit2), 'TP2', AppColors.buy);
      _level(canvas, plotW, yFor(plan!.takeProfit1), 'TP1', AppColors.buy);
      _level(canvas, plotW, yFor(plan!.entry), 'ENTRY', AppColors.gold, dashed: false, bold: true);
      _level(canvas, plotW, yFor(plan!.stopLoss), 'SL', AppColors.sell);
    }

    // ------------------------------------------------------- live price tag
    final last = visible.last.close;
    final ly = yFor(last);
    final liveColor = visible.last.isBull ? AppColors.buy : AppColors.sell;
    canvas.drawLine(
      Offset(0, ly),
      Offset(plotW, ly),
      Paint()
        ..color = liveColor.withValues(alpha: .45)
        ..strokeWidth = 0.9,
    );
    final tagRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(plotW + 2, ly - 8, rightPad - 4, 16),
      const Radius.circular(4),
    );
    canvas.drawRRect(tagRect, Paint()..color = liveColor);
    _text(canvas, _fmt.format(last), Offset(plotW + 7, ly - 6.5), const Color(0xFF06080D), 9.5, bold: true);

    // ---------------------------------------------------------- time labels
    final tf = intl.DateFormat('HH:mm');
    final first = visible.first.time;
    final mid = visible[visible.length ~/ 2].time;
    final lastT = visible.last.time;
    _text(canvas, tf.format(first), Offset(0, plotH + 2), AppColors.muted, 9);
    _text(canvas, tf.format(mid), Offset(plotW / 2 - 14, plotH + 2), AppColors.muted, 9);
    _text(canvas, tf.format(lastT), Offset(plotW - 30, plotH + 2), AppColors.muted, 9);
  }

  void _level(Canvas canvas, double plotW, double y, String label, Color color,
      {bool dashed = true, bool bold = false}) {
    final paint = Paint()
      ..color = color.withValues(alpha: bold ? .9 : .65)
      ..strokeWidth = bold ? 1.2 : 1;
    if (dashed) {
      var x = 0.0;
      while (x < plotW) {
        canvas.drawLine(Offset(x, y), Offset(x + 5, y), paint);
        x += 9;
      }
    } else {
      canvas.drawLine(Offset(0, y), Offset(plotW, y), paint);
    }
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: color, fontSize: 8.5, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2, y - tp.height / 2 - 1, tp.width + 6, tp.height + 2),
        const Radius.circular(3),
      ),
      Paint()..color = AppColors.bg.withValues(alpha: .8),
    );
    tp.paint(canvas, Offset(5, y - tp.height / 2));
  }

  void _drawEma(
    Canvas canvas,
    List<Candle> all,
    int period,
    double plotW,
    double plotH,
    int count,
    double Function(double) yFor,
    Color color,
    double step,
  ) {
    final closes = all.map((c) => c.close).toList();
    final k = 2 / (period + 1);
    final emas = List<double>.filled(closes.length, closes.first);
    for (var i = 1; i < closes.length; i++) {
      emas[i] = closes[i] * k + emas[i - 1] * (1 - k);
    }
    final startIndex = closes.length - count;
    final path = Path();
    for (var i = 0; i < count; i++) {
      final x = step * i + step / 2;
      final y = yFor(emas[startIndex + i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: .85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );
  }

  void _text(Canvas canvas, String text, Offset pos, Color color, double size, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _CandlePainter old) =>
      old.candles.length != candles.length ||
      old.plan != plan ||
      (candles.isNotEmpty && old.candles.isNotEmpty && old.candles.last.close != candles.last.close) ||
      old.visibleCount != visibleCount;
}
