/// Global configuration for the XAUUSD AI Trader app.
///
/// API keys can be provided in two ways:
///  1. At build time:  flutter run --dart-define=GEMINI_API_KEY=xxx
///  2. At runtime:     Settings screen (stored in secure storage)
class AppKeys {
  const AppKeys._();
  static const String gemini = String.fromEnvironment('GEMINI_API_KEY');
  static const String groq = String.fromEnvironment('GROQ_API_KEY');
  static const String openRouter = String.fromEnvironment('OPENROUTER_API_KEY');
  static const String newsApi = String.fromEnvironment('NEWS_API_KEY');
  static const String finnhub = String.fromEnvironment('FINNHUB_API_KEY');
}

/// Provider family of the "AI brain".
enum AiBackend { gemini, groq, openrouter, local }

class AiModelSpec {
  final AiBackend backend;
  final String label;
  final String model;
  final String note;

  const AiModelSpec({
    required this.backend,
    required this.label,
    required this.model,
    required this.note,
  });

  String get id => '${backend.name}:$model';
}

/// Free-tier models wired into the ensemble. Every one of them is optional:
/// if a key is missing, the router simply skips that model. If all cloud
/// models are unavailable the deterministic [AiBackend.local] engine answers,
/// so the app never stops working offline.
const List<AiModelSpec> kAiModels = <AiModelSpec>[
  AiModelSpec(
    backend: AiBackend.gemini,
    label: 'Gemini Flash',
    model: 'gemini-2.5-flash',
    note: 'Google AI Studio — free tier, best all-round analyst',
  ),
  AiModelSpec(
    backend: AiBackend.gemini,
    label: 'Gemini Flash-Lite',
    model: 'gemini-2.5-flash-lite',
    note: 'Google AI Studio — free tier, fastest / highest quota',
  ),
  AiModelSpec(
    backend: AiBackend.groq,
    label: 'GPT-OSS 120B',
    model: 'openai/gpt-oss-120b',
    note: 'Groq — free tier, ultra fast reasoning',
  ),
  AiModelSpec(
    backend: AiBackend.groq,
    label: 'Llama 3.3 70B',
    model: 'llama-3.3-70b-versatile',
    note: 'Groq — free tier, stable general analyst',
  ),
  AiModelSpec(
    backend: AiBackend.openrouter,
    label: 'Gemma 3 27B (free)',
    model: 'google/gemma-3-27b-it:free',
    note: 'OpenRouter — :free route',
  ),
  AiModelSpec(
    backend: AiBackend.openrouter,
    label: 'Nemotron Ultra (free)',
    model: 'nvidia/nemotron-3-ultra-550b-a55b:free',
    note: 'OpenRouter — :free route, long-context reasoner',
  ),
  AiModelSpec(
    backend: AiBackend.local,
    label: 'Rules Engine',
    model: 'ta-rules-v1',
    note: 'On-device deterministic engine — always available offline',
  ),
];

class TradingConfig {
  const TradingConfig._();

  static const String symbol = 'XAUUSD';

  /// Gold can quote with 2 or 3 decimals depending on the feed.
  static const int priceDecimals = 2;

  /// Minimum ensemble confidence required to publish a *confirmed* signal.
  static const double minConfirmConfidence = 0.66;

  /// How long a confirmed signal stays valid.
  static const Duration signalTtl = Duration(minutes: 90);

  /// Blackout window before/after a high-impact event (minutes).
  static const int defaultNewsBlackoutMinutes = 45;

  /// Hard risk guard used for position sizing display.
  static const double defaultRiskPercent = 1.0;

  static const Duration candleRefresh = Duration(seconds: 60);
  static const Duration tickRecompute = Duration(seconds: 10);
  static const Duration aiRefresh = Duration(minutes: 10);
}
