import 'dart:convert';

import '../../analysis/indicators.dart';
import '../../core/config.dart';
import '../../models/candle.dart';
import '../../models/news_item.dart';
import '../../models/signal.dart';
import '../../models/technical_snapshot.dart';

/// Everything a model needs to judge the market.
class MarketContext {
  final List<Candle> candles;
  final TechnicalSnapshot tech;
  final List<NewsItem> news;
  final List<EconomicEvent> events;
  final double newsRisk;
  final NewsBias newsBias;
  final String interval;

  const MarketContext({
    required this.candles,
    required this.tech,
    required this.news,
    required this.events,
    required this.newsRisk,
    required this.newsBias,
    this.interval = '5m',
  });

  String get systemPrompt => '''
You are a senior XAUUSD (spot gold) intraday trader and risk manager.
You receive a compact market snapshot: recent candles, computed indicators,
the latest macro/geopolitical headlines with sentiment, and the upcoming
economic calendar.

Rules:
- Judge only what the data shows. Never invent prices or events.
- Buying and selling are equally valid; being flat is a valid answer.
- If the data is contradictory, incomplete, or an event risk sits inside the
  next hour, answer WAIT or NO_TRADE instead of forcing a direction.
- Respect structure: do not recommend buying straight into resistance or
  selling straight into support.

Answer with STRICT JSON only, no markdown, exactly this schema:
{
  "action": "BUY" | "SELL" | "WAIT" | "NO_TRADE",
  "confidence": 0.0-1.0,
  "rationale": "<= 45 words, reference the actual data",
  "key_risks": ["short phrase", "short phrase"]
}''';

  String buildUserPrompt() {
    final recent = candles.length > 40 ? candles.sublist(candles.length - 40) : candles;
    final candleLines = recent
        .map((c) => '${c.time.toIso8601String().substring(5, 16)} O:${c.open.toStringAsFixed(2)} '
            'H:${c.high.toStringAsFixed(2)} L:${c.low.toStringAsFixed(2)} C:${c.close.toStringAsFixed(2)}')
        .join('\n');

    final newsLines = news
        .take(8)
        .map((n) => '- [${n.impact.name}/${n.bias.name}] ${n.title} (${n.source}, ${n.publishedAt.toIso8601String().substring(0, 16)})')
        .join('\n');

    final eventLines = events
        .where((e) => e.time.isAfter(DateTime.now()))
        .take(5)
        .map((e) => '- ${e.time.toIso8601String().substring(0, 16)} ${e.title} [${e.impact.name}]')
        .join('\n');

    final ind = tech;
    return '''
SYMBOL: XAUUSD
TIMEFRAME: $interval
LAST PRICE: ${ind.price.toStringAsFixed(2)}

INDICATORS
EMA9 ${ind.ema9.toStringAsFixed(2)} | EMA21 ${ind.ema21.toStringAsFixed(2)} | EMA50 ${ind.ema50.toStringAsFixed(2)} | EMA200 ${ind.ema200.toStringAsFixed(2)}
RSI14 ${ind.rsi.toStringAsFixed(1)} | MACD ${ind.macd.toStringAsFixed(2)} / signal ${ind.macdSignal.toStringAsFixed(2)} / hist ${ind.macdHist.toStringAsFixed(2)}
ATR14 ${ind.atr.toStringAsFixed(2)} | ADX14 ${ind.adx.toStringAsFixed(1)} | BB width ${ind.bbWidth.toStringAsFixed(2)}%
Support ${ind.support.toStringAsFixed(2)} | Resistance ${ind.resistance.toStringAsFixed(2)}
60-candle high ${ind.sessionHigh.toStringAsFixed(2)} | low ${ind.sessionLow.toStringAsFixed(2)}
Rule-engine score: ${ind.score.toStringAsFixed(2)} (-1 bearish .. +1 bullish)

RECENT CANDLES (oldest first)
$candleLines

NEWS (impact/bias)
$newsLines

UPCOMING US EVENTS
${eventLines.isEmpty ? '- none in calendar window' : eventLines}

NEWS RISK INDEX: ${(newsRisk * 100).toStringAsFixed(0)}% | NET NEWS BIAS: ${newsBias.name}

Decide: BUY, SELL, WAIT or NO_TRADE for the next 1-3 hours. JSON only.''';
  }

  /// Deterministic technical fallback used when no cloud model is available.
  static TechnicalSnapshot techFrom(List<Candle> candles) => Indicators.snapshot(candles);
}

abstract class AiProvider {
  AiModelSpec get spec;
  bool get isConfigured;
  Future<ModelVote> analyze(MarketContext ctx);
}

/// Extracts a JSON object from a model answer that may contain prose/fences.
Map<String, dynamic>? extractJson(String text) {
  var t = text.trim();
  if (t.startsWith('```')) {
    t = t.replaceAll(RegExp(r'^```[a-zA-Z]*'), '').replaceAll(RegExp(r'```$'), '').trim();
  }
  final start = t.indexOf('{');
  final end = t.lastIndexOf('}');
  if (start == -1 || end <= start) return null;
  final candidate = t.substring(start, end + 1);
  try {
    final decoded = jsonDecode(candidate);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

TradeAction actionFrom(String? raw) {
  switch ((raw ?? '').toUpperCase().replaceAll('-', '_').trim()) {
    case 'BUY':
    case 'LONG':
      return TradeAction.buy;
    case 'SELL':
    case 'SHORT':
      return TradeAction.sell;
    case 'WAIT':
      return TradeAction.wait;
    default:
      return TradeAction.noTrade;
  }
}

ModelVote voteFromJson({
  required AiModelSpec spec,
  required Map<String, dynamic> json,
  required Duration latency,
}) {
  final risks = (json['key_risks'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const <String>[];
  return ModelVote(
    modelId: spec.id,
    label: spec.label,
    action: actionFrom(json['action']?.toString()),
    confidence: ((json['confidence'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
    rationale: (json['rationale'] ?? '').toString(),
    risks: risks,
    latency: latency,
  );
}
