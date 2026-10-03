import 'dart:math';

enum PanelType { threeXui, alireza, marzban }

extension PanelTypeX on PanelType {
  String get label => switch (this) {
        PanelType.threeXui => '3X-UI',
        PanelType.alireza => 'Alireza X-UI',
        PanelType.marzban => 'Marzban',
      };

  String get shortLabel => switch (this) {
        PanelType.threeXui => '3X-UI',
        PanelType.alireza => 'Alireza',
        PanelType.marzban => 'Marzban',
      };
}

class PanelConfig {
  const PanelConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.url,
    this.username = '',
    this.password = '',
    this.token = '',
    this.allowInsecure = false,
    this.openWeb = false,
  });

  final String id;
  final String name;
  final PanelType type;
  final String url;
  final String username;
  final String password;

  /// Marzban only: an access token used instead of username/password.
  final String token;

  /// Accept self-signed / invalid TLS certificates.
  final bool allowInsecure;

  /// Tapping the panel opens its own web UI (like the panel's PWA) instead of
  /// the app's screens.
  final bool openWeb;

  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(9999)}';

  String get baseUrl => normalizePanelUrl(url);

  String get host => Uri.tryParse(baseUrl)?.host ?? '';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'url': url,
        'username': username,
        'password': password,
        'token': token,
        'allowInsecure': allowInsecure,
        'openWeb': openWeb,
      };

  factory PanelConfig.fromJson(Map<String, dynamic> j) => PanelConfig(
        id: j['id']?.toString() ?? newId(),
        name: j['name']?.toString() ?? '',
        type: PanelType.values.firstWhere((t) => t.name == j['type'],
            orElse: () => PanelType.threeXui),
        url: j['url']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
        password: j['password']?.toString() ?? '',
        token: j['token']?.toString() ?? '',
        allowInsecure: j['allowInsecure'] == true,
        openWeb: j['openWeb'] == true,
      );
}

// Trailing path segments people often paste from the browser address bar.
const _strippable = {
  'panel', 'inbounds', 'login', 'xui', 'dashboard', 'docs', 'api', //
  'settings', 'xray', 'clients',
};

/// Turns whatever the user pasted into `scheme://host[:port][/webBasePath]`
/// with no trailing slash.
String normalizePanelUrl(String input) {
  var s = input.trim();
  final hash = s.indexOf('#');
  if (hash >= 0) s = s.substring(0, hash);
  final q = s.indexOf('?');
  if (q >= 0) s = s.substring(0, q);
  if (s.isEmpty) return s;
  if (!s.contains('://')) s = 'https://$s';
  final uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty) return s;
  final segs = uri.pathSegments.where((e) => e.isNotEmpty).toList();
  while (segs.isNotEmpty && _strippable.contains(segs.last.toLowerCase())) {
    segs.removeLast();
  }
  final path = segs.isEmpty ? '' : '/${segs.join('/')}';
  return '${uri.scheme}://${uri.authority}$path';
}
