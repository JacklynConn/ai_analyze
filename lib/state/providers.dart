import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analysis/signal_engine.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import 'dashboard_controller.dart';

final Provider<SettingsService> settingsServiceProvider =
    Provider<SettingsService>((Ref ref) => SettingsService());

final Provider<NotificationService> notificationServiceProvider =
    Provider<NotificationService>((Ref ref) => NotificationService());

class SettingsController extends Notifier<AppSettings> {
  SettingsController({this.initial});

  final AppSettings? initial;

  @override
  AppSettings build() => initial ?? const AppSettings();

  Future<void> update(AppSettings next) async {
    state = next;
    await ref.read(settingsServiceProvider).save(next);
  }
}

final NotifierProvider<SettingsController, AppSettings> settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

final Provider<SignalEngine> signalEngineProvider = Provider<SignalEngine>((Ref ref) {
  final s = ref.watch(settingsProvider);
  return SignalEngine(minConfidence: s.minConfidence, blackoutMinutes: s.blackoutMinutes);
});

final NotifierProvider<DashboardController, DashboardState> dashboardProvider =
    NotifierProvider<DashboardController, DashboardState>(DashboardController.new);
