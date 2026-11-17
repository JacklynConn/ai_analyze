import 'package:material_ui/material_ui.dart';
import '../../analysis/signal_engine.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/news_item.dart';
import '../../models/signal.dart';
import '../../state/dashboard_controller.dart';
import 'common.dart';
import 'confidence_gauge.dart';

Color actionColor(TradeAction a) {
  switch (a) {
    case TradeAction.buy:
      return AppColors.buy;
    case TradeAction.sell:
      return AppColors.sell;
    default:
      return AppColors.wait;
  }
}

IconData actionIcon(TradeAction a) {
  switch (a) {
    case TradeAction.buy:
      return Icons.trending_up_rounded;
    case TradeAction.sell:
      return Icons.trending_down_rounded;
    case TradeAction.wait:
      return Icons.hourglass_empty_rounded;
    case TradeAction.noTrade:
      return Icons.block_rounded;
  }
}

class SignalCard extends StatelessWidget {
  const SignalCard({
    super.key,
    required this.state,
    required this.evaluation,
    this.onReanalyse,
    this.onOpenChart,
    this.compact = false,
  });

  final DashboardState state;
  final SignalEvaluation? evaluation;
  final VoidCallback? onReanalyse;
  final VoidCallback? onOpenChart;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ev = evaluation;
    final action = ev?.action ?? TradeAction.wait;
    final color = actionColor(action);
    final confirmed = action.isDirectional;
    final signal = state.activeSignal;
    final plan = ev?.plan;

    final checks = ev?.checks ?? const <SignalCheck>[];
    final failing = checks.where((c) => c.blocking && !c.passed).toList();
    final passing = checks.where((c) => c.blocking && c.passed).toList();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[color.withValues(alpha: .16), AppColors.surface],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ----------------------------------------------------- header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: .18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(actionIcon(action), color: color, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          action.label,
                          style: TextStyle(
                            color: color,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .5,
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (confirmed)
                          Pill(
                            label: signal?.isExpired == false
                                ? 'CONFIRMED · ${fmtCountdown(signal!.expiresAt.difference(DateTime.now()))}'
                                : 'CONFIRMED',
                            color: color,
                            dense: true,
                            filled: true,
                          )
                        else
                          Pill(label: 'NOT CONFIRMED', color: AppColors.wait, dense: true),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _verdictLine(action, failing, passing, state),
                      style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConfidenceGauge(
                value: ev?.confidence ?? 0,
                color: color,
                size: 84,
                threshold: 0.66,
              ),
            ],
          ),

          if (compact) const SizedBox(height: 12),

          // ------------------------------------------------------ plan grid
          if (plan != null) ...<Widget>[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bg.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      _PlanCell(label: 'ENTRY', value: fmtPrice(plan.entry), color: AppColors.text),
                      _PlanCell(label: 'STOP LOSS', value: fmtPrice(plan.stopLoss), color: AppColors.sell),
                      _PlanCell(label: 'TP1', value: fmtPrice(plan.takeProfit1), color: AppColors.buy),
                      _PlanCell(label: 'TP2', value: fmtPrice(plan.takeProfit2), color: AppColors.buy),
                    ],
                  ),
                  const Divider(height: 18),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Risk/Reward 1:${plan.riskReward.toStringAsFixed(1)} · ATR \$${plan.atr.toStringAsFixed(2)}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 11),
                        ),
                      ),
                      Text(
                        '${plan.lotsFor(balance: state.balance, riskPercent: state.riskPercent).toStringAsFixed(2)} lots',
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // ------------------------------------------------------- checklist
          if (checks.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                const Text(
                  'CONFIRMATION CHECKLIST',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                Text(
                  '${ev?.passedCount ?? 0}/${ev?.totalChecks ?? 0} passed',
                  style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...checks.take(compact ? 4 : 9).map(_checkRow),
          ],

          if (ev != null && ev.blockers.isNotEmpty && !compact) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.wait.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.wait.withValues(alpha: .3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Row(
                    children: <Widget>[
                      Icon(Icons.info_outline_rounded, size: 14, color: AppColors.wait),
                      SizedBox(width: 6),
                      Text(
                        'Why we are NOT trading',
                        style: TextStyle(color: AppColors.wait, fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...ev.blockers.map(
                    (b) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '• $b',
                        style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: confirmed ? onOpenChart : onReanalyse,
                  icon: Icon(confirmed ? Icons.candlestick_chart_rounded : Icons.auto_awesome_rounded, size: 17),
                  label: Text(confirmed ? 'Open chart & levels' : 'Re-run AI analysis'),
                  style: FilledButton.styleFrom(
                    backgroundColor: confirmed ? color : AppColors.surfaceAlt,
                    foregroundColor: confirmed ? const Color(0xFF06080D) : AppColors.text,
                    minimumSize: const Size.fromHeight(42),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _verdictLine(TradeAction action, List<SignalCheck> failing, List<SignalCheck> passing, DashboardState s) {
    if (action.isDirectional) {
      return 'All hard gates passed (${passing.length} checks). '
          '${s.ai.modelsUsed} AI models + structure agree — wait for price to tap the entry zone.';
    }
    if (failing.isEmpty) return 'Collecting data…';
    return 'Signal is intentionally withheld: ${failing.first.label}. '
        'The app only publishes setups when every gate is green.';
  }

  Widget _checkRow(SignalCheck c) {
    final ok = c.passed;
    final color = ok ? AppColors.buy : (c.blocking ? AppColors.sell : AppColors.muted);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded, size: 14, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: '${c.label}: ',
                    style: const TextStyle(color: AppColors.text, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: c.detail,
                    style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCell extends StatelessWidget {
  const _PlanCell({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: .6),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// Small banner used on the chart screen.
class VerdictBanner extends StatelessWidget {
  const VerdictBanner({super.key, required this.action, required this.confidence, this.note});

  final TradeAction action;
  final double confidence;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final color = actionColor(action);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Row(
        children: <Widget>[
          Icon(actionIcon(action), color: color, size: 20),
          const SizedBox(width: 10),
          Text(
            action.label,
            style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              note ?? '${(confidence * 100).toStringAsFixed(0)}% confidence',
              style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class NewsBiasPill extends StatelessWidget {
  const NewsBiasPill({super.key, required this.bias, required this.risk});

  final NewsBias bias;
  final double risk;

  @override
  Widget build(BuildContext context) {
    final color = switch (bias) {
      NewsBias.bullish => AppColors.buy,
      NewsBias.bearish => AppColors.sell,
      NewsBias.mixed => AppColors.wait,
      NewsBias.neutral => AppColors.muted,
    };
    return Pill(
      label: 'NEWS ${bias.name.toUpperCase()} · RISK ${(risk * 100).round()}%',
      color: color,
      dense: true,
      icon: Icons.public_rounded,
    );
  }
}
