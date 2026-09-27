import 'dart:convert';

import 'json.dart';

/// The panel's Xray config template, with helpers for the outbounds and
/// routing sections. Unknown keys are kept as they are.
class XrayTemplate {
  XrayTemplate(this.root);

  factory XrayTemplate.parse(String json) =>
      XrayTemplate(Map<String, dynamic>.from(asMap(jsonDecode(json))));

  final Map<String, dynamic> root;

  String encode() => const JsonEncoder.withIndent('  ').convert(root);

  List<Map<String, dynamic>> _list(Map<String, dynamic> parent, String key) {
    final v = parent[key];
    if (v is List<Map<String, dynamic>>) return v;
    final list = [
      for (final e in (v is List ? v : const [])) Map<String, dynamic>.from(asMap(e)),
    ];
    parent[key] = list;
    return list;
  }

  List<Map<String, dynamic>> get outbounds => _list(root, 'outbounds');

  Map<String, dynamic> get routing {
    final v = root['routing'];
    if (v is Map<String, dynamic>) return v;
    final m = Map<String, dynamic>.from(asMap(v));
    root['routing'] = m;
    return m;
  }

  List<Map<String, dynamic>> get rules => _list(routing, 'rules');

  String get domainStrategy => asStr(routing['domainStrategy']) ?? 'AsIs';
  set domainStrategy(String v) => routing['domainStrategy'] = v;

  List<String> get outboundTags => [
        for (final o in outbounds)
          if ((asStr(o['tag']) ?? '').isNotEmpty) asStr(o['tag'])!,
      ];

  List<String> get balancerTags => [
        for (final b in _list(routing, 'balancers'))
          if ((asStr(b['tag']) ?? '').isNotEmpty) asStr(b['tag'])!,
      ];

  List<String> get inboundTags => [
        for (final i in asList(root['inbounds']))
          if ((asStr(asMap(i)['tag']) ?? '').isNotEmpty) asStr(asMap(i)['tag'])!,
      ];

  /// Number of routing rules that send traffic to [tag].
  int rulesUsing(String tag) => rules.where((r) => r['outboundTag'] == tag).length;

  /// [base], or base-2, base-3 … when that tag is taken.
  String uniqueTag(String base, {String? except}) {
    final taken = outboundTags.where((t) => t != except).toSet();
    final clean = base.trim().isEmpty ? 'proxy' : base.trim();
    if (!taken.contains(clean)) return clean;
    var i = 2;
    while (taken.contains('$clean-$i')) {
      i++;
    }
    return '$clean-$i';
  }
}

/// "address:port" of an outbound's first server, if it has one.
String? outboundTarget(Map<String, dynamic> o) {
  final st = asMap(o['settings']);
  final endpoint = asStr(asMap(asList(st['peers']).firstOrNull)['endpoint']);
  if (endpoint != null && endpoint.isNotEmpty) return endpoint;
  final server = asMap([...asList(st['vnext']), ...asList(st['servers'])].firstOrNull);
  final addr = asStr(server['address']) ?? (st['address'] is String ? st['address'] as String : null);
  if (addr == null || addr.isEmpty) return null;
  final port = asInt(server['port']) ?? asInt(st['port']);
  return port == null ? addr : '$addr:$port';
}

/// Rule match fields shown in the list, in display order.
const ruleMatchKeys = [
  'domain',
  'ip',
  'port',
  'sourcePort',
  'network',
  'protocol',
  'inboundTag',
  'user',
  'source',
];

/// Short "key: a, b, c" lines describing what a rule matches.
List<String> ruleSummary(Map<String, dynamic> rule, {int maxItems = 3}) {
  final out = <String>[];
  for (final k in ruleMatchKeys) {
    final v = rule[k];
    if (v == null) continue;
    final items = v is List ? v.map((e) => '$e').toList() : '$v'.split(',');
    final clean = items.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (clean.isEmpty) continue;
    final more = clean.length > maxItems ? ' +${clean.length - maxItems}' : '';
    out.add('$k: ${clean.take(maxItems).join(', ')}$more');
  }
  return out;
}
