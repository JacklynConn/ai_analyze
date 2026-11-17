import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settingsService = SettingsService();
  final settings = await settingsService.load();

  final notifications = NotificationService();
  await notifications.init();

  runApp(
    ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(settingsService),
        notificationServiceProvider.overrideWithValue(notifications),
        settingsProvider.overrideWith(() => SettingsController(initial: settings)),
      ],
      child: const XauusdAiTraderApp(),
    ),
  );
}
