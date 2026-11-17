import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config.dart';

class AppSettings {
  final bool demoMode;
  final String geminiKey;
  final String groqKey;
  final String openRouterKey;
  final String finnhubKey;
  final Set<String> disabledModels;
  final double minConfidence;
  final int blackoutMinutes;
  final bool notificationsEnabled;
  final String interval;
  final double balance;
  final double riskPercent;

  const AppSettings({
    // Off by default: the app opens on the realtime FOREX.com XAUUSD feed.
    this.demoMode = false,
    this.geminiKey = AppKeys.gemini,
    this.groqKey = AppKeys.groq,
    this.openRouterKey = AppKeys.openRouter,
    this.finnhubKey = AppKeys.finnhub,
    this.disabledModels = const <String>{},
    this.minConfidence = TradingConfig.minConfirmConfidence,
    this.blackoutMinutes = TradingConfig.defaultNewsBlackoutMinutes,
    this.notificationsEnabled = true,
    this.interval = '5m',
    this.balance = 1000,
    this.riskPercent = TradingConfig.defaultRiskPercent,
  });

  AppSettings copyWith({
    bool? demoMode,
    String? geminiKey,
    String? groqKey,
    String? openRouterKey,
    String? finnhubKey,
    Set<String>? disabledModels,
    double? minConfidence,
    int? blackoutMinutes,
    bool? notificationsEnabled,
    String? interval,
    double? balance,
    double? riskPercent,
  }) =>
      AppSettings(
        demoMode: demoMode ?? this.demoMode,
        geminiKey: geminiKey ?? this.geminiKey,
        groqKey: groqKey ?? this.groqKey,
        openRouterKey: openRouterKey ?? this.openRouterKey,
        finnhubKey: finnhubKey ?? this.finnhubKey,
        disabledModels: disabledModels ?? this.disabledModels,
        minConfidence: minConfidence ?? this.minConfidence,
        blackoutMinutes: blackoutMinutes ?? this.blackoutMinutes,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        interval: interval ?? this.interval,
        balance: balance ?? this.balance,
        riskPercent: riskPercent ?? this.riskPercent,
      );

  String keyFor(AiBackend b) {
    switch (b) {
      case AiBackend.gemini:
        return geminiKey;
      case AiBackend.groq:
        return groqKey;
      case AiBackend.openrouter:
        return openRouterKey;
      case AiBackend.local:
        return 'local';
    }
  }

  bool hasKey(AiBackend b) => b == AiBackend.local || keyFor(b).trim().isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'demoMode': demoMode,
        'disabledModels': disabledModels.toList(),
        'minConfidence': minConfidence,
        'blackoutMinutes': blackoutMinutes,
        'notificationsEnabled': notificationsEnabled,
        'interval': interval,
        'balance': balance,
        'riskPercent': riskPercent,
      };

  static AppSettings fromJson(Map<String, dynamic> j) => AppSettings(
        demoMode: j['demoMode'] as bool? ?? false,
        disabledModels: (j['disabledModels'] as List<dynamic>?)?.map((e) => e.toString()).toSet() ??
            <String>{},
        minConfidence: (j['minConfidence'] as num?)?.toDouble() ?? TradingConfig.minConfirmConfidence,
        blackoutMinutes: (j['blackoutMinutes'] as num?)?.toInt() ?? TradingConfig.defaultNewsBlackoutMinutes,
        notificationsEnabled: j['notificationsEnabled'] as bool? ?? true,
        interval: j['interval'] as String? ?? '5m',
        balance: (j['balance'] as num?)?.toDouble() ?? 1000,
        riskPercent: (j['riskPercent'] as num?)?.toDouble() ?? TradingConfig.defaultRiskPercent,
      );
}

class SettingsService {
  SettingsService({FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;

  static const String _prefsKey = 'app_settings_v1';
  static const String _kGemini = 'k_gemini';
  static const String _kGroq = 'k_groq';
  static const String _kOpenRouter = 'k_openrouter';
  static const String _kFinnhub = 'k_finnhub';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    var settings = raw == null ? const AppSettings() : AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    try {
      final g = await _secure.read(key: _kGemini);
      final gr = await _secure.read(key: _kGroq);
      final or = await _secure.read(key: _kOpenRouter);
      final fh = await _secure.read(key: _kFinnhub);
      settings = settings.copyWith(
        geminiKey: (g ?? '').isNotEmpty ? g : settings.geminiKey,
        groqKey: (gr ?? '').isNotEmpty ? gr : settings.groqKey,
        openRouterKey: (or ?? '').isNotEmpty ? or : settings.openRouterKey,
        finnhubKey: (fh ?? '').isNotEmpty ? fh : settings.finnhubKey,
      );
    } catch (_) {
      // Secure storage can fail on unsupported platforms — ignore.
    }
    return settings;
  }

  Future<void> save(AppSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(s.toJson()));
    try {
      await _secure.write(key: _kGemini, value: s.geminiKey);
      await _secure.write(key: _kGroq, value: s.groqKey);
      await _secure.write(key: _kOpenRouter, value: s.openRouterKey);
      await _secure.write(key: _kFinnhub, value: s.finnhubKey);
    } catch (_) {}
  }
}
