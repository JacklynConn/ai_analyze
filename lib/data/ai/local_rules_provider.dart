import '../../core/config.dart';
import '../../models/signal.dart';
import 'ai_provider.dart';

/// Deterministic on-device "model". It never needs a key or network, so the
/// ensemble always has at least one voter. This is what keeps the app usable
/// when every cloud free-tier quota is exhausted.
class LocalRulesProvider implements AiProvider {
  const LocalRulesProvider();

  static const AiModelSpec _spec = AiModelSpec(
    backend: AiBackend.local,
    label: 'Rules Engine',
    model: 'ta-rules-v1',
    note: 'on-device',
  );

  @override
  AiModelSpec get spec => _spec;

  @override
  bool get isConfigured => true;

  @override
  Future<ModelVote> analyze(MarketContext ctx) async {
    final sw = Stopwatch()..start();
    final t = ctx.tech;
    final notes = <String>[
      ...t.notes.take(4),
      'News risk ${(ctx.newsRisk * 100).toStringAsFixed(0)}% (${ctx.newsBias.name})',
    ];

    if (t.price <= 0) {
      return ModelVote(
        modelId: spec.id,
        label: spec.label,
        action: TradeAction.noTrade,
        confidence: 0,
        rationale: 'No data.',
        latency: sw.elapsed,
      );
    }

    final TradeAction action;
    if (t.score >= 0.35 && ctx.newsRisk < 0.7) {
      action = TradeAction.buy;
    } else if (t.score <= -0.35 && ctx.newsRisk < 0.7) {
      action = TradeAction.sell;
    } else if (ctx.newsRisk >= 0.7) {
      action = TradeAction.noTrade;
    } else {
      action = TradeAction.wait;
    }

    final trendPart = (t.adx / 50).clamp(0.0, 1.0);
    final confidence = ((t.score.abs() * 0.6 + trendPart * 0.2 + 0.1) * (1 - ctx.newsRisk * 0.4))
        .clamp(0.0, 0.95);

    final rationale = '${t.ema21 > t.ema50 ? 'EMA stack bullish' : 'EMA stack bearish'}, '
        'RSI ${t.rsi.toStringAsFixed(1)}, MACD hist ${t.macdHist.toStringAsFixed(2)}, '
        'ADX ${t.adx.toStringAsFixed(1)} → score ${t.score.toStringAsFixed(2)}.';

    return ModelVote(
      modelId: spec.id,
      label: spec.label,
      action: action,
      confidence: action.isDirectional ? confidence : (1 - confidence).clamp(0.0, 1.0),
      rationale: rationale,
      risks: notes,
      latency: sw.elapsed,
    );
  }
}
