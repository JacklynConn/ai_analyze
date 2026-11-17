import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/news_item.dart';
import 'common.dart';

Color impactColor(NewsImpact i) {
  switch (i) {
    case NewsImpact.critical:
      return AppColors.sell;
    case NewsImpact.high:
      return AppColors.wait;
    case NewsImpact.medium:
      return AppColors.gold;
    case NewsImpact.low:
      return AppColors.muted;
  }
}

Color biasColor(NewsBias b) {
  switch (b) {
    case NewsBias.bullish:
      return AppColors.buy;
    case NewsBias.bearish:
      return AppColors.sell;
    case NewsBias.mixed:
      return AppColors.wait;
    case NewsBias.neutral:
      return AppColors.muted;
  }
}

class NewsTile extends StatelessWidget {
  const NewsTile({super.key, required this.item, this.showSummary = false});

  final NewsItem item;
  final bool showSummary;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final uri = Uri.tryParse(item.url);
        if (uri == null) return;
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border, width: .6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Pill(label: item.impact.name.toUpperCase(), color: impactColor(item.impact), dense: true),
                const SizedBox(width: 6),
                Pill(
                  label: item.bias.name.toUpperCase(),
                  color: biasColor(item.bias),
                  dense: true,
                  icon: item.bias == NewsBias.bullish
                      ? Icons.arrow_upward_rounded
                      : item.bias == NewsBias.bearish
                          ? Icons.arrow_downward_rounded
                          : null,
                ),
                const Spacer(),
                Text(
                  fmtAgo(item.publishedAt),
                  style: const TextStyle(color: AppColors.muted, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.4),
            ),
            if (showSummary && item.summary.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                item.summary,
                style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Text(
                  item.source,
                  style: const TextStyle(color: AppColors.muted, fontSize: 10.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Icon(
                  item.sentiment > .15
                      ? Icons.trending_up_rounded
                      : item.sentiment < -.15
                          ? Icons.trending_down_rounded
                          : Icons.remove_rounded,
                  size: 12,
                  color: biasColor(item.bias),
                ),
                Text(
                  ' ${item.sentiment >= 0 ? '+' : ''}${item.sentiment.toStringAsFixed(2)}',
                  style: TextStyle(color: biasColor(item.bias), fontSize: 10),
                ),
                const Spacer(),
                const Icon(Icons.open_in_new_rounded, size: 12, color: AppColors.muted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.event});

  final EconomicEvent event;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final until = event.timeUntil(now);
    final isPast = until.isNegative;
    final imminent = !isPast && until.inMinutes <= 45;
    final color = impactColor(event.impact);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: imminent ? AppColors.wait.withValues(alpha: .09) : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: imminent ? AppColors.wait.withValues(alpha: .5) : AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: <Widget>[
                Text(
                  '${event.time.hour.toString().padLeft(2, '0')}:${event.time.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800),
                ),
                Text(event.country, style: const TextStyle(color: AppColors.muted, fontSize: 9)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  event.title,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  isPast
                      ? 'released ${fmtAgo(event.time)}'
                      : 'in ${fmtCountdown(until)}${event.forecast != null ? ' · forecast ${event.forecast}' : ''}',
                  style: TextStyle(
                    color: imminent ? AppColors.wait : AppColors.muted,
                    fontSize: 10.5,
                    fontWeight: imminent ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Pill(label: event.impact.name.toUpperCase(), color: color, dense: true),
        ],
      ),
    );
  }
}

class NewsRiskMeter extends StatelessWidget {
  const NewsRiskMeter({super.key, required this.risk, required this.bias, required this.count});

  final double risk;
  final NewsBias bias;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = risk > .7 ? AppColors.sell : risk > .4 ? AppColors.wait : AppColors.buy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              'NEWS RISK ${(risk * 100).round()}%',
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .4),
            ),
            const Spacer(),
            Text(
              '$count headlines · bias ${bias.name}',
              style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: risk.clamp(0, 1),
            minHeight: 6,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
