import 'dart:convert';

import '../utils/json.dart';

/// Turns a share link (vless://, vmess://, trojan://, ss://) into an Xray
/// outbound object. Throws [FormatException] when the link can't be read.
Map<String, dynamic> outboundFromLink(String link) {
  final l = link.trim();
  final scheme = l.split('://').first.toLowerCase();
  return switch (scheme) {
    'vless' || 'trojan' => _fromUrl(scheme, Uri.parse(l)),
    'vmess' => _fromVmess(l.substring(8)),
    'ss' => _fromSs(l),
    _ => throw const FormatException('Unsupported link. Use vless://, vmess://, trojan:// or ss://'),
  };
}

String _b64(String s) {
  var t = s.trim().replaceAll('-', '+').replaceAll('_', '/');
  t = t.padRight(t.length + (4 - t.length % 4) % 4, '=');
  return utf8.decode(base64.decode(t));
}

String _tag(String? fragment, String fallback) {
  final f = Uri.decodeComponent(fragment ?? '').trim();
  return f.isNotEmpty ? f : fallback;
}

List<String> _csv(String? v) =>
    (v ?? '').split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

/// streamSettings from the usual query parameters of vless/trojan links.
Map<String, dynamic> _stream(Map<String, String> q, {String defaultSecurity = 'none'}) {
  final net = q['type']?.isNotEmpty == true ? q['type']! : 'tcp';
  final security = q['security']?.isNotEmpty == true ? q['security']! : defaultSecurity;
  final host = q['host'] ?? '';
  final path = q['path'] ?? '';
  final s = <String, dynamic>{'network': net, 'security': security};
  switch (net) {
    case 'ws':
      s['wsSettings'] = {'path': path.isEmpty ? '/' : path, if (host.isNotEmpty) 'host': host};
    case 'httpupgrade':
      s['httpupgradeSettings'] = {'path': path.isEmpty ? '/' : path, if (host.isNotEmpty) 'host': host};
    case 'xhttp' || 'splithttp':
      s['network'] = 'xhttp';
      s['xhttpSettings'] = {
        'path': path.isEmpty ? '/' : path,
        if (host.isNotEmpty) 'host': host,
        if ((q['mode'] ?? '').isNotEmpty) 'mode': q['mode'],
      };
    case 'grpc':
      s['grpcSettings'] = {
        'serviceName': q['serviceName'] ?? path,
        if ((q['authority'] ?? '').isNotEmpty) 'authority': q['authority'],
        'multiMode': q['mode'] == 'multi',
      };
    case 'kcp':
      s['kcpSettings'] = {
        'header': {'type': q['headerType'] ?? 'none'},
        if ((q['seed'] ?? '').isNotEmpty) 'seed': q['seed'],
      };
    case 'tcp' || 'raw':
      if (q['headerType'] == 'http') {
        s['tcpSettings'] = {
          'header': {
            'type': 'http',
            'request': {
              'path': path.isEmpty ? ['/'] : _csv(path),
              'headers': {if (host.isNotEmpty) 'Host': _csv(host)},
            },
          },
        };
      }
  }
  final sni = q['sni'] ?? q['peer'] ?? '';
  final fp = q['fp'] ?? '';
  if (security == 'tls') {
    s['tlsSettings'] = {
      if (sni.isNotEmpty) 'serverName': sni,
      if (fp.isNotEmpty) 'fingerprint': fp,
      if (_csv(q['alpn']).isNotEmpty) 'alpn': _csv(q['alpn']),
      if (q['allowInsecure'] == '1' || q['insecure'] == '1') 'allowInsecure': true,
    };
  } else if (security == 'reality') {
    s['realitySettings'] = {
      if (sni.isNotEmpty) 'serverName': sni,
      'fingerprint': fp.isEmpty ? 'chrome' : fp,
      'publicKey': q['pbk'] ?? '',
      'shortId': q['sid'] ?? '',
      if ((q['spx'] ?? '').isNotEmpty) 'spiderX': q['spx'],
      if ((q['pqv'] ?? '').isNotEmpty) 'mldsa65Verify': q['pqv'],
    };
  }
  return s;
}

Map<String, dynamic> _fromUrl(String scheme, Uri u) {
  if (u.host.isEmpty || !u.hasPort) throw const FormatException('Link has no host or port.');
  final q = u.queryParameters;
  final secret = Uri.decodeComponent(u.userInfo);
  if (secret.isEmpty) throw const FormatException('Link has no user id / password.');
  final server = <String, dynamic>{'address': u.host, 'port': u.port};
  final Map<String, dynamic> settings;
  if (scheme == 'vless') {
    settings = {
      'vnext': [
        {
          ...server,
          'users': [
            {
              'id': secret,
              'encryption': q['encryption']?.isNotEmpty == true ? q['encryption'] : 'none',
              if ((q['flow'] ?? '').isNotEmpty) 'flow': q['flow'],
            }
          ],
        }
      ],
    };
  } else {
    settings = {
      'servers': [
        {...server, 'password': secret}
      ],
    };
  }
  return {
    'tag': _tag(u.fragment, scheme),
    'protocol': scheme,
    'settings': settings,
    'streamSettings': _stream(q, defaultSecurity: scheme == 'trojan' ? 'tls' : 'none'),
  };
}

