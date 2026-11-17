import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analysis/indicators.dart';
import '../analysis/news_impact.dart';
import '../analysis/signal_engine.dart';
import '../core/config.dart';
import '../data/ai/ai_provider.dart';
import '../data/ai/ai_router.dart';
import '../data/ai/gemini_provider.dart';
import '../data/ai/local_rules_provider.dart';
import '../data/ai/openai_compatible_provider.dart';
import '../data/forexcom_repository.dart';
import '../data/news_repository.dart';
import '../data/price_repository.dart';
import '../models/candle.dart';
import '../models/news_item.dart';
import '../models/signal.dart';
import '../models/technical_snapshot.dart';
import '../services/settings_service.dart';
import 'providers.dart';

@immutable
class DashboardState {
  final bool loading;
  final bool aiRunning;
  final String? error;
  final List<Candle> candles;
  final Tick? tick;
  final TechnicalSnapshot tech;
  final List<NewsItem> news;
  final List<EconomicEvent> events;
  final double newsRisk;
  final NewsBias newsBias;
  final AiAnalysis ai;
  final SignalEvaluation? evaluation;
  final TradeSignal? activeSignal;
  final List<TradeSignal> history;
  final bool feedLive;
  final bool newsLive;
  final String interval;
  final String feedLabel;
  final DateTime? updatedAt;
  final DateTime? aiUpdatedAt;
  final double balance;
  final double riskPercent;

  DashboardState({
    this.loading = true,
    this.aiRunning = false,
    this.error,
    this.candles = const <Candle>[],
    this.tick,
    this.tech = const TechnicalSnapshot(
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
    ),
    this.news = const <NewsItem>[],
    this.events = const <EconomicEvent>[],
    this.newsRisk = 0,
    this.newsBias = NewsBias.neutral,
    AiAnalysis? ai,
    this.evaluation,
    this.activeSignal,
    this.history = const <TradeSignal>[],
    this.feedLive = false,
    this.newsLive = false,
    this.interval = '5m',
    this.feedLabel = '—',
    this.updatedAt,
    this.aiUpdatedAt,
    this.balance = 1000,
    this.riskPercent = 1,
  }) : ai = ai ?? AiAnalysis.empty();

  double get price => tick?.price ?? (candles.isNotEmpty ? candles.last.close : tech.price);
  double get changePct => tick?.dayChangePct ?? 0;

  DashboardState copyWith({
    bool? loading,
    bool? aiRunning,
    String? error,
    bool clearError = false,
    List<Candle>? candles,
    Tick? tick,
    TechnicalSnapshot? tech,
    List<NewsItem>? news,
    List<EconomicEvent>? events,
    double? newsRisk,
    NewsBias? newsBias,
    AiAnalysis? ai,
    SignalEvaluation? evaluation,
    TradeSignal? activeSignal,
    bool clearSignal = false,
    List<TradeSignal>? history,
    bool? feedLive,
    bool? newsLive,
    String? interval,
    String? feedLabel,
    DateTime? updatedAt,
    DateTime? aiUpdatedAt,
    double? balance,
    double? riskPercent,
  }) =>
      DashboardState(
        loading: loading ?? this.loading,
        aiRunning: aiRunning ?? this.aiRunning,
        error: clearError ? null : (error ?? this.error),
        candles: candles ?? this.candles,
        tick: tick ?? this.tick,
        tech: tech ?? this.tech,
        news: news ?? this.news,
        events: events ?? this.events,
        newsRisk: newsRisk ?? this.newsRisk,
        newsBias: newsBias ?? this.newsBias,
        ai: ai ?? this.ai,
        evaluation: evaluation ?? this.evaluation,
        activeSignal: clearSignal ? null : (activeSignal ?? this.activeSignal),
        history: history ?? this.history,
        feedLive: feedLive ?? this.feedLive,
        newsLive: newsLive ?? this.newsLive,
        interval: interval ?? this.interval,
        feedLabel: feedLabel ?? this.feedLabel,
        updatedAt: updatedAt ?? this.updatedAt,
        aiUpdatedAt: aiUpdatedAt ?? this.aiUpdatedAt,
        balance: balance ?? this.balance,
        riskPercent: riskPercent ?? this.riskPercent,
      );
}

class DashboardController extends Notifier<DashboardState> {
  PriceRepository? _price;
  NewsRepository? _news;
  CalendarRepository? _calendar;
  StreamSubscription<Tick>? _sub;
  Timer? _tickTimer;
  Timer? _pollTimer;
  AppSettings _settings = const AppSettings();
  String? _lastAlertKey;
  DateTime? _lastAlertAt;
  bool _started = false;

  static const NewsImpactEngine _newsEngine = NewsImpactEngine();

  @override
  DashboardState build() {
    ref.onDispose(_teardown);
    Future<void>.microtask(() => start(ref.read(settingsProvider)));
    return DashboardState();
  }

