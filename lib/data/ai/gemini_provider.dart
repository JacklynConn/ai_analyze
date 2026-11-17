import 'package:dio/dio.dart';

import '../../core/config.dart';
import '../../models/signal.dart';
import 'ai_provider.dart';

/// Google AI Studio — Gemini API (generous free tier, no credit card).
class GeminiProvider implements AiProvider {
  GeminiProvider({required this.apiKey, required this.spec, Dio? dio}) : _dio = dio ?? Dio();

  final String apiKey;
  @override
  final AiModelSpec spec;
  final Dio _dio;

  @override
  bool get isConfigured => apiKey.trim().isNotEmpty;

  @override
  Future<ModelVote> analyze(MarketContext ctx) async {
    final sw = Stopwatch()..start();
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'https://generativelanguage.googleapis.com/v1beta/models/${spec.model}:generateContent',
        queryParameters: <String, dynamic>{'key': apiKey},
        options: Options(receiveTimeout: const Duration(seconds: 30)),
        data: <String, dynamic>{
          'systemInstruction': <String, dynamic>{
            'parts': <dynamic>[
              <String, String>{'text': ctx.systemPrompt},
            ],
          },
          'contents': <dynamic>[
            <String, dynamic>{
              'role': 'user',
              'parts': <dynamic>[
                <String, String>{'text': ctx.buildUserPrompt()},
              ],
            },
          ],
          'generationConfig': <String, dynamic>{
            'temperature': 0.15,
            'maxOutputTokens': 700,
            'responseMimeType': 'application/json',
          },
        },
      );
      final candidates = res.data?['candidates'] as List<dynamic>?;
      var text = '';
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates.first['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List<dynamic>?;
        if (parts != null) {
          text = parts
              .map((dynamic p) => ((p as Map<String, dynamic>)['text'] ?? '').toString())
              .join();
        }
      }
      final json = extractJson(text);
      if (json == null) {
        return ModelVote(
          modelId: spec.id,
          label: spec.label,
          action: TradeAction.noTrade,
          confidence: 0,
          latency: sw.elapsed,
          error: 'unparsable answer',
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
        error: 'error',
      );
    }
  }
}
