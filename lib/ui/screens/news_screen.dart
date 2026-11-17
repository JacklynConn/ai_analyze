import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/news_item.dart';
import '../../state/dashboard_controller.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/news_widgets.dart';

class NewsScreen extends ConsumerStatefulWidget {
  const NewsScreen({super.key});

  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen> {
  NewsImpact? _filter;

  @override
  Widget build(BuildContext context) {
    final DashboardState s = ref.watch(dashboardProvider);
    final ctrl = ref.read(dashboardProvider.notifier);
    final filtered = _filter == null ? s.news : s.news.where((n) => n.impact == _filter).toList();

    return RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: AppColors.surface,
      onRefresh: ctrl.manualRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text('News & macro', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              Pill(
                label: s.newsLive ? 'LIVE' : 'DEMO',
                color: s.newsLive ? AppColors.buy : AppColors.wait,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'News risk index',
            subtitle: 'Weighted by impact and recency — used as a veto in the signal engine',
            child: Column(
              children: <Widget>[
                NewsRiskMeter(risk: s.newsRisk, bias: s.newsBias, count: s.news.length),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _filterChip(null, 'All'),
                    _filterChip(NewsImpact.critical, 'Critical'),
                    _filterChip(NewsImpact.high, 'High'),
                    _filterChip(NewsImpact.medium, 'Medium'),
                    _filterChip(NewsImpact.low, 'Low'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Upcoming high-impact events (USD)',
            subtitle: 'Auto-paused window: ±${ref.watch(settingsProvider).blackoutMinutes} min',
            child: Column(
              children: s.events
                  .where((e) => e.time.isAfter(DateTime.now().subtract(const Duration(hours: 2))))
                  .take(6)
                  .map((e) => EventTile(event: e))
                  .toList(),
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Headlines',
            subtitle: '${filtered.length} item(s) · tap to open source',
            padding: EdgeInsets.zero,
            child: Column(
              children: filtered.map((n) => NewsTile(item: n, showSummary: true)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(NewsImpact? impact, String label) {
    final selected = _filter == impact;
    final color = impact == null ? AppColors.gold : impactColor(impact);
    return GestureDetector(
      onTap: () => setState(() => _filter = impact),
      child: Pill(
        label: label,
        color: selected ? color : AppColors.muted,
        dense: true,
        filled: selected,
      ),
    );
  }
}