  // --------------------------------------------------------------- lifecycle
  Future<void> start(AppSettings settings) async {
    _settings = settings;
    state = state.copyWith(balance: settings.balance, riskPercent: settings.riskPercent);
    _teardown();
    _buildRepositories();
    _started = true;
    await refreshAll(runAi: true);
    _sub = _price?.ticks().listen(_onTick);
    _pollTimer = Timer.periodic(TradingConfig.candleRefresh, (_) => refreshAll(runAi: false));
  }

  void applySettings(AppSettings settings) {
    final needsRebuild = _settings.demoMode != settings.demoMode ||
        _settings.finnhubKey != settings.finnhubKey ||
        _settings.interval != settings.interval ||
        _settings.geminiKey != settings.geminiKey ||
        _settings.groqKey != settings.groqKey ||
        _settings.openRouterKey != settings.openRouterKey ||
        !setEquals(_settings.disabledModels, settings.disabledModels);
    _settings = settings;
    if (!_started || needsRebuild) {
      start(settings);
    } else {
      // thresholds changed only — re-evaluate immediately
      _evaluateAndPublish();
    }
  }

  void _teardown() {
    _sub?.cancel();
    _sub = null;
    _tickTimer?.cancel();
    _pollTimer?.cancel();
    _price?.dispose();
    _price = null;
  }

  void _buildRepositories() {
    // Default live feed: FOREX.com XAUUSD (FOREXCOM:XAUUSD, realtime).
    // A Finnhub key, when set, still takes over as before.
    _price = _settings.demoMode
        ? MockPriceRepository()
        : (_settings.finnhubKey.trim().isNotEmpty
            ? FinnhubPriceRepository(apiKey: _settings.finnhubKey)
            : ForexComPriceRepository());
    _news = CompositeNewsRepository();
    _calendar = CompositeCalendarRepository();
  }

  // -------------------------------------------------------------- data pulls
  Future<void> refreshAll({bool runAi = true}) async {
    if (_price == null) return;
    // Each source fails independently: one blocked endpoint (e.g. a
    // CORS-rejected REST call in a browser, which Dio surfaces as a raw
    // XMLHttpRequest error) must not wipe out the candles/news/chart or
    // paint a scary error banner over a feed that is actually streaming.
    List<Candle>? candles;
    List<NewsItem>? news;
    List<EconomicEvent>? events;
    try {
      candles = await _price!.candles(interval: _settings.interval, limit: 240);
    } catch (_) {}
    try {
      news = await _news!.fetch(limit: 40);
    } catch (_) {}
    try {
      events = await _calendar!.fetch();
    } catch (_) {}

    final goodCandles =
        (candles != null && candles.isNotEmpty) ? candles : state.candles;
    final goodNews = (news != null && news.isNotEmpty) ? news : state.news;
    final agg = _newsEngine.aggregate(goodNews);
    final nothingWorks =
        goodCandles.isEmpty && state.tick == null;

    state = state.copyWith(
      loading: false,
      // Only surface an error when we truly have nothing to show; partial
      // failures keep last-good data and retry on the next 60 s poll.
      clearError: !nothingWorks,
      error: nothingWorks
          ? 'Live data is temporarily unavailable — retrying automatically…'
          : null,
      candles: goodCandles,
      news: goodNews,
      events: (events != null && events.isNotEmpty) ? events : state.events,
      newsRisk: agg.risk,
      newsBias: agg.bias,
      newsLive: _news!.isLive,
      feedLive: _price!.isLive,
      feedLabel: _price!.label,
      interval: _settings.interval,
      updatedAt: DateTime.now(),
    );

    _recomputeTech();
    _evaluateAndPublish();
    _maybeRemindEvent();

    final stale = state.aiUpdatedAt == null ||
        DateTime.now().difference(state.aiUpdatedAt!) > TradingConfig.aiRefresh;
    if (runAi || stale) await runAiAnalysis();
  }

  Future<void> runAiAnalysis() async {
    if (state.candles.length < 30) return;
    state = state.copyWith(aiRunning: true);
    try {
      final router = _buildRouter();
      final analysis = await router.analyze(MarketContext(
        candles: state.candles,
        tech: state.tech,
        news: state.news,
        events: state.events,
        newsRisk: state.newsRisk,
        newsBias: state.newsBias,
        interval: state.interval,
      ));
      state = state.copyWith(
        ai: analysis,
        aiRunning: false,
        aiUpdatedAt: DateTime.now(),
      );
      _evaluateAndPublish();
    } catch (e) {
      state = state.copyWith(aiRunning: false, error: 'AI error: $e');
    }
  }

  AiRouter _buildRouter() {
    final providers = <AiProvider>[];
    for (final spec in kAiModels) {
      if (_settings.disabledModels.contains(spec.id)) continue;
      if (!_settings.hasKey(spec.backend)) continue;
      switch (spec.backend) {
        case AiBackend.gemini:
          providers.add(GeminiProvider(apiKey: _settings.geminiKey, spec: spec));
        case AiBackend.groq:
          providers.add(GroqProvider(apiKey: _settings.groqKey, spec: spec));
        case AiBackend.openrouter:
          providers.add(OpenRouterProvider(apiKey: _settings.openRouterKey, spec: spec));
        case AiBackend.local:
          providers.add(const LocalRulesProvider());
      }
    }
    if (providers.isEmpty) providers.add(const LocalRulesProvider());
    return AiRouter(providers: providers);
  }

