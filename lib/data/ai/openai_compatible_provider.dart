import 'package:dio/dio.dart';

import '../../core/config.dart';
import '../../models/signal.dart';
import 'ai_provider.dart';

/// Base for every provider that speaks the OpenAI chat-completions dialect
/// (Groq, OpenRouter, Together, Cerebras, local Ollama/vLLM ...).
class OpenAiCompatibleProvider implements AiProvider {
  OpenAiCompatibleProvider({
    required this.spec,
    required this.apiKey,
    required this.baseUrl,
    this.extraHeaders = const <String, String>{},
    Dio? dio,
  }) : _dio = dio ?? Dio();

  @override
  final AiModelSpec spec;
  final String apiKey;
  final String baseUrl;
  final Map<String, String> extraHeaders;
  final Dio _dio;

  @override
  bool get isConfigured => apiKey.trim().isNotEmpty;

  @override
  Future<ModelVote> analyze(MarketContext ctx) async {
    final sw = Stopwatch()..start();
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/chat/completions',
        options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            ...extraHeaders,
          },
          receiveTimeout: const Duration(seconds: 30),
        ),
        data: <String, dynamic>{
          'model': spec.model,
          'temperature': 0.15,
          'max_tokens': 400,
          'response_format': <String, dynamic>{'type': 'json_object'},
          'messages': <Map<String, String>>[
            <String, String>{'role': 'system', 'content': ctx.systemPrompt},
            <String, String>{'role': 'user', 'content': ctx.buildUserPrompt()},
          ],
        },
      );
      final content = res.data?['choices']?[0]?['message']?['content']?.toString() ?? '';
      final json = extractJson(content);
      if (json == null) {
        return ModelVote(
          modelId: spec.id,
          label: spec.label,
          action: TradeAction.noTrade,
          confidence: 0,
          error: 'unparsable answer',
          latency: sw.elapsed,
        );
      }
      return voteFromJson(spec: spec, json: json, latency: sw.elapsed);
    } on DioException catch (e) {
      return ModelVote(
        modelId: spec.id,
        label: spec.label,
        action: TradeAction.noTrade,
        confidence: 0,
        latency: sw.elapsed,
        error: e.response?.statusCode != null ? 'HTTP ${e.response!.statusCode}' : 'network error',
      );
    } catch (e) {
      return ModelVote(
        modelId: spec.id,
        label: spec.label,
        action: TradeAction.noTrade,
        confidence: 0,
        latency: sw.elapsed,
        error: e.toString().substring(0, e.toString().length.clamp(0, 60)),
      );
    }
  }
}

class GroqProvider extends OpenAiCompatibleProvider {
  GroqProvider({required super.apiKey, required super.spec, super.dio})
      : super(baseUrl: 'https://api.groq.com/openai/v1');
}

class OpenRouterProvider extends OpenAiCompatibleProvider {
  OpenRouterProvider({required super.apiKey, required super.spec, super.dio})
      : super(
          baseUrl: 'https://openrouter.ai/api/v1',
          extraHeaders: const <String, String>{
            'HTTP-Referer': 'https://xauusd-ai-trader.app',
            'X-Title': 'XAUUSD AI Trader',
          },
        );
}

/// For a self-hosted Ollama / LM Studio / vLLM endpoint.
class LocalServerProvider extends OpenAiCompatibleProvider {
  LocalServerProvider({required super.baseUrl, required super.spec, super.dio})
      : super(apiKey: 'local');
}
