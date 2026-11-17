import 'dart:math' as math;

import '../models/news_item.dart';

/// Keyword-driven gold-news scorer.
///
/// It runs fully on-device (no API key needed) and gives:
///  * an impact score per headline (how much it can move XAUUSD),
///  * a directional bias (bullish / bearish gold),
///  * an aggregate "news risk" that can veto a technical signal.
class NewsImpactEngine {
  const NewsImpactEngine();

  static const Map<String, double> _bullish = <String, double>{
    'rate cut': 1.0, 'dovish': 0.8, 'inflation': 0.55, 'cpi': 0.5, 'recession': 0.8,
    'war': 0.9, 'attack': 0.7, 'conflict': 0.7, 'sanctions': 0.6, 'tariff': 0.5,
    'safe haven': 0.9, 'safe-haven': 0.9, 'geopolitical': 0.7, 'missile': 0.8,
    'weak dollar': 0.8, 'dollar falls': 0.7, 'stimulus': 0.6, 'central bank buying': 1.0,
    'gold buying': 0.9, 'etf inflow': 0.7, 'uncertainty': 0.5, 'default': 0.7,
    'shutdown': 0.5, 'protest': 0.4, 'nuclear': 0.9, 'drone': 0.6,
  };

  static const Map<String, double> _bearish = <String, double>{
    'rate hike': 1.0, 'hawkish': 0.8, 'strong dollar': 0.8, 'dollar rises': 0.7,
    'yields rise': 0.7, 'yield surge': 0.8, 'risk-on': 0.6, 'selloff': 0.6,
    'profit taking': 0.5, 'ceasefire': 0.9, 'peace deal': 0.8, 'truce': 0.7,
    'etf outflow': 0.7, 'gold falls': 0.6, 'gold drops': 0.6, 'rally in stocks': 0.5,
    'resilient economy': 0.5, 'jobs beat': 0.5, 'hot inflation': 0.4,
  };

  static const Map<String, double> _impactBoosters = <String, double>{
    'fed': 0.6, 'fomc': 0.9, 'powell': 0.8, 'cpi': 0.8, 'nfp': 0.9,
    'nonfarm': 0.9, 'non-farm': 0.9, 'unemployment': 0.6, 'gdp': 0.5,
    'interest rate': 0.8, 'ecb': 0.5, 'boj': 0.5, 'treasury': 0.5,
    'ukraine': 0.6, 'russia': 0.6, 'israel': 0.6, 'iran': 0.7, 'china': 0.4,
    'middle east': 0.7, 'breaking': 0.4, 'emergency': 0.8, 'crash': 0.9,
    'explosion': 0.7, 'opec': 0.4, 'trump': 0.5, 'tariffs': 0.6,
  };

  NewsItem score(NewsItem item) {
    final text = '${item.title} ${item.summary}'.toLowerCase();
    var bull = 0.0;
    var bear = 0.0;
    var impact = 0.0;
    final tags = <String>{};

    _bullish.forEach((k, w) {
      if (text.contains(k)) {
        bull += w;
        impact += w * 0.6;
        tags.add(k);
      }
    });
    _bearish.forEach((k, w) {
      if (text.contains(k)) {
        bear += w;
        impact += w * 0.6;
        tags.add(k);
      }
    });
    _impactBoosters.forEach((k, w) {
      if (text.contains(k)) {
        impact += w;
        tags.add(k);
      }
    });

    final net = bull - bear;
    // RSI-style squash to -1..1
    final sentiment = net == 0 ? 0.0 : (net / (net.abs() + 1.5)).clamp(-1.0, 1.0);

    final impactScore = impact.clamp(0.0, 3.0);
    final level = impactScore > 1.8
        ? NewsImpact.critical
        : impactScore > 1.0
            ? NewsImpact.high
            : impactScore > 0.4
                ? NewsImpact.medium
                : NewsImpact.low;

    NewsBias bias;
    if (bull > 0 && bear > 0 && (bull - bear).abs() < 0.35) {
      bias = NewsBias.mixed;
    } else if (sentiment > 0.18) {
      bias = NewsBias.bullish;
    } else if (sentiment < -0.18) {
      bias = NewsBias.bearish;
    } else {
      bias = NewsBias.neutral;
    }

    return item.copyWith(impact: level, bias: bias, sentiment: sentiment, tags: tags.toList());
  }

  /// Aggregates headlines into a single risk number + net bias.
  ({double risk, NewsBias bias, List<NewsItem> top}) aggregate(List<NewsItem> items, {int windowHours = 12}) {
    final cutoff = DateTime.now().subtract(Duration(hours: windowHours));
    final fresh = items.where((n) => n.publishedAt.isAfter(cutoff)).toList();
    if (fresh.isEmpty) return (risk: 0.0, bias: NewsBias.neutral, top: <NewsItem>[]);

    var weighted = 0.0;
    var weightSum = 0.0;
    var risk = 0.0;
    for (final n in fresh) {
      final w = switch (n.impact) {
        NewsImpact.critical => 3.0,
        NewsImpact.high => 2.0,
        NewsImpact.medium => 1.0,
        NewsImpact.low => 0.4,
      };
      final recency = 1 / (1 + DateTime.now().difference(n.publishedAt).inHours);
      weighted += n.sentiment * w * recency;
      weightSum += w * recency;
      risk += w * recency * 0.35;
    }
    final net = weightSum == 0 ? 0.0 : weighted / weightSum;
    final riskNorm = (1 - math.exp(-risk / 4)).clamp(0.0, 1.0);

    NewsBias bias;
    if (net > 0.2) {
      bias = NewsBias.bullish;
    } else if (net < -0.2) {
      bias = NewsBias.bearish;
    } else {
      bias = NewsBias.neutral;
    }

    final top = fresh.toList()..sort((a, b) => b.impact.index != a.impact.index
        ? b.impact.index.compareTo(a.impact.index)
        : b.publishedAt.compareTo(a.publishedAt));

    return (risk: riskNorm, bias: bias, top: top.take(6).toList());
  }
}
