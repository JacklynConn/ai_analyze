import 'package:intl/intl.dart';

import '../core/config.dart';
import '../models/news_item.dart';
import '../models/signal.dart';
import '../models/technical_snapshot.dart';

/// One line of the "confirmation checklist" shown in the UI.
class SignalCheck {
  final String label;
  final bool passed;
  final bool blocking;
  final String detail;

  const SignalCheck({
    required this.label,
    required this.passed,
    required this.detail,
    this.blocking = true,
  });
}

class SignalEvaluation {
  final TradeAction action;
  final double confidence;
  final TradePlan? plan;
  final List<SignalCheck> checks;
  final List<String> reasons;
  final List<String> blockers;

  const SignalEvaluation({
    required this.action,
    required this.confidence,
    this.plan,
    this.checks = const <SignalCheck>[],
    this.reasons = const <String>[],
    this.blockers = const <String>[],
  });

  bool get isConfirmed => action.isDirectional;

  int get passedCount => checks.where((c) => c.passed).length;
  int get totalChecks => checks.length;
}

/// The heart of the app: turns technicals + AI consensus + news risk into a
/// single verdict.
///
/// Design rule (what the user asked for):
/// **If anything is unclear we return WAIT / NO TRADE instead of a signal.**
/// A trade is only published when EVERY hard gate passes.
class SignalEngine {
  final double minConfidence;
  final int blackoutMinutes;

  const SignalEngine({
    this.minConfidence = TradingConfig.minConfirmConfidence,
    this.blackoutMinutes = TradingConfig.defaultNewsBlackoutMinutes,
  });

