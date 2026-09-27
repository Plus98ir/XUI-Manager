import 'dart:convert';

int? asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt();
  return null;
}

double? asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

String? asStr(dynamic v) => v?.toString();

/// Accepts a Map or a JSON-encoded string (x-ui stores settings as strings).
Map<String, dynamic> asMap(dynamic v) {
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  if (v is String && v.trim().isNotEmpty) {
    try {
      final d = jsonDecode(v);
      if (d is Map) return d.map((k, val) => MapEntry(k.toString(), val));
    } catch (_) {}
  }
  return <String, dynamic>{};
}

List<dynamic> asList(dynamic v) => v is List ? v : const [];
