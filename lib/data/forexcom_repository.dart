import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/http_headers.dart';
import '../models/candle.dart';
import 'price_repository.dart';

/// LIVE feed — **FOREX.com XAUUSD** (`FOREXCOM:XAUUSD`).
///
/// FOREX.com (StoneX) does not offer a free public API — its own streaming
/// API requires a funded live account. The FOREX.com quote *is*, however,
/// published through TradingView under the symbol `FOREXCOM:XAUUSD`, so this
/// repository streams that exact symbol:
///
///  1. Primary: TradingView realtime WebSocket (quote session) — sub-second
///     ticks with bid / ask / session OHLC, no API key.
///  2. Fallback: TradingView scanner poll for the same symbol every 3 s,
///     used automatically while the socket is down / reconnecting.
///  3. Candles: the same FOREXCOM symbol via a TradingView chart session
///     (see [candles]), with CORS-friendly fallbacks. The live *price* shown
///     in the header always comes from FOREX.com ticks above.
class ForexComPriceRepository implements PriceRepository {
  ForexComPriceRepository({Dio? dio})
      : _dio = dio ?? Dio(),
        _yahoo = YahooPriceRepository(dio: dio);

  static const String tvSymbol = 'FOREXCOM:XAUUSD';

  final Dio _dio;
  final YahooPriceRepository _yahoo;
  final StreamController<Tick> _controller = StreamController<Tick>.broadcast();
  final math.Random _rng = math.Random();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _reconnectTimer;
  Timer? _fallbackTimer;
  DateTime? _lastTickAt;
  DateTime? _lastEnrichAt;
  DateTime? _lastConnectAt;
  bool _lastHadBidAsk = false;
  bool _disposed = false;
  bool _started = false;

  @override
  String get label => 'FOREX.com · $tvSymbol · realtime';

  @override
  bool get isLive =>
      _lastTickAt != null && DateTime.now().difference(_lastTickAt!) < const Duration(seconds: 20);

