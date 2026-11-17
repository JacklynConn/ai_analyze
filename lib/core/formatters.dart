import 'package:intl/intl.dart';

final NumberFormat _price = NumberFormat('#,##0.00');
final NumberFormat _compact = NumberFormat('#,##0.0');

String fmtPrice(double v) => _price.format(v);
String fmtPips(double v) => v.toStringAsFixed(2);
String fmtSigned(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}';
String fmtCompact(num v) => _compact.format(v);

DateFormat fmtTime = DateFormat('HH:mm');
DateFormat fmtDayTime = DateFormat('dd MMM HH:mm');
DateFormat fmtDay = DateFormat('EEE dd MMM');

String fmtAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

String fmtCountdown(Duration d) {
  if (d.isNegative) return 'now';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}