  // ------------------------------------------------------------------- ticks
  void _onTick(Tick tick) {
    var candles = state.candles;
    if (candles.isNotEmpty) {
      final updated = List<Candle>.from(candles);
      updated[updated.length - 1] = updated.last.withTick(tick.price);
      candles = updated;
    }
    state = state.copyWith(tick: tick, candles: candles, feedLive: _price?.isLive ?? false);
    _recomputeTech();
    _tickTimer?.cancel();
    _tickTimer = Timer(TradingConfig.tickRecompute, _evaluateAndPublish);
  }

  void _recomputeTech() {
    if (state.candles.length < 30) return;
    final tech = Indicators.snapshot(state.candles, livePrice: state.tick?.price);
    if (tech.price > 0) state = state.copyWith(tech: tech);
  }

  // ------------------------------------------------------------------ engine
  void _evaluateAndPublish() {
    if (state.candles.length < 30) return;
    final engine = ref.read(signalEngineProvider);
    final evaluation = engine.evaluate(
      price: state.price,
      tech: state.tech,
      ai: state.ai,
      newsRisk: state.newsRisk,
      newsBias: state.newsBias,
      events: state.events,
      now: DateTime.now(),
      spread: state.tick?.spread ?? 0,
      feedHealthy: state.price > 0,
    );

    TradeSignal? signal = state.activeSignal;

    if (evaluation.isConfirmed && evaluation.plan != null) {
      final dir = evaluation.action;
      final entry = evaluation.plan!.entry;
      final sameSetup = signal != null &&
          signal.state == SignalState.confirmed &&
          signal.action == dir &&
          (signal.plan!.entry - entry).abs() < state.tech.atr * 0.5 &&
          !signal.isExpired;
      if (!sameSetup) {
        signal = TradeSignal(
          id: '${dir.name}-${DateTime.now().millisecondsSinceEpoch}',
          action: dir,
          state: SignalState.confirmed,
          confidence: evaluation.confidence,
          createdAt: DateTime.now(),
          expiresAt: DateTime.now().add(TradingConfig.signalTtl),
          priceAtIssue: entry,
          plan: evaluation.plan,
          reasons: evaluation.reasons,
          blockers: evaluation.blockers,
          ai: state.ai,
          techScore: state.tech.score,
          newsBias: state.newsBias,
          newsRisk: state.newsRisk,
        );
        final history = <TradeSignal>[signal, ...state.history].take(30).toList();
        state = state.copyWith(activeSignal: signal, history: history);
        _maybeAlert(signal);
      }
    } else if (signal != null &&
        (signal.isExpired || signal.action != evaluation.action)) {
      final closed = signal.copyWith(state: SignalState.expired);
      signal = null;
      state = state.copyWith(
        activeSignal: closed,
        clearSignal: true,
        history: <TradeSignal>[closed, ...state.history.where((h) => h.id != closed.id)].take(30).toList(),
      );
    }

    state = state.copyWith(evaluation: evaluation);
  }

  void _maybeAlert(TradeSignal signal) {
    if (!_settings.notificationsEnabled) return;
    final key = '${signal.action.name}:${signal.plan?.entry.toStringAsFixed(1)}';
    final now = DateTime.now();
    if (key == _lastAlertKey && _lastAlertAt != null && now.difference(_lastAlertAt!).inMinutes < 15) {
      return;
    }
    _lastAlertKey = key;
    _lastAlertAt = now;
    ref.read(notificationServiceProvider).showSignal(
          signal,
          balance: _settings.balance,
          riskPercent: _settings.riskPercent,
        );
  }

  DateTime? _lastEventReminder;

  void _maybeRemindEvent() {
    if (!_settings.notificationsEnabled) return;
    final now = DateTime.now();
    if (_lastEventReminder != null && now.difference(_lastEventReminder!).inMinutes < 60) return;
    for (final e in state.events) {
      if (!e.isHighImpact) continue;
      final d = e.timeUntil(now);
      if (d.inMinutes > 0 && d.inMinutes <= 45) {
        _lastEventReminder = now;
        ref.read(notificationServiceProvider).showEventReminder(e, minutesBefore: d.inMinutes);
        break;
      }
    }
  }

  // ----------------------------------------------------------------- actions
  Future<void> manualRefresh() => refreshAll(runAi: true);

  Future<void> reanalyse() => runAiAnalysis();

  Future<void> setInterval(String interval) async {
    _settings = _settings.copyWith(interval: interval);
    state = state.copyWith(interval: interval, loading: true);
    await refreshAll(runAi: false);
  }
}
