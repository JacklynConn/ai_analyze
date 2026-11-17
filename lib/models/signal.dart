import 'news_item.dart';

/// What the engine recommends right now.
enum TradeAction { buy, sell, wait, noTrade }

/// Life-cycle of a published signal.
enum SignalState { forming, confirmed, invalidated, expired }

extension TradeActionX on TradeAction {
  String get label {
    switch (this) {
      case TradeAction.buy:
        return 'BUY';
      case TradeAction.sell:
        return 'SELL';
      case TradeAction.wait:
        return 'WAIT';
      case TradeAction.noTrade:
        return 'NO TRADE';
    }
  }

  bool get isDirectional => this == TradeAction.buy || this == TradeAction.sell;

  double get dir => this == TradeAction.buy ? 1 : (this == TradeAction.sell ? -1 : 0);
}

/// One AI model's opinion.
class ModelVote {
  final String modelId;
  final String label;
  final TradeAction action;
  final double confidence; // 0..1
  final String rationale;
  final List<String> risks;
  final Duration latency;
  final bool fromCache;
  final String? error;

  const ModelVote({
    required this.modelId,
    required this.label,
    required this.action,
    required this.confidence,
    this.rationale = '',
    this.risks = const <String>[],
    this.latency = Duration.zero,
    this.fromCache = false,
    this.error,
  });

  bool get failed => error != null;
}

/// Consensus produced by the AI router (all free models voting together).
class AiAnalysis {
  final List<ModelVote> votes;
  final TradeAction consensus;
  final double confidence; // weighted 0..1
  final double agreement; // share of models agreeing with consensus
  final String summary;
  final List<String> keyRisks;
  final DateTime generatedAt;
  final bool offline;

  const AiAnalysis({
    required this.votes,
    required this.consensus,
    required this.confidence,
    required this.agreement,
    required this.summary,
    this.keyRisks = const <String>[],
    required this.generatedAt,
    this.offline = false,
  });

  static AiAnalysis empty() => AiAnalysis(
        votes: const <ModelVote>[],
        consensus: TradeAction.wait,
        confidence: 0,
        agreement: 0,
        summary: 'No AI analysis yet. Tap "Re-analyse" to run the ensemble.',
        generatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        offline: true,
      );

  int get modelsUsed => votes.where((v) => !v.failed).length;
}

/// Trade plan derived from ATR + structure, not guessed by the LLM.
class TradePlan {
  final double entry;
  final double stopLoss;
  final double takeProfit1;
  final double takeProfit2;
  final double atr;
  final double riskReward;

  const TradePlan({
    required this.entry,
    required this.stopLoss,
    required this.takeProfit1,
    required this.takeProfit2,
    required this.atr,
    required this.riskReward,
  });

  double get slDistance => (entry - stopLoss).abs();

  /// Position size for a given account balance / risk percentage.
  double lotsFor({required double balance, required double riskPercent}) {
    if (slDistance <= 0) return 0;
    final riskUsd = balance * riskPercent / 100;
    // XAUUSD: 1 standard lot = 100 oz -> 1.00 move = 100 USD per lot.
    return riskUsd / (slDistance * 100);
  }
}

/// The final, user-facing output of the engine.
class TradeSignal {
  final String id;
  final TradeAction action;
  final SignalState state;
  final double confidence;
  final DateTime createdAt;
  final DateTime expiresAt;
  final double priceAtIssue;
  final TradePlan? plan;
  final List<String> reasons;
  final List<String> blockers;
  final AiAnalysis ai;
  final double techScore; // -1..1
  final NewsBias newsBias;
  final double newsRisk; // 0..1 (probability that news overrides TA)

  const TradeSignal({
    required this.id,
    required this.action,
    required this.state,
    required this.confidence,
    required this.createdAt,
    required this.expiresAt,
    required this.priceAtIssue,
    this.plan,
    this.reasons = const <String>[],
    this.blockers = const <String>[],
    required this.ai,
    this.techScore = 0,
    this.newsBias = NewsBias.neutral,
    this.newsRisk = 0,
  });

  bool get isConfirmed => state == SignalState.confirmed;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  TradeSignal copyWith({SignalState? state}) => TradeSignal(
        id: id,
        action: action,
        state: state ?? this.state,
        confidence: confidence,
        createdAt: createdAt,
        expiresAt: expiresAt,
        priceAtIssue: priceAtIssue,
        plan: plan,
        reasons: reasons,
        blockers: blockers,
        ai: ai,
        techScore: techScore,
        newsBias: newsBias,
        newsRisk: newsRisk,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'action': action.name,
        'state': state.name,
        'confidence': confidence,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
        'priceAtIssue': priceAtIssue,
        'reasons': reasons,
        'blockers': blockers,
        'techScore': techScore,
        'newsBias': newsBias.name,
        'newsRisk': newsRisk,
        'plan': plan == null
            ? null
            : <String, dynamic>{
                'entry': plan!.entry,
                'sl': plan!.stopLoss,
                'tp1': plan!.takeProfit1,
                'tp2': plan!.takeProfit2,
                'atr': plan!.atr,
                'rr': plan!.riskReward,
              },
      };

  static TradeSignal? fromJson(Map<String, dynamic> j) {
    final plan = j['plan'] as Map<String, dynamic>?;
    return TradeSignal(
      id: j['id'] as String? ?? '',
      action: TradeAction.values.firstWhere(
        (e) => e.name == j['action'],
        orElse: () => TradeAction.wait,
      ),
      state: SignalState.values.firstWhere(
        (e) => e.name == j['state'],
        orElse: () => SignalState.expired,
      ),
      confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch((j['createdAt'] as num?)?.toInt() ?? 0),
      expiresAt: DateTime.fromMillisecondsSinceEpoch((j['expiresAt'] as num?)?.toInt() ?? 0),
      priceAtIssue: (j['priceAtIssue'] as num?)?.toDouble() ?? 0,
      reasons: (j['reasons'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const <String>[],
      blockers: (j['blockers'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const <String>[],
      techScore: (j['techScore'] as num?)?.toDouble() ?? 0,
      newsBias: NewsBias.values.firstWhere(
        (e) => e.name == j['newsBias'],
        orElse: () => NewsBias.neutral,
      ),
      newsRisk: (j['newsRisk'] as num?)?.toDouble() ?? 0,
      plan: plan == null
          ? null
          : TradePlan(
              entry: (plan['entry'] as num).toDouble(),
              stopLoss: (plan['sl'] as num).toDouble(),
              takeProfit1: (plan['tp1'] as num).toDouble(),
              takeProfit2: (plan['tp2'] as num).toDouble(),
              atr: (plan['atr'] as num).toDouble(),
              riskReward: (plan['rr'] as num).toDouble(),
            ),
      ai: AiAnalysis.empty(),
    );
  }
}
