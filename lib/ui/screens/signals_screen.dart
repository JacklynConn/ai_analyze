import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/signal.dart';
import '../../state/dashboard_controller.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/signal_card.dart';

class SignalsScreen extends ConsumerWidget {
  const SignalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DashboardState s = ref.watch(dashboardProvider);
    final all = <TradeSignal>[
      if (s.activeSignal != null) s.activeSignal!,
      ...s.history.where((h) => h.id != s.activeSignal?.id),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: <Widget>[
        const Text(
          'Signal journal',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'Every confirmed setup is logged locally. Unconfirmed ideas are never stored — '
          'that is the point of the confirmation gate.',
          style: TextStyle(color: AppColors.muted.withValues(alpha: .9), fontSize: 11.5, height: 1.4),
        ),
        const SizedBox(height: 16),
        if (all.isEmpty)
          const SizedBox(
            height: 320,
            child: EmptyState(
              icon: Icons.radar_rounded,
              title: 'No confirmed signals yet',
              subtitle: 'The engine is waiting for technicals, AI consensus and the news '
                  'calendar to line up. Pull to refresh on the market tab.',
            ),
          )
        else
          ...all.map((sig) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SignalHistoryCard(signal: sig, active: sig.id == s.activeSignal?.id),
              )),
      ],
    );
  }
}

class _SignalHistoryCard extends StatelessWidget {
  const _SignalHistoryCard({required this.signal, required this.active});

  final TradeSignal signal;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = actionColor(signal.action);
    final expired = signal.isExpired;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: active && !expired ? color.withValues(alpha: .5) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(actionIcon(signal.action), size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                signal.action.label,
                style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 8),
              Pill(
                label: expired ? 'EXPIRED' : (active ? 'ACTIVE' : 'CLOSED'),
                color: expired ? AppColors.muted : color,
                dense: true,
              ),
              const Spacer(),
              Text(
                '${(signal.confidence * 100).round()}%',
                style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            fmtDayTime.format(signal.createdAt),
            style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
          ),
          if (signal.plan != null) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                _cell('ENTRY', fmtPrice(signal.plan!.entry), AppColors.text),
                _cell('SL', fmtPrice(signal.plan!.stopLoss), AppColors.sell),
                _cell('TP1', fmtPrice(signal.plan!.takeProfit1), AppColors.buy),
                _cell('TP2', fmtPrice(signal.plan!.takeProfit2), AppColors.buy),
              ],
            ),
          ],
          if (signal.reasons.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              signal.reasons.take(2).join(' · '),
              style: const TextStyle(color: AppColors.muted, fontSize: 10.5, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cell(String label, String value, Color color) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 8.5, fontWeight: FontWeight.w700)),
            Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