  // ------------------------------------------------------------- ticks API
  @override
  Stream<Tick> ticks() {
    if (!_started) {
      _started = true;
      _connect();
      // Poll the same FOREXCOM symbol whenever the socket has been silent.
      _fallbackTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (_disposed) return;
        final silentFor = _lastTickAt == null
            ? const Duration(days: 1)
            : DateTime.now().difference(_lastTickAt!);
        final silent = silentFor > const Duration(seconds: 8);
        // Some quote updates carry only the last price; top up bid/ask
        // from the scanner at most every 20 s so the quote card fills in.
        final needsBidAsk = !_lastHadBidAsk &&
            (_lastEnrichAt == null ||
                DateTime.now().difference(_lastEnrichAt!) > const Duration(seconds: 20));
        if (silent || needsBidAsk) _pollScanner();
        // Watchdog: on mobile networks a WebSocket often dies *silently*
        // (NAT timeout, network switch) — no error/done event ever fires,
        // so the price would freeze forever while the UI still looked
        // connected. Force a fresh socket if nothing arrived for 12 s.
        if (silentFor > const Duration(seconds: 12)) _forceReconnect();
      });
      _pollScanner();
    }
    return _controller.stream;
  }

  // ------------------------------------------------- TradingView WebSocket
  String _session(String prefix) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final suffix = List<String>.generate(12, (_) => chars[_rng.nextInt(chars.length)]).join();
    return '$prefix$suffix';
  }

  String _frame(Object payload) {
    final body = payload is String ? payload : jsonEncode(payload);
    return '~m~${body.length}~m~$body';
  }

  void _send(String method, List<dynamic> params) {
    try {
      _channel?.sink.add(_frame(<String, dynamic>{'m': method, 'p': params}));
    } catch (_) {
      // Socket is half-open; the reconnect logic will pick this up.
    }
  }

  void _connect() {
    if (_disposed) return;
    _lastConnectAt = DateTime.now();
    try {
      final ch = WebSocketChannel.connect(
        Uri.parse('wss://data.tradingview.com/socket.io/websocket'),
      );
      _channel = ch;
      final quoteSession = _session('qs_');

      _send('set_auth_token', <dynamic>['unauthorized_user_token']);
      _send('quote_create_session', <dynamic>[quoteSession]);
      _send('quote_set_fields', <dynamic>[
        quoteSession,
        'lp', 'lp_time', 'bid', 'ask', 'ch', 'chp',
        'open_price', 'high_price', 'low_price', 'prev_close_price',
        'volume', 'description', 'exchange', 'short_name',
      ]);
      _send('quote_add_symbols', <dynamic>[quoteSession, tvSymbol]);
      _send('quote_fast_symbols', <dynamic>[quoteSession, tvSymbol]);

      _wsSub = ch.stream.listen(
        _onSocketData,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _channel = null;
    _wsSub?.cancel();
    _wsSub = null;
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), _connect);
  }

  /// Tears the socket down *now* and reconnects immediately (throttled to
  /// one attempt per 10 s so a dead network doesn't spin in a tight loop).
  void _forceReconnect() {
    if (_disposed) return;
    if (_lastConnectAt != null &&
        DateTime.now().difference(_lastConnectAt!) < const Duration(seconds: 10)) {
      return;
    }
    _reconnectTimer?.cancel();
    final oldSub = _wsSub;
    final oldChannel = _channel;
    _wsSub = null;
    _channel = null;
    oldSub?.cancel();
    try {
      oldChannel?.sink.close();
    } catch (_) {}
    _connect();
  }

  /// TradingView frames look like `~m~<len>~m~<payload>` and several frames
  /// can arrive glued together. `~h~<n>` payloads are heartbeats that must
  /// be echoed back verbatim.
  /// Splits a raw socket message into individual TradingView payloads.
  static Iterable<String> payloadsOf(String data) =>
      data.split(RegExp(r'~m~\d+~m~')).where((p) => p.isNotEmpty);

  void _onSocketData(dynamic data) {
    if (data is! String) return;
    for (final part in payloadsOf(data)) {
      if (part.isEmpty) continue;
      if (part.startsWith('~h~')) {
        try {
          _channel?.sink.add(_frame(part));
        } catch (_) {}
        continue;
      }
      if (!part.startsWith('{')) continue;
      try {
        final decoded = jsonDecode(part) as Map<String, dynamic>;
        if (decoded['m'] == 'qsd') _handleQuote(decoded['p']);
      } catch (_) {
        // Partial / non-JSON frame — ignore, next tick is milliseconds away.
      }
    }
  }

  void _handleQuote(dynamic p) {
    if (p is! List || p.length < 2) return;
    final quote = p[1];
    if (quote is! Map<String, dynamic>) return;
    if (quote['n'] != null && quote['n'] != tvSymbol) return;
    final v = quote['v'];
    if (v is! Map) return;

    double? num_(String key) {
      final raw = v[key];
      return raw is num ? raw.toDouble() : null;
    }

    final bid = num_('bid');
    final ask = num_('ask');
    final price = num_('lp') ??
        ((bid != null && ask != null) ? (bid + ask) / 2 : null);
    if (price == null || price <= 0) return;

    final lpTime = num_('lp_time');
    _emit(Tick(
      price: price,
      time: lpTime != null && lpTime > 0
          ? DateTime.fromMillisecondsSinceEpoch((lpTime * 1000).toInt())
          : DateTime.now(),
      bid: bid,
      ask: ask,
      dayChangePct: num_('chp') ?? 0,
      dayOpen: num_('open_price'),
      dayHigh: num_('high_price'),
      dayLow: num_('low_price'),
    ));
  }

  // ------------------------------------------------- scanner poll fallback
  Future<void> _pollScanner() async {
    _lastEnrichAt = DateTime.now();
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'https://scanner.tradingview.com/symbol',
        queryParameters: <String, dynamic>{
          'symbol': tvSymbol,
          'fields': 'close,bid,ask,open,high,low,change,change_abs,lp_time',
        },
        options: Options(
          headers: webSafeUserAgent(),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final d = res.data;
      if (d == null) return;
      double? num_(String key) {
        final raw = d[key];
        return raw is num ? raw.toDouble() : null;
      }

      final bid = num_('bid');
      final ask = num_('ask');
      final price = num_('close') ??
          ((bid != null && ask != null) ? (bid + ask) / 2 : null);
      if (price == null || price <= 0) return;

      // Scanner `change` is already a percent; fall back to change_abs math.
      var pct = num_('change') ?? 0;
      final abs = num_('change_abs');
      if (pct == 0 && abs != null && price - abs != 0) {
        pct = abs / (price - abs) * 100;
      }
      final lpTime = num_('lp_time');
      _emit(Tick(
        price: price,
        time: lpTime != null && lpTime > 0
            ? DateTime.fromMillisecondsSinceEpoch((lpTime * 1000).toInt())
            : DateTime.now(),
        bid: bid,
        ask: ask,
        dayChangePct: pct,
        dayOpen: num_('open'),
        dayHigh: num_('high'),
        dayLow: num_('low'),
      ));
    } catch (_) {
      // Offline / blocked — the WebSocket (or the next poll) will recover.
    }
  }

  void _emit(Tick tick) {
    _lastTickAt = DateTime.now();
    _lastHadBidAsk = tick.bid != null && tick.ask != null;
    if (!_disposed && !_controller.isClosed) _controller.add(tick);
  }

  // ---------------------------------------------------------------- candles
  /// Candles come from the *same* FOREXCOM:XAUUSD symbol over a TradingView
  /// chart session (WebSocket — no CORS problem in browsers, unlike the
  /// Yahoo REST endpoint, which rejects cross-origin calls and caused the
  /// "DioException [connection error] / XMLHttpRequest onError" banner on
  /// web). Fallbacks, in order: Binance Vision PAXGUSDT klines (gold-backed,
  /// CORS-enabled public API), then Yahoo GC=F (native only in practice).
  @override
  Future<List<Candle>> candles({String interval = '5m', int limit = 200}) async {
    try {
      final tv = await _tvCandles(interval: interval, limit: limit);
      if (tv.isNotEmpty) return tv;
    } catch (_) {}
    try {
      final paxg = await _paxgCandles(interval: interval, limit: limit);
      if (paxg.isNotEmpty) return paxg;
    } catch (_) {}
    try {
      return await _yahoo.candles(interval: interval, limit: limit);
    } catch (_) {
      return <Candle>[];
    }
  }

  Future<List<Candle>> _tvCandles({required String interval, required int limit}) async {
    const timeframes = <String, String>{
      '1m': '1', '5m': '5', '15m': '15', '30m': '30', '1h': '60',
    };
    final timeframe = timeframes[interval] ?? '5';
    final chartSession = _session('cs_');
    final byTime = <int, Candle>{};
    final done = Completer<void>();
    WebSocketChannel? ch;
    StreamSubscription<dynamic>? sub;

    try {
      ch = WebSocketChannel.connect(
        Uri.parse('wss://data.tradingview.com/socket.io/websocket'),
      );
      void send(String m, List<dynamic> p) {
        try {
          ch?.sink.add(_frame(<String, dynamic>{'m': m, 'p': p}));
        } catch (_) {}
      }

      sub = ch.stream.listen(
        (dynamic data) {
          if (data is! String) return;
          for (final part in payloadsOf(data)) {
            if (part.startsWith('~h~')) {
              try {
                ch?.sink.add(_frame(part));
              } catch (_) {}
              continue;
            }
            if (!part.startsWith('{')) continue;
            try {
              final decoded = jsonDecode(part) as Map<String, dynamic>;
              if (decoded['m'] == 'timescale_update') {
                _parseTimescale(decoded['p'], byTime);
              } else if (decoded['m'] == 'series_completed' && !done.isCompleted) {
                done.complete();
              }
            } catch (_) {}
          }
        },
        onError: (_) {
          if (!done.isCompleted) done.complete();
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );

      send('set_auth_token', <dynamic>['unauthorized_user_token']);
      send('chart_create_session', <dynamic>[chartSession, '']);
      send('resolve_symbol', <dynamic>[
        chartSession,
        'symbol_1',
        '={"symbol":"$tvSymbol","adjustment":"splits","session":"extended"}',
      ]);
      send('create_series', <dynamic>[
        chartSession, 'ser_1', 's1', 'symbol_1', timeframe, limit,
      ]);

      await done.future.timeout(const Duration(seconds: 15), onTimeout: () {});
    } finally {
      await sub?.cancel();
      try {
        await ch?.sink.close();
      } catch (_) {}
    }

    final out = byTime.values.toList()..sort((a, b) => a.time.compareTo(b.time));
    return out.length <= limit ? out : out.sublist(out.length - limit);
  }

  void _parseTimescale(dynamic p, Map<int, Candle> byTime) {
    if (p is! List || p.length < 2 || p[1] is! Map) return;
    for (final series in (p[1] as Map).values) {
      if (series is! Map) continue;
      final bars = series['s'];
      if (bars is! List) continue;
      for (final bar in bars) {
        if (bar is! Map) continue;
        final v = bar['v'];
        if (v is! List || v.length < 5) continue;
        if (v[0] is! num || v[1] is! num || v[2] is! num || v[3] is! num || v[4] is! num) continue;
        final t = (v[0] as num).toInt();
        byTime[t] = Candle(
          time: DateTime.fromMillisecondsSinceEpoch(t * 1000),
          open: (v[1] as num).toDouble(),
          high: (v[2] as num).toDouble(),
          low: (v[3] as num).toDouble(),
          close: (v[4] as num).toDouble(),
          volume: v.length > 5 && v[5] is num ? (v[5] as num).toDouble() : 0,
        );
      }
    }
  }

  /// Gold-backed PAXG/USDT klines from Binance's public, CORS-enabled data
  /// mirror — web-friendly chart backdrop that tracks spot gold closely.
  Future<List<Candle>> _paxgCandles({required String interval, required int limit}) async {
    const intervals = <String>{'1m', '5m', '15m', '30m', '1h'};
    final res = await _dio.get<List<dynamic>>(
      'https://data-api.binance.vision/api/v3/klines',
      queryParameters: <String, dynamic>{
        'symbol': 'PAXGUSDT',
        'interval': intervals.contains(interval) ? interval : '5m',
        'limit': limit,
      },
      options: Options(receiveTimeout: const Duration(seconds: 12)),
    );
    final rows = res.data ?? <dynamic>[];
    final out = <Candle>[];
    for (final row in rows) {
      if (row is! List || row.length < 6) continue;
      final t = row[0];
      final o = double.tryParse('${row[1]}');
      final h = double.tryParse('${row[2]}');
      final l = double.tryParse('${row[3]}');
      final c = double.tryParse('${row[4]}');
      if (t is! num || o == null || h == null || l == null || c == null) continue;
      out.add(Candle(
        time: DateTime.fromMillisecondsSinceEpoch(t.toInt()),
        open: o, high: h, low: l, close: c,
        volume: double.tryParse('${row[5]}') ?? 0,
      ));
    }
    return out;
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _fallbackTimer?.cancel();
    _wsSub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _yahoo.dispose();
    _controller.close();
  }
}
