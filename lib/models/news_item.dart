/// How much a headline matters for gold.
enum NewsImpact { low, medium, high, critical }

/// Directional pressure the news applies to XAUUSD.
enum NewsBias { bullish, bearish, neutral, mixed }

class NewsItem {
  final String id;
  final String title;
  final String source;
  final String url;
  final DateTime publishedAt;
  final String summary;
  final NewsImpact impact;
  final NewsBias bias;
  final double sentiment; // -1 .. +1 (positive = bullish gold)
  final List<String> tags;

  const NewsItem({
    required this.id,
    required this.title,
    required this.source,
    required this.url,
    required this.publishedAt,
    this.summary = '',
    this.impact = NewsImpact.medium,
    this.bias = NewsBias.neutral,
    this.sentiment = 0,
    this.tags = const <String>[],
  });

  NewsItem copyWith({
    NewsImpact? impact,
    NewsBias? bias,
    double? sentiment,
    List<String>? tags,
  }) =>
      NewsItem(
        id: id,
        title: title,
        source: source,
        url: url,
        publishedAt: publishedAt,
        summary: summary,
        impact: impact ?? this.impact,
        bias: bias ?? this.bias,
        sentiment: sentiment ?? this.sentiment,
        tags: tags ?? this.tags,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'source': source,
        'url': url,
        'ts': publishedAt.millisecondsSinceEpoch,
        'summary': summary,
        'impact': impact.name,
        'bias': bias.name,
        'sentiment': sentiment,
        'tags': tags,
      };

  factory NewsItem.fromJson(Map<String, dynamic> j) => NewsItem(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        source: j['source'] as String? ?? '',
        url: j['url'] as String? ?? '',
        publishedAt: DateTime.fromMillisecondsSinceEpoch((j['ts'] as num?)?.toInt() ?? 0),
        summary: j['summary'] as String? ?? '',
        impact: NewsImpact.values.firstWhere(
          (e) => e.name == j['impact'],
          orElse: () => NewsImpact.medium,
        ),
        bias: NewsBias.values.firstWhere(
          (e) => e.name == j['bias'],
          orElse: () => NewsBias.neutral,
        ),
        sentiment: (j['sentiment'] as num?)?.toDouble() ?? 0,
        tags: (j['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const <String>[],
      );
}

/// Scheduled macro event (NFP, CPI, FOMC ...) that can invalidate a setup.
class EconomicEvent {
  final String title;
  final String country;
  final DateTime time;
  final NewsImpact impact;
  final String? forecast;
  final String? previous;

  const EconomicEvent({
    required this.title,
    required this.country,
    required this.time,
    required this.impact,
    this.forecast,
    this.previous,
  });

  bool get isHighImpact => impact == NewsImpact.high || impact == NewsImpact.critical;

  Duration timeUntil(DateTime now) => time.difference(now);
}
