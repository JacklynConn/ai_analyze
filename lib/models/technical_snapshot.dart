/// Result of the on-device technical analysis pass.
class TechnicalSnapshot {
  final double price;
  final double ema9;
  final double ema21;
  final double ema50;
  final double ema200;
  final double rsi;
  final double macd;
  final double macdSignal;
  final double macdHist;
  final double atr;
  final double adx;
  final double bbUpper;
  final double bbLower;
  final double bbWidth;
  final double support;
  final double resistance;
  final double sessionHigh;
  final double sessionLow;

  /// -1 (strongly bearish) .. +1 (strongly bullish)
  final double score;
  final List<String> notes;

  const TechnicalSnapshot({
    required this.price,
    required this.ema9,
    required this.ema21,
    required this.ema50,
    required this.ema200,
    required this.rsi,
    required this.macd,
    required this.macdSignal,
    required this.macdHist,
    required this.atr,
    required this.adx,
    required this.bbUpper,
    required this.bbLower,
    required this.bbWidth,
    required this.support,
    required this.resistance,
    required this.sessionHigh,
    required this.sessionLow,
    required this.score,
    required this.notes,
  });

  bool get trendUp => ema21 > ema50 && ema50 > ema200;
  bool get trendDown => ema21 < ema50 && ema50 < ema200;

  /// Distance from current price to the nearest structure level, in ATR units.
  double get distanceToResistanceAtr => atr == 0 ? 99 : (resistance - price) / atr;
  double get distanceToSupportAtr => atr == 0 ? 99 : (price - support) / atr;

  static TechnicalSnapshot empty() => const TechnicalSnapshot(
        price: 0,
        ema9: 0,
        ema21: 0,
        ema50: 0,
        ema200: 0,
        rsi: 50,
        macd: 0,
        macdSignal: 0,
        macdHist: 0,
        atr: 0,
        adx: 0,
        bbUpper: 0,
        bbLower: 0,
        bbWidth: 0,
        support: 0,
        resistance: 0,
        sessionHigh: 0,
        sessionLow: 0,
        score: 0,
        notes: <String>[],
      );
}
