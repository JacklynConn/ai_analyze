import 'package:flutter/foundation.dart';

/// Headers for plain GET requests to public data endpoints.
///
/// On the web, `User-Agent` is a *forbidden header*: browsers refuse to let
/// page code set it, and Dio warns that it turns the request into a
/// non-"simple" CORS request, forcing a preflight (OPTIONS) that most of
/// these endpoints (Yahoo, TradingView, Google News) do not answer — so the
/// request fails outright in a browser.
///
/// Native platforms still send it (some endpoints 403 without one); on web
/// the browser supplies its own User-Agent anyway, so nothing is lost.
Map<String, dynamic>? webSafeUserAgent() =>
    kIsWeb ? null : const <String, dynamic>{'User-Agent': 'Mozilla/5.0'};
