import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../state/dashboard_controller.dart';
import 'common.dart';

class PriceHeader extends StatelessWidget {
  const PriceHeader({
    super.key,
    required this.state,
    this.onRefresh,
    this.onReanalyse,
    this.aiRunning = false,
  });

  final DashboardState state;
  final VoidCallback? onRefresh;
  final VoidCallback? onReanalyse;
  final bool aiRunning;

  @override
  Widget build(BuildContext context) {
    final price = state.price;
    final up = state.changePct >= 0;
    final color = up ? AppColors.buy : AppColors.sell;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppColors.gold.withValues(alpha: .4)),
              ),
              child: const Center(
                child: Text(
                  'Au',
                  style: TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'XAUUSD',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: .4),
            ),
            const SizedBox(width: 8),
            Pill(label: state.interval, color: AppColors.muted, dense: true),
            const Spacer(),
            IconButton(
              onPressed: state.aiRunning ? null : onReanalyse,
              icon: state.aiRunning
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
                    )
                  : const Icon(Icons.auto_awesome_rounded, size: 19),
              color: AppColors.gold,
              tooltip: 'Re-run AI analysis',
            ),
            IconButton(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 19),
              color: AppColors.muted,
              tooltip: 'Refresh data',
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                fmtPrice(price),
                key: ValueKey<String>(price.toStringAsFixed(2)),
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.5,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Pill(
                label: '${up ? '+' : ''}${state.changePct.toStringAsFixed(2)}%',
                color: color,
                icon: up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                filled: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            LiveDot(active: state.feedLive, color: state.feedLive ? AppColors.buy : AppColors.wait),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                state.feedLive ? state.feedLabel : '${state.feedLabel} · simulated',
                style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            if (state.tick?.spread != null && state.tick!.spread > 0)
              Text(
                'spread ${state.tick!.spread.toStringAsFixed(2)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
              ),
            const Spacer(),
            if (state.updatedAt != null)
              Text(
                '${fmtTime.format(state.updatedAt!)}·${fmtAgo(state.updatedAt!)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
              ),
          ],
        ),
      ],
    );
  }
}
