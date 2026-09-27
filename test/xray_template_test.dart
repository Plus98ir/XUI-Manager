import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xui_manager/api/outbound_links.dart';
import 'package:xui_manager/api/xui_api.dart';
import 'package:xui_manager/models/models.dart';
import 'package:xui_manager/utils/xray_template.dart';

void main() {
  group('outboundFromLink', () {
    test('vless reality', () {
      final o = outboundFromLink(
          'vless://11111111-2222-4333-8444-555555555555@de.example.com:443?type=tcp&security=reality&sni=www.speedtest.net&fp=chrome&pbk=PUB&sid=ab12&flow=xtls-rprx-vision#DE%20exit');
      expect(o['tag'], 'DE exit');
      expect(o['protocol'], 'vless');
      final server = (o['settings']['vnext'] as List).first as Map;
      expect(server['address'], 'de.example.com');
      expect(server['port'], 443);
      final user = (server['users'] as List).first as Map;
      expect(user['id'], '11111111-2222-4333-8444-555555555555');
      expect(user['flow'], 'xtls-rprx-vision');
      expect(user['encryption'], 'none');
      final st = o['streamSettings'] as Map;
      expect(st['security'], 'reality');
      expect(st['realitySettings']['publicKey'], 'PUB');
      expect(st['realitySettings']['shortId'], 'ab12');
      expect(st['realitySettings']['serverName'], 'www.speedtest.net');
    });

    test('vless ws tls', () {
      final o = outboundFromLink(
          'vless://uuid@cdn.example.com:2053?type=ws&security=tls&path=%2Fws&host=h.example.com&sni=h.example.com&alpn=h2,http/1.1#ws');
      final st = o['streamSettings'] as Map;
      expect(st['network'], 'ws');
      expect(st['wsSettings'], {'path': '/ws', 'host': 'h.example.com'});
      expect(st['tlsSettings']['alpn'], ['h2', 'http/1.1']);
    });

    test('trojan defaults to tls', () {
      final o = outboundFromLink('trojan://secret@t.example.com:443?sni=t.example.com#tr');
      expect(o['protocol'], 'trojan');
      expect((o['settings']['servers'] as List).first['password'], 'secret');
      expect(o['streamSettings']['security'], 'tls');
    });

    test('vmess base64 json', () {
      final body = base64.encode(utf8.encode(jsonEncode({
        'v': '2',
        'ps': 'vm',
        'add': 'v.example.com',
        'port': '8443',
        'id': 'uuid',
        'aid': '0',
        'net': 'grpc',
        'path': 'svc',
        'tls': 'tls',
        'sni': 'v.example.com',
      })));
      final o = outboundFromLink('vmess://$body');
      expect(o['tag'], 'vm');
      final server = (o['settings']['vnext'] as List).first as Map;
      expect(server['port'], 8443);
      expect(o['streamSettings']['grpcSettings']['serviceName'], 'svc');
      expect(o['streamSettings']['security'], 'tls');
    });

    test('ss sip002 and legacy', () {
      final user = base64Url.encode(utf8.encode('aes-256-gcm:pass')).replaceAll('=', '');
      final a = outboundFromLink('ss://$user@1.2.3.4:8388#my%20ss');
      final sa = (a['settings']['servers'] as List).first as Map;
      expect(a['tag'], 'my ss');
      expect(sa['method'], 'aes-256-gcm');
      expect(sa['password'], 'pass');
      expect(sa['port'], 8388);

      final legacy = base64.encode(utf8.encode('chacha20-ietf-poly1305:p@ss@5.6.7.8:443'));
      final b = outboundFromLink('ss://$legacy');
      final sb = (b['settings']['servers'] as List).first as Map;
      expect(sb['address'], '5.6.7.8');
      expect(sb['password'], 'p@ss');
    });

    test('rejects unknown links', () {
      expect(() => outboundFromLink('hysteria2://x@y:1'), throwsFormatException);
      expect(() => outboundFromLink('vless://@host:443'), throwsFormatException);
    });
  });

  group('XrayTemplate', () {
    final src = jsonEncode({
      'log': {'loglevel': 'warning'},
      'outbounds': [
        {'tag': 'direct', 'protocol': 'freedom'},
        {'tag': 'blocked', 'protocol': 'blackhole'},
      ],
      'routing': {
        'rules': [
          {'type': 'field', 'outboundTag': 'blocked', 'ip': ['geoip:private']},
        ],
      },
    });

    test('edits keep unknown keys', () {
      final t = XrayTemplate.parse(src);
      t.outbounds.add({'tag': t.uniqueTag('direct'), 'protocol': 'freedom'});
      t.rules.insert(0, {'type': 'field', 'outboundTag': 'direct', 'domain': ['geosite:ir']});
      t.domainStrategy = 'IPIfNonMatch';
      final back = jsonDecode(t.encode()) as Map;
      expect(back['log'], {'loglevel': 'warning'});
      expect((back['outbounds'] as List).last['tag'], 'direct-2');
      expect((back['routing']['rules'] as List).first['domain'], ['geosite:ir']);
      expect(back['routing']['domainStrategy'], 'IPIfNonMatch');
      expect(t.rulesUsing('blocked'), 1);
    });

    test('works without outbounds or routing', () {
      final t = XrayTemplate.parse('{}');
      expect(t.outbounds, isEmpty);
      expect(t.rules, isEmpty);
      expect(t.domainStrategy, 'AsIs');
    });

    test('summary and target', () {
      expect(
          ruleSummary({
            'domain': ['a', 'b', 'c', 'd'],
            'port': '443',
          }),
          ['domain: a, b, c +1', 'port: 443']);
      expect(
          outboundTarget({
            'settings': {
              'servers': [
                {'address': 'x', 'port': 1}
              ]
            }
          }),
          'x:1');
      expect(
          outboundTarget({
            'settings': {
              'address': ['10.0.0.2/32'],
              'peers': [
                {'endpoint': 'e:2408'}
              ]
            }
          }),
          'e:2408');
    });
  });

  test('3.x accepts users on every protocol but proxies, tunnels and TUN', () {
    InboundInfo ib(String p) => InboundInfo(id: 1, tag: 't', remark: '', protocol: p);
    for (final p in ['vless', 'vmess', 'trojan', 'shadowsocks', 'hysteria', 'hysteria2', 'amneziawg']) {
      expect(XuiApi.supportsClients(ib(p), v3: true), isTrue, reason: p);
    }
    for (final p in ['socks', 'http', 'mixed', 'tunnel', 'dokodemo-door', 'tun']) {
      expect(XuiApi.supportsClients(ib(p), v3: true), isFalse, reason: p);
    }
    expect(XuiApi.supportsClients(ib('hysteria')), isFalse);
  });
}
