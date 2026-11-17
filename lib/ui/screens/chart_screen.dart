import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/signal.dart';
import '../../state/dashboard_controller.dart';
import '../../state/providers.dart';
import '../widgets/candlestick_chart.dart';
import '../widgets/common.dart';
import '../widgets/signal_card.dart';

class ChartScreen extends ConsumerWidget {
  const ChartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DashboardState s = ref.watch(dashboardProvider);
    final ctrl = ref.read(dashboardProvider.notifier);
    final action = s.evaluation?.action ?? TradeAction.wait;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text('XAUUSD', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Text(
              fmtPrice(s.price),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.gold),
            ),
            const Spacer(),
            LiveDot(active: s.feedLive),
            const SizedBox(width: 6),
            Text(
              s.feedLive ? 'LIVE' : 'DEMO',
              style: TextStyle(
                color: s.feedLive ? AppColors.buy : AppColors.wait,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: <String>['1m', '5m', '15m', '30m', '1h']
                .map((tf) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(tf, style: const TextStyle(fontSize: 11)),
                        selected: s.interval == tf,
                        onSelected: (_) => ctrl.setInterval(tf),
                        selectedColor: AppColors.gold.withValues(alpha: .2),
                        backgroundColor: AppColors.surfaceAlt,
                        side: BorderSide(
                          color: s.interval == tf ? AppColors.gold : AppColors.border,
                        ),
                        labelStyle: TextStyle(
                          color: s.interval == tf ? AppColors.gold : AppColors.muted,
                          fontWeight: FontWeight.w700,
                        ),
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 12),
        VerdictBanner(
          action: action,
          confidence: s.evaluation?.confidence ?? 0,
          note: action.isDirectional
              ? 'Plan active · ${s.activeSignal?.plan != null ? 'entry ${fmtPrice(s.activeSignal!.plan!.entry)}' : ''}'
              : s.evaluation?.blockers.isNotEmpty == true
                  ? s.evaluation!.blockers.first
                  : 'Waiting for confirmation',
        ),
        const SizedBox(height: 12),
        SectionCard(
          padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
          child: CandleChart(
            candles: s.candles,
            tech: s.tech,
            plan: s.activeSignal?.plan,
            height: MediaQuery.sizeOf(context).height * 0.42,
            visibleCount: 80,
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Indicators',
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  _Metric(label: 'RSI 14', value: s.tech.rsi.toStringAsFixed(1), good: s.tech.rsi > 50),
                  _Metric(label: 'ADX 14', value: s.tech.adx.toStringAsFixed(1), good: s.tech.adx > 25),
                  _Metric(label: 'ATR 14', value: s.tech.atr.toStringAsFixed(2), good: true),
                  _Metric(label: 'SCORE', value: s.tech.score.toStringAsFixed(2), good: s.tech.score >= 0),
                ],
              ),
              const Divider(height: 22),
              KeyValueRow(label: 'EMA 9 / 21', value: '${s.tech.ema9.toStringAsFixed(2)} / ${s.tech.ema21.toStringAsFixed(2)}'),
              KeyValueRow(label: 'EMA 50 / 200', value: '${s.tech.ema50.toStringAsFixed(2)} / ${s.tech.ema200.toStringAsFixed(2)}'),
              KeyValueRow(label: 'MACD hist', value: s.tech.macdHist.toStringAsFixed(2)),
              KeyValueRow(label: 'Bollinger width', value: '${s.tech.bbWidth.toStringAsFixed(2)}%'),
              KeyValueRow(label: 'Support / Resistance', value: '${s.tech.support.toStringAsFixed(2)} / ${s.tech.resistance.toStringAsFixed(2)}'),
              KeyValueRow(label: '60-candle range', value: '${s.tech.sessionLow.toStringAsFixed(2)} – ${s.tech.sessionHigh.toStringAsFixed(2)}'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Structure notes',
          subtitle: 'What the rule engine sees right now',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: s.tech.notes
                .map(
                  (n) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Icon(Icons.circle, size: 5, color: AppColors.gold),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            n,
                            style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 14),
        if (s.activeSignal?.plan != null)
          SectionCard(
            title: 'Trade plan (ATR + structure based)',
            child: Column(
              children: <Widget>[
                KeyValueRow(label: 'Direction', value: s.activeSignal!.action.label, valueColor: actionColor(s.activeSignal!.action), bold: true),
                KeyValueRow(label: 'Entry', value: fmtPrice(s.activeSignal!.plan!.entry)),
                KeyValueRow(label: 'Stop loss', value: fmtPrice(s.activeSignal!.plan!.stopLoss), valueColor: AppColors.sell),
                KeyValueRow(label: 'Take profit 1', value: fmtPrice(s.activeSignal!.plan!.takeProfit1), valueColor: AppColors.buy),
                KeyValueRow(label: 'Take profit 2', value: fmtPrice(s.activeSignal!.plan!.takeProfit2), valueColor: AppColors.buy),
                KeyValueRow(
                  label: 'Position size (${s.riskPercent.toStringAsFixed(1)}% of \$${s.balance.toStringAsFixed(0)})',
                  value: '${s.activeSignal!.plan!.lotsFor(balance: s.balance, riskPercent: s.riskPercent).toStringAsFixed(2)} lots',
                  valueColor: AppColors.gold,
                  bold: true,
                ),
                KeyValueRow(label: 'Valid until', value: fmtDayTime.format(s.activeSignal!.expiresAt)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.good});

  final String label;
  final String value;
  final bool good;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: good ? AppColors.buy : AppColors.sell,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 9.5, letterSpacing: .4)),
        ],
      ),
    );
  }
}
