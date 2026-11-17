import '../../models/signal.dart';
import 'ai_provider.dart';
import 'local_rules_provider.dart';

/// Runs every configured model in parallel and turns their answers into a
/// single consensus. This is the "AI council" the app shows to the user.
class AiRouter {
  AiRouter({required List<AiProvider> providers, this.timeout = const Duration(seconds: 35)})
      : _providers = providers.isEmpty
            ? <AiProvider>[const LocalRulesProvider()]
            : List<AiProvider>.unmodifiable(providers);

  final List<AiProvider> _providers;
  final Duration timeout;

  List<AiProvider> get providers => _providers;

  Future<AiAnalysis> analyze(MarketContext ctx) async {
    final results = await Future.wait(
      _providers.map((p) async {
        try {
          return await p.analyze(ctx).timeout(timeout);
        } catch (_) {
          return ModelVote(
            modelId: p.spec.id,
            label: p.spec.label,
            action: TradeAction.noTrade,
            confidence: 0,
            error: 'timeout',
          );
        }
      }),
    );

    final ok = results.where((v) => !v.failed).toList();
    if (ok.isEmpty) {
      return AiAnalysis(
        votes: results,
        consensus: TradeAction.noTrade,
        confidence: 0,
        agreement: 0,
        summary: 'Every AI model failed (quota / network). Falling back to rules engine only.',
        generatedAt: DateTime.now(),
        offline: true,
      );
    }

    var buyW = 0.0;
    var sellW = 0.0;
    var waitW = 0.0;
    var totalW = 0.0;
    for (final v in ok) {
      final w = 0.15 + v.confidence;
      totalW += w;
      switch (v.action) {
        case TradeAction.buy:
          buyW += w;
        case TradeAction.sell:
          sellW += w;
        case TradeAction.wait:
          waitW += w;
        case TradeAction.noTrade:
          waitW += w * 0.8;
      }
    }

    final TradeAction consensus;
    var winW = 0.0;
    if (buyW >= sellW && buyW >= waitW) {
      consensus = TradeAction.buy;
      winW = buyW;
    } else if (sellW >= buyW && sellW >= waitW) {
      consensus = TradeAction.sell;
      winW = sellW;
    } else {
      consensus = TradeAction.wait;
      winW = waitW;
    }

    final agreement = totalW == 0 ? 0.0 : (winW / totalW).clamp(0.0, 1.0);

    // Confidence = weighted average of the models that back the consensus,
    // damped by how divided the council is.
    final backers = ok.where((v) =>
        v.action == consensus ||
        (consensus == TradeAction.wait && (v.action == TradeAction.noTrade || v.action == TradeAction.wait)));
    final avgConf = backers.isEmpty
        ? 0.0
        : backers.map((v) => v.confidence).reduce((a, b) => a + b) / backers.length;
    final confidence = (avgConf * (0.55 + 0.45 * agreement)).clamp(0.0, 0.99);

    final directional = ok.where((v) => v.action.isDirectional).length;
    final risks = <String>{};
    for (final v in ok) {
      risks.addAll(v.risks.take(2));
    }

    final summary = StringBuffer()
      ..write('$directional/${ok.length} models recommend a trade; ')
      ..write('consensus ${consensus.label} with ${(confidence * 100).toStringAsFixed(0)}% confidence ')
      ..write('and ${(agreement * 100).toStringAsFixed(0)}% agreement.');

    return AiAnalysis(
      votes: results,
      consensus: consensus,
      confidence: confidence,
      agreement: agreement,
      summary: summary.toString(),
      keyRisks: risks.take(6).toList(),
      generatedAt: DateTime.now(),
      offline: ok.every((v) => v.modelId == LocalRulesProvider().spec.id),
    );
  }
}
