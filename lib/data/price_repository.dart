import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/http_headers.dart';
import '../models/candle.dart';

abstract class PriceRepository {
  /// Human readable feed name shown in the UI.
  String get label;

  bool get isLive;

  Stream<Tick> ticks();

  Future<List<Candle>> candles({String interval = '5m', int limit = 200});

  void dispose();
}

// ---------------------------------------------------------------------------
// DEMO feed — deterministic-ish random walk, works with zero configuration.
// ---------------------------------------------------------------------------
class MockPriceRepository implements PriceRepository {
  MockPriceRepository({double seedPrice = 4182.40}) : _price = seedPrice {
    _buildHistory();
    _timer = Timer.periodic(const Duration(milliseconds: 900), (_) => _emit());
  }

  final math.Random _rng = math.Random(20261117);
  final List<Candle> _candles = <Candle>[];
  final StreamController<Tick> _controller = StreamController<Tick>.broadcast();

  late double _price;
  late double _openDay;
  double _drift = 0.0;
  int _regimeLeft = 60;
  Timer? _timer;

  @override
  String get label => 'DEMO feed (simulated)';

  @override
  bool get isLive => false;

  void _buildHistory() {
    var p = _price - 26;
    final now = DateTime.now();
    final start = now.subtract(const Duration(minutes: 5 * 220));
    _openDay = p;
    for (var i = 0; i < 220; i++) {
      final drift = math.sin(i / 18) * 0.55 + math.sin(i / 51) * 0.9;
      final o = p;
      final c = o + drift + (_rng.nextDouble() - 0.5) * 3.4;
      final h = math.max(o, c) + _rng.nextDouble() * 1.6;
      final l = math.min(o, c) - _rng.nextDouble() * 1.6;
      _candles.add(Candle(
        time: start.add(Duration(minutes: 5 * i)),
        open: o,
        high: h,
        low: l,
        close: c,
        volume: 900 + _rng.nextDouble() * 2600,
      ));
      p = c;
    }
    _price = _candles.last.close;
  }

  void _emit() {
    if (_regimeLeft-- <= 0) {
      _regimeLeft = 40 + _rng.nextInt(80);
      _drift = (_rng.nextDouble() - 0.5) * 0.16;
    }
    final shock = (_rng.nextDouble() - 0.5) * 0.85;
    _price = math.max(100, _price + _drift + shock);
    final t = DateTime.now();

    if (_candles.isEmpty) {
      _candles.add(Candle(time: t, open: _price, high: _price, low: _price, close: _price));
    } else {
      final last = _candles.last;
      final bucket = DateTime(t.year, t.month, t.day, t.hour, (t.minute ~/ 5) * 5);
      if (bucket.isAfter(last.time)) {
        _candles.add(Candle(time: bucket, open: _price, high: _price, low: _price, close: _price));
        if (_candles.length > 400) _candles.removeAt(0);
      } else {
        _candles[_candles.length - 1] = last.withTick(_price);
      }
    }

    _controller.add(Tick(
      price: _price,
      time: t,
      bid: _price - 0.12,
      ask: _price + 0.12,
      dayChangePct: _openDay == 0 ? 0 : (_price - _openDay) / _openDay * 100,
    ));
  }

  @override
  Stream<Tick> ticks() => _controller.stream;

  @override
  Future<List<Candle>> candles({String interval = '5m', int limit = 200}) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    return _candles.length <= limit ? List<Candle>.from(_candles) : _candles.sublist(_candles.length - limit);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}

