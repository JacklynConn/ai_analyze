import 'dart:math' as math;

import '../models/candle.dart';
import '../models/technical_snapshot.dart';

/// Small, dependency-free technical-analysis toolkit.
/// All functions take the oldest candle first.
class Indicators {
  const Indicators._();

  static List<double> emaSeries(List<double> values, int period) {
    if (values.isEmpty) return <double>[];
    final k = 2 / (period + 1);
    final out = List<double>.filled(values.length, values.first);
    for (var i = 1; i < values.length; i++) {
      out[i] = values[i] * k + out[i - 1] * (1 - k);
    }
    return out;
  }

  static double ema(List<double> values, int period) {
    final s = emaSeries(values, period);
    return s.isEmpty ? 0 : s.last;
  }

  static double sma(List<double> values, int period) {
    if (values.isEmpty) return 0;
    final slice = values.length <= period ? values : values.sublist(values.length - period);
    return slice.reduce((a, b) => a + b) / slice.length;
  }

  static double stdev(List<double> values, int period) {
    if (values.length < 2) return 0;
    final slice = values.length <= period ? values : values.sublist(values.length - period);
    final mean = slice.reduce((a, b) => a + b) / slice.length;
    final variance = slice.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) / slice.length;
    return math.sqrt(variance);
  }

  /// Wilder RSI.
  static double rsi(List<double> closes, {int period = 14}) {
    if (closes.length < period + 1) return 50;
    var gain = 0.0;
    var loss = 0.0;
    for (var i = 1; i <= period; i++) {
      final change = closes[i] - closes[i - 1];
      if (change >= 0) {
        gain += change;
      } else {
        loss -= change;
      }
    }
    var avgGain = gain / period;
    var avgLoss = loss / period;
    for (var i = period + 1; i < closes.length; i++) {
      final change = closes[i] - closes[i - 1];
      avgGain = (avgGain * (period - 1) + (change > 0 ? change : 0)) / period;
      avgLoss = (avgLoss * (period - 1) + (change < 0 ? -change : 0)) / period;
    }
    if (avgLoss == 0) return 100;
    final rs = avgGain / avgLoss;
    return 100 - (100 / (1 + rs));
  }

  static (double macd, double signal, double hist) macd(
    List<double> closes, {
    int fast = 12,
    int slow = 26,
    int signalPeriod = 9,
  }) {
    if (closes.length < slow + signalPeriod) return (0, 0, 0);
    final fastE = emaSeries(closes, fast);
    final slowE = emaSeries(closes, slow);
    final macdLine = List<double>.generate(closes.length, (i) => fastE[i] - slowE[i]);
    final signalLine = emaSeries(macdLine, signalPeriod);
    final m = macdLine.last;
    final s = signalLine.last;
    return (m, s, m - s);
  }

  /// Average True Range (Wilder smoothing).
  static double atr(List<Candle> candles, {int period = 14}) {
    if (candles.length < period + 1) return 0;
    final trs = <double>[];
    for (var i = 1; i < candles.length; i++) {
      final c = candles[i];
      final prevClose = candles[i - 1].close;
      trs.add(math.max(c.high - c.low, math.max((c.high - prevClose).abs(), (c.low - prevClose).abs())));
    }
    var a = trs.take(period).reduce((x, y) => x + y) / period;
    for (var i = period; i < trs.length; i++) {
      a = (a * (period - 1) + trs[i]) / period;
    }
    return a;
  }

  /// Simplified ADX (trend strength, 0..100).
  static double adx(List<Candle> candles, {int period = 14}) {
    if (candles.length < period * 2) return 0;
    final plusDm = <double>[];
    final minusDm = <double>[];
    final trs = <double>[];
    for (var i = 1; i < candles.length; i++) {
      final upMove = candles[i].high - candles[i - 1].high;
      final downMove = candles[i - 1].low - candles[i].low;
      plusDm.add(upMove > downMove && upMove > 0 ? upMove : 0);
      minusDm.add(downMove > upMove && downMove > 0 ? downMove : 0);
      final prevClose = candles[i - 1].close;
      trs.add(math.max(candles[i].high - candles[i].low,
          math.max((candles[i].high - prevClose).abs(), (candles[i].low - prevClose).abs())));
    }
    final tr = sma(trs, period);
    if (tr == 0) return 0;
    final plusDi = 100 * sma(plusDm, period) / tr;
    final minusDi = 100 * sma(minusDm, period) / tr;
    final sum = plusDi + minusDi;
    if (sum == 0) return 0;
    return (100 * (plusDi - minusDi).abs() / sum);
  }

  static (double upper, double lower, double width) bollinger(List<double> closes, {int period = 20, double mult = 2}) {
    final mid = sma(closes, period);
    final sd = stdev(closes, period);
    final upper = mid + mult * sd;
    final lower = mid - mult * sd;
    final width = mid == 0 ? 0.0 : (upper - lower) / mid * 100;
    return (upper, lower, width);
  }

  /// Clusters swing highs/lows to obtain structure levels near price.
  static (double support, double resistance) structureLevels(List<Candle> candles, double price) {
    if (candles.isEmpty) return (price, price);
    const lookback = 3;
    final highs = <double>[];
    final lows = <double>[];
    final start = math.max(lookback, candles.length - 120);
    for (var i = start; i < candles.length - lookback; i++) {
      final c = candles[i];
      var isHigh = true;
      var isLow = true;
      for (var j = i - lookback; j <= i + lookback; j++) {
        if (j == i) continue;
        if (candles[j].high >= c.high) isHigh = false;
        if (candles[j].low <= c.low) isLow = false;
      }
      if (isHigh) highs.add(c.high);
      if (isLow) lows.add(c.low);
    }
    final supports = lows.where((l) => l < price).toList()..sort();
    final resistances = highs.where((h) => h > price).toList()..sort();
    final support = supports.isNotEmpty ? supports.last : candles.map((c) => c.low).reduce(math.min);
    final resistance = resistances.isNotEmpty ? resistances.first : candles.map((c) => c.high).reduce(math.max);
    return (support, resistance);
  }

  /// Full snapshot used by the signal engine and by the AI prompt.
  static TechnicalSnapshot snapshot(List<Candle> candles, {double? livePrice}) {
    if (candles.length < 30) return TechnicalSnapshot.empty();
    final closes = candles.map((c) => c.close).toList();
    final price = livePrice ?? closes.last;

    final ema9 = Indicators.ema(closes, 9);
    final ema21 = Indicators.ema(closes, 21);
    final ema50 = Indicators.ema(closes, 50);
    final ema200 = Indicators.ema(closes, math.min(200, closes.length));
    final rsiV = rsi(closes);
    final (m, s, h) = macd(closes);
    final atrV = atr(candles);
    final adxV = adx(candles);
    final (bbU, bbL, bbW) = bollinger(closes);
    final (sup, res) = structureLevels(candles, price);

    final recent = candles.length > 60 ? candles.sublist(candles.length - 60) : candles;
    final sessionHigh = recent.map((c) => c.high).reduce(math.max);
    final sessionLow = recent.map((c) => c.low).reduce(math.min);

    // --- Score: weighted vote of the classic checks -------------------------
    var score = 0.0;
    final notes = <String>[];

    if (ema21 > ema50) {
      score += 0.20;
      notes.add('EMA21 above EMA50 (short-term bullish structure)');
    } else {
      score -= 0.20;
      notes.add('EMA21 below EMA50 (short-term bearish structure)');
    }

    if (price > ema200) {
      score += 0.15;
      notes.add('Price above EMA200 — macro trend supports buyers');
    } else {
      score -= 0.15;
      notes.add('Price below EMA200 — macro trend favours sellers');
    }

    if (rsiV >= 55 && rsiV <= 70) {
      score += 0.15;
      notes.add('RSI ${rsiV.toStringAsFixed(1)} — bullish but not overbought');
    } else if (rsiV <= 45 && rsiV >= 30) {
      score -= 0.15;
      notes.add('RSI ${rsiV.toStringAsFixed(1)} — bearish momentum');
    } else if (rsiV > 70) {
      score -= 0.05;
      notes.add('RSI ${rsiV.toStringAsFixed(1)} — overbought, chase risk');
    } else if (rsiV < 30) {
      score += 0.05;
      notes.add('RSI ${rsiV.toStringAsFixed(1)} — oversold, bounce risk');
    }

    if (h > 0) {
      score += 0.15;
      notes.add('MACD histogram positive (momentum up)');
    } else {
      score -= 0.15;
      notes.add('MACD histogram negative (momentum down)');
    }

    if (adxV > 25) {
      notes.add('ADX ${adxV.toStringAsFixed(1)} — trending market');
      score *= 1.1;
    } else {
      notes.add('ADX ${adxV.toStringAsFixed(1)} — choppy / range-bound');
      score *= 0.8;
    }

    if (bbW < 0.6) notes.add('Bollinger squeeze — breakout pending, direction unclear');

    score = score.clamp(-1.0, 1.0);

    return TechnicalSnapshot(
      price: price,
      ema9: ema9,
      ema21: ema21,
      ema50: ema50,
      ema200: ema200,
      rsi: rsiV,
      macd: m,
      macdSignal: s,
      macdHist: h,
      atr: atrV,
      adx: adxV,
      bbUpper: bbU,
      bbLower: bbL,
      bbWidth: bbW,
      support: sup,
      resistance: res,
      sessionHigh: sessionHigh,
      sessionLow: sessionLow,
      score: score,
      notes: notes,
    );
  }
}
