import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../state/dashboard_controller.dart';
import 'common.dart';

/// Realtime FOREX.com XAUUSD quote strip: bid / ask / spread, session
/// open-high-low and the age of the last tick (re-rendered every second so
/// "x s ago" stays honest even when the market is quiet).
class RealtimePriceCard extends StatefulWidget {
  const RealtimePriceCard({super.key, required this.state});

  final DashboardState state;

  @override
  State<RealtimePriceCard> createState() => _RealtimePriceCardState();
}

class _RealtimePriceCardState extends State<RealtimePriceCard> {
  Timer? _ticker;
  double? _prevPrice;
  bool _flashUp = true;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(RealtimePriceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final price = widget.state.price;
    if (_prevPrice != null && price != _prevPrice) _flashUp = price > _prevPrice!;
    _prevPrice = price;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final tick = s.tick;
    final live = s.feedLive;
    final age = tick == null ? null : DateTime.now().difference(tick.time);
    final stale = age != null && age > const Duration(seconds: 20);

    return SectionCard(
      title: 'Realtime · FOREX.com',
      subtitle: 'XAUUSD · FOREXCOM:XAUUSD — streaming, no key required',
      trailing: Pill(
        label: live && !stale ? 'LIVE' : (tick == null ? 'CONNECTING' : 'STALE'),
        color: live && !stale ? AppColors.buy : AppColors.wait,
        filled: true,
        dense: true,
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              _quoteBox(
                label: 'BID · SELL',
                value: tick?.bid,
                color: AppColors.sell,
              ),
              const SizedBox(width: 10),
              _quoteBox(
                label: 'ASK · BUY',
                value: tick?.ask,
                color: AppColors.buy,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('SPREAD',
                          style: TextStyle(color: AppColors.muted, fontSize: 9.5, letterSpacing: .8)),
                      const SizedBox(height: 3),
                      Text(
                        tick != null && tick.spread > 0 ? tick.spread.toStringAsFixed(2) : '—',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Icon(
                _flashUp ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                size: 16,
                color: _flashUp ? AppColors.buy : AppColors.sell,
              ),
              Text(
                'Last ${fmtPrice(s.price)}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: _flashUp ? AppColors.buy : AppColors.sell,
                ),
              ),
              const Spacer(),
              if (tick?.dayOpen != null) _mini('O', tick!.dayOpen!),
              if (tick?.dayHigh != null) _mini('H', tick!.dayHigh!),
              if (tick?.dayLow != null) _mini('L', tick!.dayLow!),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              LiveDot(active: live && !stale, color: AppColors.buy),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tick == null
                      ? 'Waiting for the first FOREX.com tick… (market closed on weekends)'
                      : 'Updated ${fmtAgo(tick.time)}${stale ? ' — reconnecting…' : ''}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'Candles: FOREXCOM via TradingView',
                style: const TextStyle(color: AppColors.muted, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quoteBox({required String label, required double? value, required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: .35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: TextStyle(color: color, fontSize: 9.5, letterSpacing: .8)),
            const SizedBox(height: 3),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(
                value == null ? '—' : fmtPrice(value),
                key: ValueKey<String>(value?.toStringAsFixed(2) ?? '—'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mini(String label, double value) => Padding(
        padding: const EdgeInsets.only(left: 10),
        child: Text(
          '$label ${fmtPrice(value)}',
          style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
        ),
      );
}