  SignalEvaluation evaluate({
    required double price,
    required TechnicalSnapshot tech,
    required AiAnalysis ai,
    required double newsRisk,
    required NewsBias newsBias,
    required List<EconomicEvent> events,
    required DateTime now,
    double spread = 0,
    bool feedHealthy = true,
  }) {
    final checks = <SignalCheck>[];
    final reasons = <String>[];
    final blockers = <String>[];

    void block(String label, String detail) {
      checks.add(SignalCheck(label: label, passed: false, detail: detail));
      blockers.add('$label — $detail');
    }

    void pass(String label, String detail) {
      checks.add(SignalCheck(label: label, passed: true, detail: detail));
      reasons.add('$label — $detail');
    }

    void note(String label, String detail) {
      checks.add(SignalCheck(label: label, passed: true, detail: detail, blocking: false));
    }

    // ---------------------------------------------------------------- data
    if (!feedHealthy || price <= 0) {
      block('Price feed', 'Live quote unavailable, cannot judge entry');
      return SignalEvaluation(
        action: TradeAction.noTrade,
        confidence: 0,
        checks: checks,
        reasons: reasons,
        blockers: blockers,
      );
    }
    pass('Price feed', 'Live quote \$${price.toStringAsFixed(2)}');

    // ---------------------------------------------------------- high impact
    EconomicEvent? nextEvent;
    for (final e in events) {
      if (!e.isHighImpact) continue;
      final d = e.timeUntil(now);
      if (d.inMinutes.abs() <= blackoutMinutes) {
        nextEvent = e;
        break;
      }
    }
    if (nextEvent != null) {
      final d = nextEvent.timeUntil(now);
      final when = d.isNegative
          ? '${DateFormat('HH:mm').format(nextEvent.time)} already released'
          : 'in ${d.inMinutes}m (${DateFormat('HH:mm').format(nextEvent.time)})';
      block('High-impact news window', '${nextEvent.title} $when — spread may blow out');
    } else {
      final upcoming = events.where((e) => e.isHighImpact && e.time.isAfter(now)).toList()..sort((a, b) => a.time.compareTo(b.time));
      pass('High-impact news window',
          upcoming.isEmpty ? 'No high-impact releases found' : 'Next: ${upcoming.first.title} at ${DateFormat('HH:mm').format(upcoming.first.time)}');
    }

    // ------------------------------------------------------------- trend
    if (tech.adx < 18) {
      block('Trend strength', 'ADX ${tech.adx.toStringAsFixed(1)} — market is ranging, breakout traps likely');
    } else {
      pass('Trend strength', 'ADX ${tech.adx.toStringAsFixed(1)} — directional market');
    }

    // -------------------------------------------------- technical direction
    final techDir = tech.score >= 0.35 ? 1 : (tech.score <= -0.35 ? -1 : 0);
    if (techDir == 0) {
      block('Technical bias', 'Score ${tech.score.toStringAsFixed(2)} is neutral — no edge');
    } else {
      pass('Technical bias',
          '${techDir > 0 ? 'Bullish' : 'Bearish'} structure, score ${tech.score.toStringAsFixed(2)}');
    }

    // ------------------------------------------------------- AI consensus
    if (ai.modelsUsed == 0) {
      block('AI ensemble', 'No AI model responded — waiting for a fresh analysis');
    } else if (!ai.consensus.isDirectional) {
      block('AI ensemble', '${ai.modelsUsed} models → ${ai.consensus.label} (AI is not convinced yet)');
    } else if (ai.agreement < 0.6) {
      block('AI agreement', '${(ai.agreement * 100).toStringAsFixed(0)}% of models agree — too split');
    } else if (ai.confidence < minConfidence) {
      block('AI confidence',
          '${(ai.confidence * 100).toStringAsFixed(0)}% < required ${(minConfidence * 100).toStringAsFixed(0)}%');
    } else {
      pass('AI ensemble',
          '${ai.modelsUsed} models, ${(ai.agreement * 100).toStringAsFixed(0)}% agree ${ai.consensus.label} @ ${(ai.confidence * 100).toStringAsFixed(0)}%');
    }

    // --------------------------------------------------- AI vs technicals
    if (techDir != 0 && ai.consensus.isDirectional) {
      if (techDir == ai.consensus.dir.toInt()) {
        pass('AI ↔ technicals', 'Both point ${techDir > 0 ? 'up' : 'down'}');
      } else {
        block('AI ↔ technicals', 'AI says ${ai.consensus.label} but structure says ${techDir > 0 ? 'BUY' : 'SELL'}');
      }
    }

    // -------------------------------------------------------- news filter
    final biasAgainst = (newsBias == NewsBias.bullish && techDir < 0) ||
        (newsBias == NewsBias.bearish && techDir > 0);
    if (newsRisk > 0.55 && biasAgainst) {
      block('News flow', 'Headlines lean ${newsBias.name} against the setup (risk ${(newsRisk * 100).toStringAsFixed(0)}%)');
    } else if (newsRisk > 0.75) {
      block('News flow', 'Very heavy news tape (risk ${(newsRisk * 100).toStringAsFixed(0)}%) — wait for calm');
    } else {
      pass('News flow', 'No contradicting catalyst (risk ${(newsRisk * 100).toStringAsFixed(0)}%)');
    }

    // -------------------------------------------------------- room to run
    if (techDir > 0 && tech.distanceToResistanceAtr < 0.8) {
      block('Target room', 'Resistance ${tech.resistance.toStringAsFixed(2)} is only '
          '${tech.distanceToResistanceAtr.toStringAsFixed(2)} ATR away');
    } else if (techDir < 0 && tech.distanceToSupportAtr < 0.8) {
      block('Target room', 'Support ${tech.support.toStringAsFixed(2)} is only '
          '${tech.distanceToSupportAtr.toStringAsFixed(2)} ATR away');
    } else if (techDir != 0) {
      pass('Target room', '${(techDir > 0 ? tech.distanceToResistanceAtr : tech.distanceToSupportAtr).toStringAsFixed(2)} ATR to next level');
    }

    // ------------------------------------------------------------- spread
    if (tech.atr > 0 && spread > tech.atr * 0.25) {
      block('Spread', 'Spread ${spread.toStringAsFixed(2)} is wide vs ATR ${tech.atr.toStringAsFixed(2)}');
    } else {
      note('Spread', spread <= 0 ? 'Feed provides no spread' : spread.toStringAsFixed(2));
    }

    // ------------------------------------------------ volatility sanity
    if (tech.atr <= 0) {
      block('Volatility', 'ATR unavailable');
    } else if (tech.atr > price * 0.02) {
      block('Volatility', 'ATR \$${tech.atr.toStringAsFixed(2)} is extreme vs price');
    } else {
      note('Volatility', 'ATR \$${tech.atr.toStringAsFixed(2)}');
    }

    // ------------------------------------------------ RSI exhaustion guard
    if (techDir > 0 && tech.rsi > 76) {
      block('Momentum', 'RSI ${tech.rsi.toStringAsFixed(1)} — overbought, buying here is late');
    } else if (techDir < 0 && tech.rsi < 24) {
      block('Momentum', 'RSI ${tech.rsi.toStringAsFixed(1)} — oversold, selling here is late');
    } else if (techDir != 0) {
      pass('Momentum', 'RSI ${tech.rsi.toStringAsFixed(1)} has room to extend');
    }

    final hardBlockers = checks.where((c) => c.blocking && !c.passed).toList();

    // ------------------------------------------------------------- verdict
    if (hardBlockers.isNotEmpty) {
      final onlySoft =
          hardBlockers.every((b) => b.label == 'Technical bias' || b.label == 'AI ensemble' || b.label == 'AI confidence' || b.label == 'AI agreement');
      return SignalEvaluation(
        action: onlySoft ? TradeAction.wait : TradeAction.noTrade,
        confidence: _confidence(tech.score, ai, newsRisk),
        checks: checks,
        reasons: reasons,
        blockers: blockers,
      );
    }

    final dir = techDir > 0 ? TradeAction.buy : TradeAction.sell;
    final confidence = _confidence(tech.score, ai, newsRisk);
    final plan = _buildPlan(direction: dir, price: price, tech: tech);

    return SignalEvaluation(
      action: dir,
      confidence: confidence,
      plan: plan,
      checks: checks,
      reasons: reasons,
      blockers: blockers,
    );
  }

