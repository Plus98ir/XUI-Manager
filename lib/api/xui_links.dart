import 'dart:convert';

import '../utils/json.dart';

/// Builds share links (vless://, vmess://, trojan://, ss://) for an x-ui
/// client, the same way the panel's own "share" dialog does.
List<String> buildXuiLinks(
    Map<String, dynamic> inbound, Map<String, dynamic> client, String panelHost) {
  try {
    return _build(inbound, client, panelHost);
  } catch (_) {
    return const [];
  }
}

class _Target {
  const _Target(this.host, this.port, this.remark, this.forceTls);
  final String host;
  final int port;
  final String remark;
  final String forceTls; // same | tls | none
}

List<String> _build(
    Map<String, dynamic> inbound, Map<String, dynamic> client, String panelHost) {
  final protocol = asStr(inbound['protocol']) ?? '';
  if (!const {'vmess', 'vless', 'trojan', 'shadowsocks'}.contains(protocol)) {
    return const [];
  }
  final stream = asMap(inbound['streamSettings']);
  final settings = asMap(inbound['settings']);
  final email = asStr(client['email']) ?? '';
  final baseRemark =
      [asStr(inbound['remark']) ?? '', email].where((e) => e.isNotEmpty).join('-');
  final port = asInt(inbound['port']) ?? 0;

  final targets = <_Target>[];
  for (final e in asList(stream['externalProxy'])) {
    final m = asMap(e);
    final dest = asStr(m['dest']) ?? '';
    if (dest.isEmpty) continue;
    final r = asStr(m['remark']) ?? '';
    targets.add(_Target(dest, asInt(m['port']) ?? port,
        r.isEmpty ? baseRemark : '$baseRemark-$r', asStr(m['forceTls']) ?? 'same'));
  }
  if (targets.isEmpty) {
    // 3X-UI 3.x lets each inbound set its own share address.
    final share = asStr(inbound['shareAddr']) ?? '';
    targets.add(_Target(share.isNotEmpty ? share : panelHost, port, baseRemark, 'same'));
  }

  return targets
      .map((t) => _link(protocol, stream, settings, client, t))
      .whereType<String>()
      .toList();
}

String _hostPart(String h) => h.contains(':') && !h.startsWith('[') ? '[$h]' : h;

String? _headerHost(Map<String, dynamic> headers) {
  final v = headers['Host'] ?? headers['host'];
  if (v is List && v.isNotEmpty) return v.first.toString();
  if (v is String && v.isNotEmpty) return v;
  return null;
}

void _putIf(Map<String, String> p, String k, String? v) {
  if (v != null && v.isNotEmpty) p[k] = v;
}

Map<String, String> _streamParams(Map<String, dynamic> stream, String security) {
  final p = <String, String>{};
  final net = asStr(stream['network']) ?? 'tcp';
  p['type'] = net;
  switch (net) {
    case 'tcp':
      {
        final header = asMap(asMap(stream['tcpSettings'])['header']);
        if (asStr(header['type']) == 'http') {
          p['headerType'] = 'http';
          final req = asMap(header['request']);
          final paths = asList(req['path']);
          if (paths.isNotEmpty) p['path'] = paths.first.toString();
          _putIf(p, 'host', _headerHost(asMap(req['headers'])));
        }
      }
    case 'ws':
      {
        final ws = asMap(stream['wsSettings']);
        p['path'] = asStr(ws['path']) ?? '/';
        final host = asStr(ws['host']) ?? '';
        _putIf(p, 'host', host.isNotEmpty ? host : _headerHost(asMap(ws['headers'])));
      }
    case 'grpc':
      {
        final g = asMap(stream['grpcSettings']);
        p['serviceName'] = asStr(g['serviceName']) ?? '';
        _putIf(p, 'authority', asStr(g['authority']));
        if (g['multiMode'] == true) p['mode'] = 'multi';
      }
    case 'httpupgrade':
      {
        final h = asMap(stream['httpupgradeSettings']);
        p['path'] = asStr(h['path']) ?? '/';
        final host = asStr(h['host']) ?? '';
        _putIf(p, 'host', host.isNotEmpty ? host : _headerHost(asMap(h['headers'])));
      }
    case 'xhttp':
    case 'splithttp':
      {
        final x = asMap(stream['xhttpSettings'] ?? stream['splithttpSettings']);
        p['path'] = asStr(x['path']) ?? '/';
        final host = asStr(x['host']) ?? '';
        _putIf(p, 'host', host.isNotEmpty ? host : _headerHost(asMap(x['headers'])));
        _putIf(p, 'mode', asStr(x['mode']));
      }
    case 'kcp':
      {
        final k = asMap(stream['kcpSettings']);
        p['headerType'] = asStr(asMap(k['header'])['type']) ?? 'none';
        _putIf(p, 'seed', asStr(k['seed']));
      }
  }

  p['security'] = security;
  if (security == 'tls') {
    final tls = asMap(stream['tlsSettings']);
    final ts = asMap(tls['settings']);
    _putIf(p, 'sni', asStr(tls['serverName']));
    _putIf(p, 'fp', asStr(ts['fingerprint']));
    _putIf(p, 'alpn', asList(tls['alpn']).join(','));
    if (ts['allowInsecure'] == true) p['allowInsecure'] = '1';
  } else if (security == 'reality') {
    final r = asMap(stream['realitySettings']);
    final rs = asMap(r['settings']);
    _putIf(p, 'pbk', asStr(rs['publicKey']));
    p['fp'] = asStr(rs['fingerprint']) ?? 'chrome';
    final names = asList(r['serverNames']);
    if (names.isNotEmpty) _putIf(p, 'sni', names.first.toString());
    final sids = asList(r['shortIds']);
    if (sids.isNotEmpty) _putIf(p, 'sid', sids.first.toString());
    _putIf(p, 'spx', asStr(rs['spiderX']));
  }
  return p;
}

