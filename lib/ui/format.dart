import 'package:intl/intl.dart';

/// `5:07` (min:sec per km), or `--:--` when unknown.
String formatPace(double? secPerKm) {
  if (secPerKm == null || !secPerKm.isFinite || secPerKm > 60 * 60) {
    return '--:--';
  }
  final total = secPerKm.round();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// `1:02:03` or `12:34`.
String formatDuration(Duration d) {
  // Round like formatPace does, so a 1 km split shows the same time and pace.
  final total = (d.inMilliseconds / 1000).round();
  final h = total ~/ 3600;
  final m = total ~/ 60 % 60;
  final s = (total % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// Distance in km with two decimals, without unit: `5.23`.
String formatKm(double meters) => (meters / 1000).toStringAsFixed(2);

String formatDate(DateTime t) => DateFormat.yMMMEd().format(t);

String formatDateTime(DateTime t) =>
    '${DateFormat.yMMMEd().format(t)} · ${DateFormat.Hm().format(t)}';

/// "Morning run", "Evening run"…
String runTitle(DateTime t) {
  final h = t.hour;
  final part = h < 5
      ? 'Night'
      : h < 12
      ? 'Morning'
      : h < 14
      ? 'Lunch'
      : h < 18
      ? 'Afternoon'
      : h < 22
      ? 'Evening'
      : 'Night';
  return '$part run';
}
