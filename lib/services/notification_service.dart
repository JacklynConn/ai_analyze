import 'package:material_ui/material_ui.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/theme.dart';
import '../models/news_item.dart';
import '../models/signal.dart';

/// Local (on-device) alerts. No push server involved: the app itself decides
/// when a setup is confirmed and fires an OS notification.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;
  String? _lastSignature;
  int _id = 1000;

  static const String _channelId = 'xauusd_signals';
  static const String _channelName = 'XAUUSD AI Signals';
  static const String _newsChannelId = 'xauusd_news';
  static const String _newsChannelName = 'XAUUSD News Risk';

  Future<void> init({void Function(String payload)? onTap}) async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: (response) => onTap?.call(response.payload ?? ''),
      );

      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Confirmed BUY / SELL signals for XAUUSD',
          importance: Importance.max,
          playSound: true,
        ));
        await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
          _newsChannelId,
          _newsChannelName,
          description: 'High-impact macro events that can move gold',
          importance: Importance.high,
        ));
        await androidPlugin.requestNotificationsPermission();
      }
      final iosPlugin =
          _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);
      _ready = true;
    } catch (e) {
      debugPrint('NotificationService init failed: $e');
    }
  }

  Future<void> showSignal(TradeSignal signal, {required double balance, required double riskPercent}) async {
    if (!_ready) return;
    final plan = signal.plan;
    final signature = '${signal.action.name}:${plan?.entry.toStringAsFixed(1)}:${signal.createdAt.millisecondsSinceEpoch ~/ 60000}';
    if (signature == _lastSignature) return;
    _lastSignature = signature;

    final isBuy = signal.action == TradeAction.buy;
    final title = '${isBuy ? '🟢 BUY' : '🔴 SELL'} XAUUSD confirmed · ${(signal.confidence * 100).toStringAsFixed(0)}%';
    final lots = plan?.lotsFor(balance: balance, riskPercent: riskPercent) ?? 0;
    final body = plan == null
        ? signal.reasons.take(2).join(' · ')
        : 'Entry ${plan.entry.toStringAsFixed(2)} · SL ${plan.stopLoss.toStringAsFixed(2)} · '
            'TP1 ${plan.takeProfit1.toStringAsFixed(2)} · TP2 ${plan.takeProfit2.toStringAsFixed(2)} · '
            '${lots.toStringAsFixed(2)} lots @ ${riskPercent.toStringAsFixed(1)}% risk';

    await _plugin.show(
      id: _id++,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Confirmed XAUUSD signals',
          importance: Importance.max,
          priority: Priority.high,
          color: isBuy ? AppColors.buy : AppColors.sell,
          styleInformation: BigTextStyleInformation(body),
          ticker: title,
        ),
        iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true, interruptionLevel: InterruptionLevel.timeSensitive),
      ),
      payload: signal.id,
    );
  }

  Future<void> showEventReminder(EconomicEvent event, {int minutesBefore = 30}) async {
    if (!_ready) return;
    final body = '${event.title} (${event.country}) at '
        '${event.time.hour.toString().padLeft(2, '0')}:${event.time.minute.toString().padLeft(2, '0')} — '
        'spread may widen, signals are paused around releases.';
    await _plugin.show(
      id: _id++,
      title: '⚠️ High-impact event in ${minutesBefore}m',
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _newsChannelId,
          _newsChannelName,
          channelDescription: 'High-impact macro events',
          importance: Importance.high,
          priority: Priority.high,
          color: AppColors.wait,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
      payload: 'event:${event.title}',
    );
  }

  Future<void> showTest() async {
    if (!_ready) return;
    await _plugin.show(
      id: _id++,
      title: '🔔 Alerts are working',
      body: 'You will be notified here the moment XAUUSD gives a confirmed setup.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(_channelId, _channelName, importance: Importance.max, priority: Priority.high),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