String _query(Map<String, String> p) =>
    p.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');

String? _link(String protocol, Map<String, dynamic> stream, Map<String, dynamic> settings,
    Map<String, dynamic> client, _Target t) {
  final sec = t.forceTls == 'same' || t.forceTls.isEmpty
      ? (asStr(stream['security']) ?? 'none')
      : t.forceTls;
  final params = _streamParams(stream, sec);
  final addr = '${_hostPart(t.host)}:${t.port}';
  final frag = Uri.encodeComponent(t.remark);

  switch (protocol) {
    case 'vless':
      {
        final id = asStr(client['id']) ?? '';
        if (id.isEmpty) return null;
        params['encryption'] = asStr(settings['encryption']) ?? 'none';
        final flow = asStr(client['flow']) ?? '';
        if (flow.isNotEmpty && params['type'] == 'tcp' && (sec == 'tls' || sec == 'reality')) {
          params['flow'] = flow;
        }
        return 'vless://$id@$addr?${_query(params)}#$frag';
      }
    case 'trojan':
      {
        final pw = asStr(client['password']) ?? '';
        if (pw.isEmpty) return null;
        return 'trojan://${Uri.encodeComponent(pw)}@$addr?${_query(params)}#$frag';
      }
    case 'vmess':
      {
        final m = <String, dynamic>{
          'v': '2',
          'ps': t.remark,
          'add': t.host,
          'port': t.port,
          'id': asStr(client['id']) ?? '',
          'scy': asStr(client['security']) ?? 'auto',
          'aid': 0,
          'net': params['type'],
          'type': params['headerType'] ?? 'none',
          'host': params['host'] ?? params['authority'] ?? '',
          'path': params['path'] ?? params['serviceName'] ?? params['seed'] ?? '',
          'tls': sec == 'tls' ? 'tls' : '',
          'sni': params['sni'] ?? '',
          'alpn': params['alpn'] ?? '',
          'fp': params['fp'] ?? '',
        };
        if (params['type'] == 'grpc' && params['mode'] == 'multi') m['type'] = 'multi';
        return 'vmess://${base64.encode(utf8.encode(jsonEncode(m)))}';
      }
    case 'shadowsocks':
      {
        final method = asStr(settings['method']) ?? '';
        final clientMethod = asStr(client['method']) ?? '';
        final clientPw = asStr(client['password']) ?? '';
        String userinfo;
        if (method.startsWith('2022')) {
          final serverPw = asStr(settings['password']) ?? '';
          userinfo = '$method:${serverPw.isEmpty ? clientPw : '$serverPw:$clientPw'}';
        } else {
          userinfo = '${clientMethod.isNotEmpty ? clientMethod : method}:$clientPw';
        }
        final q = Map<String, String>.of(params);
        if (sec != 'tls') q.remove('security');
        if (q['type'] == 'tcp' && !q.containsKey('headerType')) q.remove('type');
        final qs = q.isEmpty ? '' : '?${_query(q)}';
        final b64 = base64Url.encode(utf8.encode(userinfo)).replaceAll('=', '');
        return 'ss://$b64@$addr$qs#$frag';
      }
  }
  return null;
}
