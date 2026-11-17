/// OHLCV candle.
class Candle {
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  const Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume = 0,
  });

  bool get isBull => close >= open;
  double get body => (close - open).abs();
  double get range => (high - low).abs();
  double get mid => (high + low) / 2;

  Candle copyWith({double? close, double? high, double? low, double? volume}) => Candle(
        time: time,
        open: open,
        high: high ?? this.high,
        low: low ?? this.low,
        close: close ?? this.close,
        volume: volume ?? this.volume,
      );

  /// Applies a live tick to the (still forming) candle.
  Candle withTick(double price) => copyWith(
        close: price,
        high: price > high ? price : high,
        low: price < low ? price : low,
      );

  static Candle? fromYahoo(List<dynamic> row) {
    if (row.length < 5) return null;
    final ts = row[0];
    final o = row[1], h = row[2], l = row[3], c = row[4];
    if (ts is! num || o is! num || h is! num || l is! num || c is! num) return null;
    return Candle(
      time: DateTime.fromMillisecondsSinceEpoch(ts.toInt() * 1000),
      open: o.toDouble(),
      high: h.toDouble(),
      low: l.toDouble(),
      close: c.toDouble(),
      volume: row.length > 5 && row[5] is num ? (row[5] as num).toDouble() : 0,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        't': time.millisecondsSinceEpoch,
        'o': open,
        'h': high,
        'l': low,
        'c': close,
        'v': volume,
      };

  factory Candle.fromJson(Map<String, dynamic> j) => Candle(
        time: DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt()),
        open: (j['o'] as num).toDouble(),
        high: (j['h'] as num).toDouble(),
        low: (j['l'] as num).toDouble(),
        close: (j['c'] as num).toDouble(),
        volume: (j['v'] as num?)?.toDouble() ?? 0,
      );
}

/// Live quote.
class Tick {
  final double price;
  final DateTime time;
  final double? bid;
  final double? ask;
  final double dayChangePct;

  const Tick({
    required this.price,
    required this.time,
    this.bid,
    this.ask,
    this.dayChangePct = 0,
  });

  double get spread => (ask != null && bid != null) ? (ask! - bid!) : 0;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'p': price,
        't': time.millisecondsSinceEpoch,
        'b': bid,
        'a': ask,
        'd': dayChangePct,
      };

  factory Tick.fromJson(Map<String, dynamic> j) => Tick(
        price: (j['p'] as num).toDouble(),
        time: DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt()),
        bid: (j['b'] as num?)?.toDouble(),
        ask: (j['a'] as num?)?.toDouble(),
        dayChangePct: (j['d'] as num?)?.toDouble() ?? 0,
      );
}
