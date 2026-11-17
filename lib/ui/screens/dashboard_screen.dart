import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../state/dashboard_controller.dart';
import '../../state/providers.dart';
import '../widgets/candlestick_chart.dart';
import '../widgets/common.dart';
import '../widgets/model_council.dart';
import '../widgets/news_widgets.dart';
import '../widgets/price_header.dart';
import '../widgets/realtime_price_card.dart';
import '../widgets/signal_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key, required this.onOpenChart});

  final VoidCallback onOpenChart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DashboardState s = ref.watch(dashboardProvider);
    final ctrl = ref.read(dashboardProvider.notifier);

    return RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: AppColors.surface,
      onRefresh: ctrl.manualRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: <Widget>[
          PriceHeader(
            state: s,
            aiRunning: s.aiRunning,
            onRefresh: ctrl.manualRefresh,
            onReanalyse: ctrl.reanalyse,
          ),
          const SizedBox(height: 14),
          RealtimePriceCard(state: s),
          if (s.error != null) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.sell.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.sell.withValues(alpha: .35)),
              ),
              child: Text(
                s.error!,
                style: const TextStyle(color: AppColors.sell, fontSize: 11),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (s.loading && s.candles.isEmpty)
            const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator(color: AppColors.gold)),
            )
          else
            SignalCard(
              state: s,
              evaluation: s.evaluation,
              onReanalyse: ctrl.reanalyse,
              onOpenChart: onOpenChart,
            ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Live chart · ${s.interval}',
            subtitle: '${s.candles.length} candles · EMA21/50 · ATR \$${s.tech.atr.toStringAsFixed(2)}',
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            trailing: TextButton.icon(
              onPressed: onOpenChart,
              icon: const Icon(Icons.open_in_full_rounded, size: 14),
              label: const Text('Expand', style: TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(foregroundColor: AppColors.gold),
            ),
            child: CandleChart(
              candles: s.candles,
              tech: s.tech,
              plan: s.activeSignal?.plan,
              height: 210,
              visibleCount: 55,
            ),
          ),
          const SizedBox(height: 14),
          ModelCouncilCard(
            ai: s.ai,
            running: s.aiRunning,
            onRerun: ctrl.reanalyse,
            newsRisk: s.newsRisk,
            newsBias: s.newsBias,
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Global news radar',
            subtitle: s.newsLive ? 'Live headlines · Google News' : 'Demo headlines (enable live in settings)',
            trailing: Pill(
              label: s.newsRisk > .7 ? 'HIGH RISK' : s.newsRisk > .4 ? 'ELEVATED' : 'CALM',
              color: s.newsRisk > .7
                  ? AppColors.sell
                  : s.newsRisk > .4
                      ? AppColors.wait
                      : AppColors.buy,
              dense: true,
            ),
            child: Column(
              children: <Widget>[
                NewsRiskMeter(risk: s.newsRisk, bias: s.newsBias, count: s.news.length),
                const SizedBox(height: 12),
                ...s.news.take(4).map((n) => NewsTile(item: n)),
                if (s.news.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No headlines yet',
                      style: TextStyle(color: AppColors.muted, fontSize: 11.5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'High-impact events',
            subtitle: 'Signals are automatically paused around these',
            child: Column(
              children: <Widget>[
                ...s.events
                    .where((e) => e.time.isAfter(DateTime.now().subtract(const Duration(hours: 1))))
                    .take(4)
                    .map((e) => EventTile(event: e)),
                if (s.events.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Calendar unavailable', style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const _Disclaimer(),
        ],
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.shield_outlined, size: 14, color: AppColors.muted),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Analysis tool only — no orders are sent to any broker. XAUUSD is highly leveraged; '
              'never risk money you cannot afford to lose. Signals can be wrong.',
              style: TextStyle(color: AppColors.muted, fontSize: 10.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
