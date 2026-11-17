import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/news_item.dart';
import '../../models/signal.dart';
import 'common.dart';
import 'signal_card.dart';

class ModelCouncilCard extends StatelessWidget {
  const ModelCouncilCard({
    super.key,
    required this.ai,
    required this.running,
    this.onRerun,
    this.newsRisk = 0,
    this.newsBias = NewsBias.neutral,
  });

  final AiAnalysis ai;
  final bool running;
  final VoidCallback? onRerun;
  final double newsRisk;
  final NewsBias newsBias;

  @override
  Widget build(BuildContext context) {
    final votes = ai.votes;
    return SectionCard(
      title: 'AI council',
      subtitle: running
          ? 'Querying ${votes.isEmpty ? 'models' : '${votes.length} models'}…'
          : '${ai.modelsUsed} model(s) · ${(ai.agreement * 100).toStringAsFixed(0)}% agreement · '
              '${ai.generatedAt.millisecondsSinceEpoch == 0 ? 'never' : fmtAgo(ai.generatedAt)}',
      trailing: running
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
            )
          : IconButton(
              onPressed: onRerun,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              color: AppColors.muted,
              tooltip: 'Re-run AI analysis',
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  ai.summary,
                  style: const TextStyle(color: AppColors.text, fontSize: 12, height: 1.45),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Pill(
                label: 'CONSENSUS ${ai.consensus.label}',
                color: actionColor(ai.consensus),
                dense: true,
                filled: true,
              ),
              const SizedBox(width: 8),
              NewsBiasPill(bias: newsBias, risk: newsRisk),
              if (ai.offline) ...<Widget>[
                const SizedBox(width: 8),
                const Pill(label: 'OFFLINE RULES', color: AppColors.muted, dense: true),
              ],
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 92,
            child: votes.isEmpty
                ? const Center(
                    child: Text('No model answers yet', style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: votes.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => _VoteChip(vote: votes[i]),
                  ),
          ),
          if (ai.keyRisks.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: ai.keyRisks
                  .take(4)
                  .map((r) => Pill(label: r, color: AppColors.wait, dense: true))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _VoteChip extends StatelessWidget {
  const _VoteChip({required this.vote});

  final ModelVote vote;

  @override
  Widget build(BuildContext context) {
    final failed = vote.failed;
    final color = failed ? AppColors.muted : actionColor(vote.action);
    return Tooltip(
      message: failed ? '${vote.label}: ${vote.error}' : vote.rationale,
      child: Container(
        width: 148,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: failed ? AppColors.border : color.withValues(alpha: .4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  failed ? Icons.cloud_off_rounded : actionIcon(vote.action),
                  size: 13,
                  color: color,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    vote.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              failed ? (vote.error ?? 'error') : vote.action.label,
              style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w900, letterSpacing: .3),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: failed ? 0 : vote.confidence,
                minHeight: 4,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              failed
                  ? 'retry'
                  : '${(vote.confidence * 100).round()}% · ${vote.latency.inMilliseconds}ms',
              style: const TextStyle(color: AppColors.muted, fontSize: 9.5),
            ),
          ],
        ),
      ),
    );
  }
}
