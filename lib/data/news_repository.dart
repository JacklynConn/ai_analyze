import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../analysis/news_impact.dart';
import '../core/http_headers.dart';
import '../models/news_item.dart';

abstract class NewsRepository {
  String get label;
  bool get isLive;
  Future<List<NewsItem>> fetch({int limit = 40});
}

// ---------------------------------------------------------------------------
// DEMO headlines (no network, realistic wording).
// ---------------------------------------------------------------------------
class MockNewsRepository implements NewsRepository {
  @override
  String get label => 'DEMO headlines';

  @override
  bool get isLive => false;

  @override
  Future<List<NewsItem>> fetch({int limit = 40}) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final now = DateTime.now();
    final raw = <(String, String, int, String)>[
      ('Fed officials signal patience on rate cuts as core inflation stays sticky', 'Reuters', 35,
          'Several policymakers said they want more evidence before easing; markets trim odds for a December cut.'),
      ('Dollar index slips for a third session, gold holds above key support', 'Bloomberg', 90,
          'A softer dollar and falling real yields are supporting bullion demand.'),
      ('US CPI preview: core inflation expected at 3.1% year-on-year', 'CNBC', 150,
          'Traders are positioning ahead of the release; a hot print could revive rate-hike bets.'),
      ('Middle East tensions escalate after overnight strikes', 'AP', 210,
          'Safe-haven flows lifted gold in Asian hours as investors sought protection.'),
      ('Central bank gold buying continues at record pace in Q3', 'World Gold Council', 320,
          'Official sector purchases remain the strongest structural bid for bullion.'),
      ('Treasury yields rise as strong jobs data reduces recession fears', 'WSJ', 400,
          'A resilient labour market keeps the Fed cautious; gold slipped on the headline.'),
      ('Gold ETF inflows turn positive for the first time in five weeks', 'Kitco', 520,
          'ETF holdings rose 4.2 tonnes, hinting at returning institutional interest.'),
      ('China stimulus package lifts risk appetite across Asian equities', 'SCMP', 640,
          'Better sentiment reduced safe-haven demand but physical gold premiums stayed firm.'),
      ('FOMC minutes: members see risks to both inflation and employment', 'Federal Reserve', 760,
          'The minutes showed a split committee, leaving policy path data-dependent.'),
      ('Ceasefire talks resume, easing geopolitical risk premium', 'Reuters', 900,
          'Progress in negotiations could remove part of the safe-haven bid for gold.'),
    ];
    const engine = NewsImpactEngine();
    return raw
        .take(limit)
        .map((r) => engine.score(NewsItem(
              id: 'mock-${r.$3}',
              title: r.$1,
              source: r.$2,
              url: 'https://www.google.com/search?q=${Uri.encodeComponent(r.$1)}',
              publishedAt: now.subtract(Duration(minutes: r.$3)),
              summary: r.$4,
            )))
        .toList();
  }
}