  double _confidence(double techScore, AiAnalysis ai, double newsRisk) {
    final techPart = techScore.abs().clamp(0.0, 1.0);
    final aiPart = ai.confidence.clamp(0.0, 1.0);
    final agreementPart = ai.agreement.clamp(0.0, 1.0);
    final raw = techPart * 0.35 + aiPart * 0.45 + agreementPart * 0.20;
    return (raw * (1 - newsRisk * 0.25)).clamp(0.0, 0.99);
  }

  TradePlan _buildPlan({
    required TradeAction direction,
    required double price,
    required TechnicalSnapshot tech,
  }) {
    final atr = tech.atr > 0 ? tech.atr : price * 0.002;
    final isBuy = direction == TradeAction.buy;

    // Stop goes beyond the structure level, but never tighter than 1.1 ATR.
    final structuralStop = isBuy ? tech.support - atr * 0.25 : tech.resistance + atr * 0.25;
    final atrStop = isBuy ? price - atr * 1.4 : price + atr * 1.4;
    final sl = isBuy
        ? (structuralStop < atrStop ? structuralStop : atrStop)
        : (structuralStop > atrStop ? structuralStop : atrStop);

    final risk = (price - sl).abs();
    final tp1 = isBuy ? price + risk * 1.5 : price - risk * 1.5;
    final tp2 = isBuy ? price + risk * 2.5 : price - risk * 2.5;

    return TradePlan(
      entry: double.parse(price.toStringAsFixed(2)),
      stopLoss: double.parse(sl.toStringAsFixed(2)),
      takeProfit1: double.parse(tp1.toStringAsFixed(2)),
      takeProfit2: double.parse(tp2.toStringAsFixed(2)),
      atr: double.parse(atr.toStringAsFixed(2)),
      riskReward: risk == 0 ? 0 : 1.5,
    );
  }
}