// ---------------------------------------------------------------------------
// LIVE feed #1 — Yahoo Finance chart API (gold futures GC=F, no key required).
// ---------------------------------------------------------------------------
class YahooPriceRepository implements PriceRepository {
  YahooPriceRepository({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  final StreamController<Tick> _controller = StreamController<Tick>.broadcast();
  Timer? _timer;
  double _prevClose = 0;
  bool _healthy = false;

  @override
  String get label => 'Yahoo Finance · GC=F (delayed)';

  @override
  bool get isLive => _healthy;

  static const String _base = 'https://query1.finance.yahoo.com/v8/finance/chart/GC=F';

  @override
  Stream<Tick> ticks() {
    _timer ??= Timer.periodic(const Duration(seconds: 4), (_) => _poll());
    _poll();
    return _controller.stream;
  }

  Future<void> _poll() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        _base,
        queryParameters: <String, dynamic>{'interval': '1m', 'range': '1d'},
        options: Options(
          headers: webSafeUserAgent(),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      final meta = (res.data?['chart']?['result']?[0]?['meta']) as Map<String, dynamic>?;
      if (meta == null) return;
      final price = (meta['regularMarketPrice'] as num?)?.toDouble() ?? 0;
      _prevClose = (meta['chartPreviousClose'] as num?)?.toDouble() ?? _prevClose;
      if (price <= 0) return;
      _healthy = true;
      _controller.add(Tick(
        price: price,
        time: DateTime.now(),
        dayChangePct: _prevClose == 0 ? 0 : (price - _prevClose) / _prevClose * 100,
      ));
    } catch (_) {
      _healthy = false;
    }
  }

  @override
  Future<List<Candle>> candles({String interval = '5m', int limit = 200}) async {
    final yInterval = switch (interval) {
      '1m' => '1m',
      '5m' => '5m',
      '15m' => '15m',
      '30m' => '30m',
      '1h' => '60m',
      _ => '5m',
    };
    final range = switch (interval) {
      '1m' => '5d',
      '5m' => '1mo',
      '15m' => '1mo',
      '30m' => '3mo',
      '1h' => '6mo',
      _ => '1mo',
    };
    final res = await _dio.get<Map<String, dynamic>>(
      _base,
      queryParameters: <String, dynamic>{'interval': yInterval, 'range': range},
      options: Options(
        headers: webSafeUserAgent(),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    final result = res.data?['chart']?['result']?[0] as Map<String, dynamic>?;
    if (result == null) return <Candle>[];
    final ts = (result['timestamp'] as List<dynamic>?) ?? <dynamic>[];
    final quote = (result['indicators']?['quote']?[0]) as Map<String, dynamic>?;
    if (quote == null) return <Candle>[];
    final opens = quote['open'] as List<dynamic>?;
    final highs = quote['high'] as List<dynamic>?;
    final lows = quote['low'] as List<dynamic>?;
    final closes = quote['close'] as List<dynamic>?;
    final vols = quote['volume'] as List<dynamic>?;

    final out = <Candle>[];
    for (var i = 0; i < ts.length; i++) {
      final o = opens?[i], h = highs?[i], l = lows?[i], c = closes?[i];
      if (o is! num || h is! num || l is! num || c is! num) continue;
      out.add(Candle(
        time: DateTime.fromMillisecondsSinceEpoch(((ts[i] as num).toInt()) * 1000),
        open: o.toDouble(),
        high: h.toDouble(),
        low: l.toDouble(),
        close: c.toDouble(),
        volume: (vols?[i] is num) ? (vols![i] as num).toDouble() : 0,
      ));
    }
    if (out.isNotEmpty) _healthy = true;
    return out.length <= limit ? out : out.sublist(out.length - limit);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}

// ---------------------------------------------------------------------------
// LIVE feed #2 — Finnhub WebSocket (real tick data, free API key required).
// Candles are still taken from Yahoo so the chart always renders.
// ---------------------------------------------------------------------------
class FinnhubPriceRepository implements PriceRepository {
  FinnhubPriceRepository({required this.apiKey, Dio? dio})
      : _yahoo = YahooPriceRepository(dio: dio);

  final String apiKey;
  final YahooPriceRepository _yahoo;
  final StreamController<Tick> _controller = StreamController<Tick>.broadcast();
  WebSocketChannel? _channel;
  double _prev = 0;

  @override
  String get label => 'Finnhub WS · OANDA:XAU_USD';

  @override
  bool get isLive => _channel != null;

  @override
  Stream<Tick> ticks() {
    _connect();
    _yahoo.ticks().listen((t) {
      if (_channel == null) _controller.add(t);
    });
    return _controller.stream;
  }

  void _connect() {
    try {
      final ch = WebSocketChannel.connect(Uri.parse('wss://ws.finnhub.io?token=$apiKey'));
      _channel = ch;
      ch.sink.add('{"type":"subscribe","symbol":"OANDA:XAU_USD"}');
      ch.stream.listen(
        (dynamic msg) {
          try {
            final decoded = msg as dynamic;
            final String raw = decoded.toString();
            final match = RegExp(r'"p":([0-9.]+)').firstMatch(raw);
            if (match == null) return;
            final price = double.tryParse(match.group(1) ?? '');
            if (price == null || price <= 0) return;
            if (_prev == 0) _prev = price;
            _controller.add(Tick(
              price: price,
              time: DateTime.now(),
              bid: price - 0.12,
              ask: price + 0.12,
              dayChangePct: _prev == 0 ? 0 : (price - _prev) / _prev * 100,
            ));
          } catch (_) {}
        },
        onError: (_) => _channel = null,
        onDone: () => _channel = null,
      );
    } catch (_) {
      _channel = null;
    }
  }

  @override
  Future<List<Candle>> candles({String interval = '5m', int limit = 200}) =>
      _yahoo.candles(interval: interval, limit: limit);

  @override
  void dispose() {
    _channel?.sink.close();
    _yahoo.dispose();
    _controller.close();
  }
}