// ---------------------------------------------------------------------------
// LIVE — Google News RSS (free, no key). Great for geopolitical + macro flow.
// ---------------------------------------------------------------------------
class GoogleNewsRssRepository implements NewsRepository {
  GoogleNewsRssRepository({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  bool _live = false;

  @override
  String get label => 'Google News RSS';

  @override
  bool get isLive => _live;

  static const String _query = '(gold OR XAUUSD OR "Federal Reserve" OR inflation) when:1d';

  @override
  Future<List<NewsItem>> fetch({int limit = 40}) async {
    final uri = Uri.https('news.google.com', '/rss/search', <String, String>{
      'q': _query,
      'hl': 'en-US',
      'gl': 'US',
      'ceid': 'US:en',
    });
    final res = await _dio.get<String>(
      uri.toString(),
      options: Options(
        responseType: ResponseType.plain,
        headers: webSafeUserAgent(),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    final body = res.data ?? '';
    if (body.isEmpty) throw StateError('empty rss');
    final doc = XmlDocument.parse(body);
    const engine = NewsImpactEngine();
    final out = <NewsItem>[];
    for (final node in doc.findAllElements('item').take(limit)) {
      final title = node.getElement('title')?.innerText ?? '';
      final link = node.getElement('link')?.innerText ?? '';
      final pub = node.getElement('pubDate')?.innerText ?? '';
      final source = node.getElement('source')?.innerText ?? 'Google News';
      if (title.isEmpty) continue;
      final date = _parseDate(pub) ?? DateTime.now();
      out.add(engine.score(NewsItem(
        id: base64Url.encode(utf8.encode(title)).substring(0, 16),
        title: title,
        source: source,
        url: link,
        publishedAt: date,
        summary: '',
      )));
    }
    if (out.isEmpty) throw StateError('no rss items');
    _live = true;
    return out;
  }

  DateTime? _parseDate(String raw) {
    if (raw.isEmpty) return null;
    try {
      // e.g. "Mon, 17 Nov 2026 07:40:00 GMT"
      const months = <String, int>{
        'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
        'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
      };
      final parts = raw.split(' ');
      if (parts.length < 6) return null;
      final day = int.parse(parts[1]);
      final month = months[parts[2]];
      final year = int.parse(parts[3]);
      final hms = parts[4].split(':').map(int.parse).toList();
      if (month == null) return null;
      return DateTime.utc(year, month, day, hms[0], hms[1], hms.length > 2 ? hms[2] : 0)
          .toLocal();
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Composite: try live sources, gracefully fall back to demo data.
// ---------------------------------------------------------------------------
class CompositeNewsRepository implements NewsRepository {
  CompositeNewsRepository({List<NewsRepository>? sources, MockNewsRepository? fallback})
      : _sources = sources ?? <NewsRepository>[
          GoogleNewsRssRepository(),
        ],
        _fallback = fallback ?? MockNewsRepository();

  final List<NewsRepository> _sources;
  final MockNewsRepository _fallback;
  bool _liveUsed = false;

  @override
  String get label => _liveUsed ? 'Live news (Google News RSS)' : 'Demo headlines';

  @override
  bool get isLive => _liveUsed;

  @override
  Future<List<NewsItem>> fetch({int limit = 40}) async {
    for (final s in _sources) {
      try {
        final items = await s.fetch(limit: limit);
        if (items.isNotEmpty) {
          _liveUsed = true;
          return items;
        }
      } catch (_) {
        continue;
      }
    }
    _liveUsed = false;
    return _fallback.fetch(limit: limit);
  }
}

// ---------------------------------------------------------------------------
// Economic calendar
// ---------------------------------------------------------------------------
abstract class CalendarRepository {
  Future<List<EconomicEvent>> fetch();
}

class MockCalendarRepository implements CalendarRepository {
  @override
  Future<List<EconomicEvent>> fetch() async {
    final now = DateTime.now();
    DateTime todayAt(int hour, int minute) => DateTime(now.year, now.month, now.day, hour, minute);

    final candidates = <EconomicEvent>[
      EconomicEvent(title: 'US Core CPI (YoY)', country: 'US', time: todayAt(13, 30), impact: NewsImpact.high, forecast: '3.1%', previous: '3.2%'),
      EconomicEvent(title: 'US Initial Jobless Claims', country: 'US', time: todayAt(13, 30).add(const Duration(days: 1)), impact: NewsImpact.medium),
      EconomicEvent(title: 'FOMC Member Speech', country: 'US', time: todayAt(17, 0), impact: NewsImpact.medium),
      EconomicEvent(title: 'US Non-Farm Payrolls', country: 'US', time: todayAt(13, 30).add(const Duration(days: 2)), impact: NewsImpact.critical, forecast: '165K', previous: '142K'),
      EconomicEvent(title: 'Fed Interest Rate Decision', country: 'US', time: todayAt(19, 0).add(const Duration(days: 3)), impact: NewsImpact.critical),
    ];
    return candidates.where((e) => e.time.isAfter(now.subtract(const Duration(hours: 2)))).toList();
  }
}

class ForexFactoryCalendarRepository implements CalendarRepository {
  ForexFactoryCalendarRepository({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  @override
  Future<List<EconomicEvent>> fetch() async {
    final res = await _dio.get<List<dynamic>>(
      'https://nfs.faireconomy.media/ff_calendar_thisweek.json',
      options: Options(
        headers: webSafeUserAgent(),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    final data = res.data ?? <dynamic>[];
    final out = <EconomicEvent>[];
    for (final raw in data) {
      if (raw is! Map) continue;
      final country = (raw['country'] ?? '').toString();
      if (country != 'USD') continue;
      final impactRaw = (raw['impact'] ?? '').toString().toLowerCase();
      final impact = switch (impactRaw) {
        'high' => NewsImpact.high,
        'medium' => NewsImpact.medium,
        'low' => NewsImpact.low,
        _ => NewsImpact.low,
      };
      final when = DateTime.tryParse((raw['date'] ?? '').toString());
      if (when == null) continue;
      out.add(EconomicEvent(
        title: (raw['title'] ?? 'Event').toString(),
        country: country,
        time: when.toLocal(),
        impact: impact,
        forecast: raw['forecast']?.toString(),
        previous: raw['previous']?.toString(),
      ));
    }
    return out;
  }
}

class CompositeCalendarRepository implements CalendarRepository {
  CompositeCalendarRepository({CalendarRepository? live, CalendarRepository? fallback})
      : _live = live ?? ForexFactoryCalendarRepository(),
        _fallback = fallback ?? MockCalendarRepository();

  final CalendarRepository _live;
  final CalendarRepository _fallback;

  @override
  Future<List<EconomicEvent>> fetch() async {
    try {
      final events = await _live.fetch();
      if (events.isNotEmpty) return events;
    } catch (_) {}
    return _fallback.fetch();
  }
}