Map<String, dynamic> _fromVmess(String body) {
  final Map<String, dynamic> j;
  try {
    j = asMap(jsonDecode(_b64(body.split('#').first)));
  } catch (_) {
    throw const FormatException('Invalid vmess link.');
  }
  final address = asStr(j['add']) ?? '';
  final port = asInt(j['port']);
  final id = asStr(j['id']) ?? '';
  if (address.isEmpty || port == null || id.isEmpty) {
    throw const FormatException('vmess link is missing address, port or id.');
  }
  final tls = asStr(j['tls']) ?? '';
  final q = <String, String>{
    'type': asStr(j['net']) ?? 'tcp',
    'security': tls.isEmpty ? 'none' : tls,
    'host': asStr(j['host']) ?? '',
    'path': asStr(j['path']) ?? '',
    'headerType': asStr(j['type']) ?? '',
    'sni': asStr(j['sni']) ?? '',
    'fp': asStr(j['fp']) ?? '',
    'alpn': asStr(j['alpn']) ?? '',
    if (asStr(j['net']) == 'grpc') 'serviceName': asStr(j['path']) ?? '',
    if (asStr(j['net']) == 'grpc' && asStr(j['type']) == 'multi') 'mode': 'multi',
  };
  return {
    'tag': _tag(asStr(j['ps']), 'vmess'),
    'protocol': 'vmess',
    'settings': {
      'vnext': [
        {
          'address': address,
          'port': port,
          'users': [
            {
              'id': id,
              'alterId': asInt(j['aid']) ?? 0,
              'security': (asStr(j['scy']) ?? '').isEmpty ? 'auto' : asStr(j['scy']),
            }
          ],
        }
      ],
    },
    'streamSettings': _stream(q),
  };
}

Map<String, dynamic> _fromSs(String link) {
  var rest = link.substring(5);
  var tag = 'shadowsocks';
  final hash = rest.indexOf('#');
  if (hash >= 0) {
    tag = _tag(rest.substring(hash + 1), tag);
    rest = rest.substring(0, hash);
  }
  rest = rest.split('?').first.replaceAll(RegExp(r'/$'), '');
  String userInfo, hostPort;
  final at = rest.lastIndexOf('@');
  if (at >= 0) {
    userInfo = Uri.decodeComponent(rest.substring(0, at));
    hostPort = rest.substring(at + 1);
    if (!userInfo.contains(':')) userInfo = _b64(userInfo);
  } else {
    // Old style: the whole "method:pass@host:port" is base64.
    final all = _b64(rest);
    final i = all.lastIndexOf('@');
    if (i < 0) throw const FormatException('Invalid ss link.');
    userInfo = all.substring(0, i);
    hostPort = all.substring(i + 1);
  }
  final colon = userInfo.indexOf(':');
  final pColon = hostPort.lastIndexOf(':');
  final port = pColon < 0 ? null : int.tryParse(hostPort.substring(pColon + 1));
  if (colon < 0 || port == null) throw const FormatException('Invalid ss link.');
  var host = hostPort.substring(0, pColon);
  if (host.startsWith('[') && host.endsWith(']')) host = host.substring(1, host.length - 1);
  return {
    'tag': tag,
    'protocol': 'shadowsocks',
    'settings': {
      'servers': [
        {
          'address': host,
          'port': port,
          'method': userInfo.substring(0, colon),
          'password': userInfo.substring(colon + 1),
        }
      ],
    },
  };
}

/// Ready-made outbounds offered in the "add" menu.
Map<String, dynamic> outboundTemplate(String kind) => switch (kind) {
      'freedom' => {
          'tag': 'direct',
          'protocol': 'freedom',
          'settings': {'domainStrategy': 'AsIs'},
        },
      'blackhole' => {
          'tag': 'blocked',
          'protocol': 'blackhole',
          'settings': <String, dynamic>{},
        },
      'socks' => {
          'tag': 'socks-out',
          'protocol': 'socks',
          'settings': {
            'servers': [
              {'address': '127.0.0.1', 'port': 1080}
            ],
          },
        },
      'http' => {
          'tag': 'http-out',
          'protocol': 'http',
          'settings': {
            'servers': [
              {'address': '127.0.0.1', 'port': 8080}
            ],
          },
        },
      _ => {
          'tag': 'warp',
          'protocol': 'wireguard',
          'settings': {
            'secretKey': '',
            'address': ['172.16.0.2/32'],
            'peers': [
              {'publicKey': '', 'endpoint': 'engage.cloudflareclient.com:2408'}
            ],
          },
        },
    };
