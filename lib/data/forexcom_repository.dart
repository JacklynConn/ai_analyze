import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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
///  3. Candles: Yahoo Finance `GC=F` (same convention as the Finnhub feed in
///     this app). Futures can differ from the FOREX.com spot quote by a few
///     dollars — the live *price* shown in the header always comes from
///     FOREX.com; candles are only the chart backdrop.
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
        final silent = _lastTickAt == null ||
            DateTime.now().difference(_lastTickAt!) > const Duration(seconds: 8);
        if (silent && !_disposed) _pollScanner();
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

  /// TradingView frames look like `~m~<len>~m~<payload>` and several frames
  /// can arrive glued together. `~h~<n>` payloads are heartbeats that must
  /// be echoed back verbatim.
  void _onSocketData(dynamic data) {
    if (data is! String) return;
    for (final part in data.split(RegExp(r'~m~\d+~m~'))) {
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
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'https://scanner.tradingview.com/symbol',
        queryParameters: <String, dynamic>{
          'symbol': tvSymbol,
          'fields': 'close,bid,ask,open,high,low,change,change_abs,lp_time',
        },
        options: Options(
          headers: <String, dynamic>{'User-Agent': 'Mozilla/5.0'},
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
    if (!_disposed && !_controller.isClosed) _controller.add(tick);
  }

  // ---------------------------------------------------------------- candles
  @override
  Future<List<Candle>> candles({String interval = '5m', int limit = 200}) =>
      _yahoo.candles(interval: interval, limit: limit);

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
