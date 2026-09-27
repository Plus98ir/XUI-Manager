import '../l10n.dart';
import '../models/models.dart';

/// Isolates a left-to-right fragment (numbers, units, "3 / 5") inside
/// right-to-left text so it is not reordered.
String ltr(String s) => '\u2066$s\u2069';

String fmtBytes(num? bytes, {int decimals = 2}) {
  if (bytes == null) return '-';
  if (bytes <= 0) return ltr('0 B');
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return ltr('${v.toStringAsFixed(i == 0 ? 0 : decimals)} ${units[i]}');
}

String fmtSpeed(num? bytesPerSec) =>
    bytesPerSec == null ? '-' : '${fmtBytes(bytesPerSec)}/s';

String fmtUptime(int? secs, S s) {
  if (secs == null) return '-';
  final d = secs ~/ 86400;
  final h = (secs % 86400) ~/ 3600;
  final m = (secs % 3600) ~/ 60;
  if (d > 0) return '$d ${s.t('days')} $h ${s.t('hours')}';
  if (h > 0) return '$h ${s.t('hours')} $m ${s.t('minutes')}';
  return '$m ${s.t('minutes')}';
}

String _pad2(int v) => v.toString().padLeft(2, '0');

String fmtDate(DateTime? d) => d == null
    ? '-'
    : ltr('${d.year}-${_pad2(d.month)}-${_pad2(d.day)} ${_pad2(d.hour)}:${_pad2(d.minute)}');

String fmtExpiry(PanelUser u, S s) {
  if (u.expiryDaysAfterFirstUse != null) {
    return s.n('days_after_first_use', u.expiryDaysAfterFirstUse!);
  }
  if (u.expiry == null) return s.t('unlimited');
  final diff = u.expiry!.difference(DateTime.now());
  if (diff.isNegative) return s.t('expired');
  if (diff.inDays >= 1) return s.n('days_left', diff.inDays);
  return s.n('hours_left', diff.inHours);
}

String fmtTraffic(PanelUser u, S s) =>
    u.total > 0 ? ltr('${fmtBytes(u.used)} / ${fmtBytes(u.total)}') : '${fmtBytes(u.used)} / ${s.t('unlimited')}';

String bytesToGbText(int bytes) {
  if (bytes <= 0) return '0';
  final g = bytes / 1073741824;
  return g == g.roundToDouble() ? g.toInt().toString() : g.toStringAsFixed(2);
}
